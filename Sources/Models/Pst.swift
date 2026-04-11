import Foundation

// MARK: - PST Header Support

/// Represents the header of a Logic Pro PST file.
///
/// See also: [PST_FORMAT.md](PST_FORMAT.md) for detailed format specification.
struct PstHeader: Codable, Sendable {
  /// Total file size in bytes
  let fileSize: UInt32
  /// Format version (typically 1)
  let formatVersion: UInt32
  /// Data/payload size or section size
  let dataSize: UInt32
  /// Magic string: "GAMETSPP"
  let magic: String  // always "GAMETSPP"
  /// Additional format flags/version info
  let flags: UInt32

  /// Expected header size in bytes
  static let size = 24

  init(data: Data) throws {
    guard data.count >= PstHeader.size else {
      throw PstParseError.insufficientData("Need at least \(PstHeader.size) bytes for header")
    }

    let fileSize = data.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    let formatVersion = data.subdata(in: 4..<8).withUnsafeBytes {
      $0.load(as: UInt32.self).littleEndian
    }
    let dataSize = data.subdata(in: 8..<12).withUnsafeBytes {
      $0.load(as: UInt32.self).littleEndian
    }

    guard let magic = String(data: data.subdata(in: 12..<20), encoding: .ascii) else {
      throw PstParseError.invalidMagic("Could not decode magic string")
    }

    guard magic == "GAMETSPP" else {
      throw PstParseError.invalidMagic("Expected GAMETSPP, got \(magic)")
    }

    let flags = data.subdata(in: 20..<24).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

    self.fileSize = fileSize
    self.formatVersion = formatVersion
    self.dataSize = dataSize
    self.magic = magic
    self.flags = flags
  }

  func data() -> Data {
    var result = Data()
    var fs = fileSize.littleEndian
    withUnsafeBytes(of: &fs) { result.append(contentsOf: $0) }
    var fv = formatVersion.littleEndian
    withUnsafeBytes(of: &fv) { result.append(contentsOf: $0) }
    var ds = dataSize.littleEndian
    withUnsafeBytes(of: &ds) { result.append(contentsOf: $0) }
    guard let magicData = magic.data(using: .ascii) else {
      fatalError(
        "PstHeader magic string '\(magic)' is not valid ASCII — this should never happen after validation in init(data:)"
      )
    }
    result.append(magicData)
    var fl = flags.littleEndian
    withUnsafeBytes(of: &fl) { result.append(contentsOf: $0) }
    return result
  }
}

/// Represents a Logic Pro PST file with structured header parsing.
struct PstEnvelope: Codable, Sendable {
  let header: PstHeader
  /// Raw payload data following the header
  let payload: Data

  init(header: PstHeader, payload: Data) {
    self.header = header
    self.payload = payload
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawData = try container.decode(Data.self)
    self = try PstEnvelope(data: rawData)
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(data())
  }

  init(data: Data) throws {
    let header = try PstHeader(data: data)

    let payloadStart = PstHeader.size
    guard data.count >= payloadStart else {
      throw PstParseError.insufficientData("File too small to contain header")
    }

    self.header = header
    self.payload = data.subdata(in: payloadStart..<data.count)
  }

  func data() -> Data {
    var result = header.data()
    result.append(payload)
    return result
  }

  /// Returns a summary of the PST structure
  func summary() -> String {
    """
    PST Summary:
    - Format Version: \(header.formatVersion)
    - File Size: \(header.fileSize) bytes
    - Data Size: \(header.dataSize) bytes
    - Payload Size: \(payload.count) bytes
    - Flags: 0x\(String(format: "%08x", header.flags))
    """
  }
}

// MARK: - Common Error Type

/// Errors thrown when parsing a PST file.
public enum PstParseError: Error {
  /// The data is too short to contain the required structure.
  case insufficientData(String)
  /// The expected GAMETSPP magic string was not found.
  case invalidMagic(String)
}

// MARK: - Pst

/// Represents a Logic Pro Preset (PST) file.
///
/// PST files use a fixed binary format: a 24-byte GAMETSPP header followed by a payload
/// containing instrument parameter data as packed IEEE 754 floats.
///
/// The primary invariant: `init(data:)` followed by `data()` produces byte-for-byte identical output.
public struct Pst: Codable, Sendable, LogicFileData {
  /// The canonical lowercase URL path extension for PST files.
  public static let pathExtension = "pst"

  /// Parsed PST data (header + payload)
  var envelope: PstEnvelope

  /// The parameter payload (all bytes after the 24-byte header).
  public var payload: Data { envelope.payload }

  /// Magic string (always "GAMETSPP").
  public var magic: String { envelope.header.magic }
  /// Format version (typically 1).
  public var formatVersion: UInt32 { envelope.header.formatVersion }
  /// Additional format flags/version info.
  public var flags: UInt32 { envelope.header.flags }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawData = try container.decode(Data.self)
    self = try Pst(data: rawData)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(try data())
  }

  /// Parse a PST from raw file bytes.
  ///
  /// - Parameter data: The complete PST file contents (24-byte header + payload).
  /// - Throws: `PstParseError` if the data is too short or the GAMETSPP magic string is absent.
  public init(data: Data) throws {
    self.envelope = try PstEnvelope(data: data)
  }

  /// Serialize the PST back to raw file bytes.
  ///
  /// Produces byte-for-byte identical output when called on an instance created with `init(data:)`.
  public func data() throws -> Data {
    envelope.data()
  }

  /// Analyze the payload for candidate parameter regions using the generic `PayloadAnalyzer`.
  public func analyzePayload(windowFloats: Int = 8) throws -> [ParameterRegion] {
    try PayloadAnalyzer.analyze(payload: envelope.payload, windowFloats: windowFloats)
  }

  /// Accesses the IEEE 754 float parameter at `byteOffset` within the payload.
  ///
  /// Traps if the offset is out of range.
  public subscript(byteOffset byteOffset: Int) -> Float {
    get {
      guard let value = try? readFloat(from: envelope.payload, at: byteOffset) else {
        preconditionFailure(
          "Byte offset \(byteOffset) out of range for payload of \(envelope.payload.count) bytes")
      }
      return value
    }
    set {
      guard let newPayload = try? writingFloat(newValue, into: envelope.payload, at: byteOffset)
      else {
        preconditionFailure(
          "Byte offset \(byteOffset) out of range for payload of \(envelope.payload.count) bytes")
      }
      envelope = PstEnvelope(
        header: envelope.header,
        payload: newPayload
      )
    }
  }
}

extension Pst {
  /// Try to detect whether the Pst's payload contains a plugin preset blob.
  /// Returns a lightweight `PresetDetection` describing the likely nested format.
  public func tryParsePreset() -> PresetDetection {
    let payload = envelope.payload

    if payload.count >= 20 {
      if let magic = String(data: payload.subdata(in: 12..<20), encoding: .ascii),
        magic == "GAMETSPP" || magic == "PPSTEMAG"
      {
        return PresetDetection(format: .emagic, magic: magic, size: payload.count)
      }
    }

    if payload.count >= 8 {
      let idData = payload.subdata(in: 0..<4)
      let idStr = String(data: idData, encoding: .ascii) ?? ""
      let lenBE = payload.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
      let lenLE = payload.subdata(in: 4..<8).withUnsafeBytes {
        $0.load(as: UInt32.self).littleEndian
      }
      if (Int(lenBE) + 8 <= payload.count) || (Int(lenLE) + 8 <= payload.count) {
        return PresetDetection(format: .chunked, magic: idStr, size: payload.count)
      }
    }

    return PresetDetection(format: .unknown, magic: nil, size: payload.count)
  }
}
