import Foundation

/// Errors thrown when parsing an AU Preset file.
public enum AupresetError: Error {
  /// The plist data could not be parsed as a valid AU Preset dictionary.
  case invalidFormat
}

/// Represents an Apple AU Preset file (.aupreset).
///
/// AU Preset files are Apple's standard format for storing Audio Unit preset data.
/// They use Property List (plist) format to store metadata and binary parameter data.
///
/// See also: [AUPRESET_FORMAT.md](AUPRESET_FORMAT.md) for detailed format specification.
public struct Aupreset: Codable, Sendable, LogicFileData {
  /// The canonical lowercase URL path extension for AU Preset files.
  public static let pathExtension = "aupreset"

  /// The plist format (binary or XML).
  public let format: PropertyListSerialization.PropertyListFormat
  /// The preset name.
  public let name: String
  /// Four-byte manufacturer code, stored as an integer.
  public let manufacturer: Int
  /// AU plugin type code (e.g. effect, instrument).
  public let type: Int
  /// AU plugin subtype code identifying the specific plugin.
  public let subtype: Int
  /// Preset format version.
  public let version: Int
  /// The embedded plugin parameter data, from the `"data"` key of the plist.
  public let payload: Data?
  /// MIDI mono mode setting. Present on some plugins.
  public let midiMonoMode: Int?
  /// Mono mode pitch range in semitones. Present on some plugins.
  public let monoModePitchRange: Int?

  // Full parsed plist stored for faithful round-trip serialization, preserving any
  // fields not yet modeled as typed properties above.
  private var plist: PlistDict

  /// Parse an AU Preset from raw plist bytes.
  ///
  /// - Parameter data: The complete `.aupreset` file contents.
  /// - Throws: `AupresetError.invalidFormat` if the data is not a valid AU Preset plist.
  public init(data: Data) throws {
    let (obj, fmt) = try parsePlist(from: data)
    guard let dict = obj as? [String: Any] else {
      throw AupresetError.invalidFormat
    }
    self.format = fmt
    self.plist = PlistDict(dict)
    self.name = dict["name"] as? String ?? ""
    self.manufacturer = dict["manufacturer"] as? Int ?? 0
    self.type = dict["type"] as? Int ?? 0
    self.subtype = dict["subtype"] as? Int ?? 0
    self.version = dict["version"] as? Int ?? 0
    self.payload = dict["data"] as? Data
    self.midiMonoMode = dict["midiMonoMode"] as? Int
    self.monoModePitchRange = dict["monoModePitchRange"] as? Int
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(data: try container.decode(Data.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(try data())
  }

  /// Serialize the AU Preset back to plist bytes.
  ///
  /// Preserves the original plist format (binary or XML) and any unknown keys
  /// not modeled as typed properties.
  public func data() throws -> Data {
    try PropertyListSerialization.data(
      fromPropertyList: plist.storage, format: format, options: 0)
  }

  /// Analyze the embedded payload (if present) using the generic `PayloadAnalyzer`.
  /// Returns candidate parameter regions found in the embedded payload.
  public func analyzePayload(windowFloats: Int = 8) throws -> [ParameterRegion] {
    guard let payloadData = self.payload else { return [] }
    return try PayloadAnalyzer.analyze(payload: payloadData, windowFloats: windowFloats)
  }

  /// The AudioUnit component triple identifying which plugin this preset belongs to.
  public var pluginIdentifier: PluginIdentifier {
    PluginIdentifier(manufacturer: manufacturer, type: type, subtype: subtype)
  }

  /// Accesses the IEEE 754 float parameter at `byteOffset` within the embedded payload.
  ///
  /// Traps if the payload is nil or the offset is out of range.
  public subscript(byteOffset byteOffset: Int) -> Float {
    get {
      guard let payload else {
        preconditionFailure("Cannot read parameter: Aupreset has no payload")
      }
      guard let value = try? readFloat(from: payload, at: byteOffset) else {
        preconditionFailure(
          "Byte offset \(byteOffset) out of range for payload of \(payload.count) bytes")
      }
      return value
    }
    set {
      guard let payload else {
        preconditionFailure("Cannot write parameter: Aupreset has no payload")
      }
      guard let newPayload = try? writingFloat(newValue, into: payload, at: byteOffset),
        let replaced = try? replacing(payload: newPayload)
      else {
        preconditionFailure(
          "Byte offset \(byteOffset) out of range for payload of \(payload.count) bytes")
      }
      self = replaced
    }
  }

  /// Returns a new `Aupreset` with the payload replaced, preserving all other plist keys.
  private func replacing(payload newPayload: Data) throws -> Aupreset {
    var dict = plist.storage
    dict["data"] = newPayload
    let serialized = try PropertyListSerialization.data(
      fromPropertyList: dict, format: format, options: 0)
    return try Aupreset(data: serialized)
  }
}

extension Aupreset {
  /// Try to detect whether the embedded payload contains a known preset format.
  /// This is a best-effort, non-throwing check that does not assume the payload
  /// is a PST file produced by Logic — it only looks for signatures and chunk patterns.
  ///
  /// Returns `.unknown` with size 0 if there is no payload.
  public func tryParsePreset() -> PresetDetection {
    guard let payload = self.payload else {
      return PresetDetection(format: .unknown, magic: nil, size: 0)
    }

    if payload.count >= 8 {
      let idData = payload.subdata(in: 0..<4)
      if let idStr = String(data: idData, encoding: .ascii),
        idStr.range(of: "^[ -~]{4}$", options: .regularExpression) != nil
      {
        let lenBE = payload.subdata(in: 4..<8).withUnsafeBytes {
          $0.load(as: UInt32.self).bigEndian
        }
        let lenLE = payload.subdata(in: 4..<8).withUnsafeBytes {
          $0.load(as: UInt32.self).littleEndian
        }
        if (Int(lenBE) + 8 <= payload.count) || (Int(lenLE) + 8 <= payload.count) {
          return PresetDetection(format: .chunked, magic: idStr, size: payload.count)
        }
      }
    }

    return PresetDetection(format: .unknown, magic: nil, size: payload.count)
  }
}
