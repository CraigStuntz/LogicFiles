import Foundation

/// Errors thrown when parsing an NSKeyedArchiver blob.
public enum KeyedArchiveError: Error {
  /// The data is not a valid binary plist or does not contain an `$archiver` key.
  case invalidFormat
}

/// A control point in an `MAKeyboardLayer` curve (key scaling or velocity response).
public struct MAGraphPoint: Codable, Sendable {
  /// Horizontal position (0.0–1.0).
  public let x: Double
  /// Vertical position (0.0–1.0).
  public let y: Double
  /// Bezier control point X offset.
  public let cpx: Double
  /// Bezier control point Y offset.
  public let cpy: Double
  /// Whether this segment uses a curved interpolation.
  public let isCurve: Bool
  /// Whether this segment uses step (discontinuous) interpolation.
  public let isStep: Bool

  /// Creates a graph control point.
  ///
  /// - Parameters:
  ///   - x: Horizontal position (0.0–1.0).
  ///   - y: Vertical position (0.0–1.0).
  ///   - cpx: Bezier control point X offset.
  ///   - cpy: Bezier control point Y offset.
  ///   - isCurve: Whether this segment uses curved interpolation.
  ///   - isStep: Whether this segment uses step interpolation.
  public init(
    x: Double, y: Double, cpx: Double = 0, cpy: Double = 0, isCurve: Bool = false,
    isStep: Bool = false
  ) {
    self.x = x
    self.y = y
    self.cpx = cpx
    self.cpy = cpy
    self.isCurve = isCurve
    self.isStep = isStep
  }

  init?(_ dict: [String: Any]) {
    guard let x = dict["x"] as? Double,
      let y = dict["y"] as? Double
    else { return nil }
    self.init(
      x: x, y: y,
      cpx: dict["cpx"] as? Double ?? 0,
      cpy: dict["cpy"] as? Double ?? 0,
      isCurve: dict["isCurve"] as? Bool ?? false,
      isStep: dict["isStep"] as? Bool ?? false
    )
  }
}

/// Keyboard zone and MIDI routing settings for a Logic Pro instrument track.
///
/// Decoded from the `MAKeyboardLayer` class inside a `KeyedArchive` blob.
/// Other known MA* classes are not yet modelled as typed structs; they degrade
/// to plain `[String: Any]` in `KeyedArchive.decoded`.
public struct MAKeyboardLayer: Codable, Sendable {
  /// Lowest MIDI note accepted by this layer (0–127).
  public let lowNote: Int
  /// Highest MIDI note accepted by this layer (0–127).
  public let highNote: Int
  /// Lowest velocity accepted by this layer (1–127).
  public let lowVelocity: Int
  /// Highest velocity accepted by this layer (1–127).
  public let highVelocity: Int
  /// Semitone transpose offset.
  public let transpose: Int
  /// When true, transpose is disabled for this layer.
  public let noTranspose: Bool
  /// Keyboard split index (for multi-layer setups).
  public let keyboardIndex: Int
  /// Whether multitimbral mode is enabled.
  public let multitimbralEnabled: Bool
  /// Key scaling response curve.
  public let keyScalingGraph: [MAGraphPoint]
  /// Velocity response curve.
  public let velocityResponseGraph: [MAGraphPoint]

  /// Creates a keyboard layer with the given zone and MIDI routing settings.
  ///
  /// - Parameters:
  ///   - lowNote: Lowest MIDI note accepted (0–127).
  ///   - highNote: Highest MIDI note accepted (0–127).
  ///   - lowVelocity: Lowest velocity accepted (1–127).
  ///   - highVelocity: Highest velocity accepted (1–127).
  ///   - transpose: Semitone transpose offset.
  ///   - noTranspose: Whether transpose is disabled.
  ///   - keyboardIndex: Keyboard split index for multi-layer setups.
  ///   - multitimbralEnabled: Whether multitimbral mode is enabled.
  ///   - keyScalingGraph: Key scaling response curve control points.
  ///   - velocityResponseGraph: Velocity response curve control points.
  public init(
    lowNote: Int, highNote: Int,
    lowVelocity: Int = 1, highVelocity: Int = 127,
    transpose: Int = 0, noTranspose: Bool = false,
    keyboardIndex: Int = 0, multitimbralEnabled: Bool = false,
    keyScalingGraph: [MAGraphPoint] = [], velocityResponseGraph: [MAGraphPoint] = []
  ) {
    self.lowNote = lowNote
    self.highNote = highNote
    self.lowVelocity = lowVelocity
    self.highVelocity = highVelocity
    self.transpose = transpose
    self.noTranspose = noTranspose
    self.keyboardIndex = keyboardIndex
    self.multitimbralEnabled = multitimbralEnabled
    self.keyScalingGraph = keyScalingGraph
    self.velocityResponseGraph = velocityResponseGraph
  }

  init?(_ dict: [String: Any]) {
    guard let low = dict["lowNote"] as? Int,
      let high = dict["highNote"] as? Int
    else { return nil }
    self.init(
      lowNote: low, highNote: high,
      lowVelocity: dict["lowVelocity"] as? Int ?? 1,
      highVelocity: dict["highVelocity"] as? Int ?? 127,
      transpose: dict["transpose"] as? Int ?? 0,
      noTranspose: dict["noTranspose"] as? Bool ?? false,
      keyboardIndex: dict["keyboardIndex"] as? Int ?? 0,
      multitimbralEnabled: dict["multitimbralEnabled"] as? Bool ?? false,
      keyScalingGraph: (dict["keyScalingGraph"] as? [[String: Any]] ?? []).compactMap {
        MAGraphPoint($0)
      },
      velocityResponseGraph: (dict["velocityResponseGraph"] as? [[String: Any]] ?? []).compactMap {
        MAGraphPoint($0)
      }
    )
  }
}

/// An NSKeyedArchiver plist blob embedded within a CST plugin slot.
///
/// Raw bytes are preserved verbatim for round-trip fidelity. The `decoded`
/// property resolves the NSKeyedArchiver UID reference graph into a plain
/// `[String: Any]` dictionary. Unknown ObjC classes degrade gracefully to
/// plain dictionaries with a `__class__` key.
public struct KeyedArchive: Codable, Sendable {
  private let raw: Data
  private let _decoded: DecodedDict

  /// Parse an NSKeyedArchiver blob from raw binary plist bytes.
  ///
  /// - Parameter data: The raw binary plist data (must start with `bplist00`).
  /// - Throws: `KeyedArchiveError.invalidFormat` if the data is not a valid keyed archive.
  public init(data: Data) throws {
    guard data.starts(with: Data("bplist00".utf8)) else {
      throw KeyedArchiveError.invalidFormat
    }
    let (obj, _) = try parsePlist(from: data)
    guard let dict = obj as? [String: Any], dict["$archiver"] != nil else {
      throw KeyedArchiveError.invalidFormat
    }
    raw = data
    _decoded = DecodedDict(KeyedArchive.resolveTop(dict))
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(data: try container.decode(Data.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(raw)
  }

  /// Returns the original raw binary plist bytes verbatim.
  public func data() throws -> Data { raw }

  var byteCount: Int { raw.count }

  /// The resolved NSKeyedArchiver top-level dictionary.
  ///
  /// UID references are followed and NS collection patterns are collapsed into
  /// Swift dictionaries and arrays. Unknown ObjC classes degrade to plain
  /// dictionaries with a `__class__` key indicating the original class name.
  public var decoded: [String: Any] { _decoded.storage }

  /// The Environment Layer settings, if this archive contains an `MAKeyboardLayer`.
  public var environmentLayer: MAKeyboardLayer? {
    guard let dict = decoded["dictionary"] as? [String: Any],
      let layerDict = dict["layer"] as? [String: Any]
    else { return nil }
    return MAKeyboardLayer(layerDict)
  }

  // MARK: - UID resolver

  private static func resolveTop(_ plist: [String: Any]) -> [String: Any] {
    let objects = plist["$objects"] as? [Any] ?? []
    let top = plist["$top"] as? [String: Any] ?? [:]
    return top.mapValues { resolveVal($0, objects: objects, depth: 0) }
  }

  /// Extracts the integer value from a CFKeyedArchiverUID (__NSCFType).
  ///
  /// PropertyListSerialization returns binary plist UIDs as opaque __NSCFType objects
  /// (CFKeyedArchiverUID). There is no public Swift API to read the value directly, so
  /// we extract it from the description string, which is stable on Apple platforms:
  /// "<CFKeyedArchiverUID 0x...>{value = N}"
  private static func cfUID(from val: Any) -> Int? {
    let desc = "\(val)"
    guard desc.hasPrefix("<CFKeyedArchiverUID"),
      let valueStart = desc.range(of: "value = "),
      let valueEnd = desc[valueStart.upperBound...].firstIndex(of: "}")
    else { return nil }
    return Int(desc[valueStart.upperBound..<valueEnd])
  }

  private static func resolveVal(_ val: Any, objects: [Any], depth: Int) -> Any {
    guard depth < 32 else { return NSNull() }

    // Binary plist UID: __NSCFType (CFKeyedArchiverUID)
    if let uid = cfUID(from: val) {
      guard uid > 0, uid < objects.count else { return NSNull() }
      return resolveVal(objects[uid], objects: objects, depth: depth + 1)
    }

    if let dict = val as? [String: Any] {
      // XML plist UID: {CF$UID: N}
      if let uid = dict["CF$UID"] as? Int {
        guard uid > 0, uid < objects.count else { return NSNull() }
        return resolveVal(objects[uid], objects: objects, depth: depth + 1)
      }

      // Resolve all sub-values; handle $class and NS collection patterns
      var resolved: [String: Any] = [:]
      for (k, v) in dict where k != "$class" {
        resolved[k] = resolveVal(v, objects: objects, depth: depth + 1)
      }
      if let classRef = dict["$class"],
        let classDict = resolveVal(classRef, objects: objects, depth: depth + 1) as? [String: Any],
        let className = classDict["$classname"] as? String
      {
        // NSDictionary / NSMutableDictionary
        if let keys = resolved["NS.keys"] as? [Any],
          let objs = resolved["NS.objects"] as? [Any]
        {
          var out: [String: Any] = [:]
          for (k2, v2) in zip(keys, objs) {
            let strKey: String
            if let s = k2 as? String {
              strKey = s
            } else if let i = k2 as? Int {
              strKey = "\(i)"
            } else {
              continue
            }
            out[strKey] = v2
          }
          return out
        }
        // NSArray / NSMutableArray
        if let objs = resolved["NS.objects"] as? [Any] {
          return objs
        }
        // NSAttributedString — return the plain string content
        if className == "NSAttributedString", let str = resolved["NS.string"] as? String {
          return str
        }
        // All other classes: keep as dict with __class__ tag
        resolved["__class__"] = className
      }
      return resolved
    }

    if let arr = val as? [Any] {
      return arr.map { resolveVal($0, objects: objects, depth: depth + 1) }
    }

    // Primitive (String, Int, Double, Bool, Data, NSNull)
    return val
  }
}

/// @unchecked Sendable wrapper around `[String: Any]`.
/// Foundation's plist types (NSString, NSNumber, NSData, NSDictionary, NSArray) are
/// all immutable after construction and thread-safe, so this is safe.
private struct DecodedDict: @unchecked Sendable {
  let storage: [String: Any]
  init(_ storage: [String: Any]) { self.storage = storage }
}
