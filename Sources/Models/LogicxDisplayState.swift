import Foundation

/// Per-alternative display state from a `.logicx` bundle's `DisplayState.plist`.
///
/// The display state plist contains window layout and editor state information,
/// organized by screensets. Only top-level metadata fields are modeled as typed
/// properties; the full plist is preserved for round-trip fidelity.
///
/// See also: [LOGICX_FORMAT.md](LOGICX_FORMAT.md) for detailed format specification.
public struct LogicxDisplayState: Codable, Sendable {
  /// Display data format version.
  public var displayDataVersion: Int {
    didSet { self["displayDataVersion"] = displayDataVersion }
  }
  /// The currently active screenset slot (1-based).
  public var screensetCurrSlot: Int {
    didSet { self["screensetCurrSlot"] = screensetCurrSlot }
  }

  // Full parsed plist for round-trip and re-serialization.
  private var plist: PlistDict
  private let format: PropertyListSerialization.PropertyListFormat
  // Original bytes when loaded from disk; nil when constructed programmatically.
  // Cleared when the plist is mutated so that data() re-serializes from the dictionary.
  private var raw: Data?

  /// Parse display state from raw plist bytes.
  ///
  /// - Parameter data: The complete `DisplayState.plist` file contents.
  /// - Throws: `LogicxDisplayStateError.invalidFormat` if the data is not a valid plist dictionary.
  public init(data: Data) throws {
    var fmt = PropertyListSerialization.PropertyListFormat.binary
    let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: &fmt)
    guard let dict = obj as? [String: Any] else {
      throw LogicxDisplayStateError.invalidFormat
    }
    self.plist = PlistDict(dict)
    self.format = fmt
    self.raw = data
    let content = try PropertyListDecoder().decode(Content.self, from: data)
    self.displayDataVersion = content.displayDataVersion
    self.screensetCurrSlot = content.screensetCurrSlot
  }

  /// Serialize to plist bytes.
  ///
  /// Returns the original bytes verbatim when loaded from disk; re-serializes from
  /// the parsed plist when constructed programmatically.
  public func data() throws -> Data {
    if let raw { return raw }
    return try PropertyListSerialization.data(
      fromPropertyList: plist.storage, format: format, options: 0)
  }

  private struct Content: Decodable {
    let displayDataVersion: Int
    let screensetCurrSlot: Int
  }
}

extension LogicxDisplayState {
  /// Reads or writes a value in the underlying plist dictionary by key.
  /// Setting a value discards the stored original bytes so that `data()` re-serializes
  /// from the modified dictionary rather than returning the unmodified file.
  subscript(key: String) -> Any? {
    get { plist.storage[key] }
    set {
      var dict = plist.storage
      dict[key] = newValue
      plist = PlistDict(dict)
      raw = nil
    }
  }
}

/// Errors thrown when parsing a `DisplayState.plist`.
public enum LogicxDisplayStateError: Error {
  /// The plist data could not be parsed as a valid dictionary.
  case invalidFormat
}

extension LogicxDisplayState {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(data: try container.decode(Data.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(try data())
  }
}
