import Foundation

/// Project-level metadata from a `.logicx` bundle's `Resources/ProjectInformation.plist`.
///
/// See also: [LOGICX_FORMAT.md](LOGICX_FORMAT.md) for detailed format specification.
public struct LogicxProjectInformation: Codable, Sendable {
  /// Logic Pro bundle format version (e.g. 2).
  public var bundleVersion: Int {
    didSet { self["BundleVersion"] = bundleVersion }
  }
  /// Application and version that last saved the project (e.g. "Logic Pro 12.0.1 (6590)").
  public var lastSavedFrom: String {
    didSet { self["LastSavedFrom"] = lastSavedFrom }
  }
  /// Whether the project is saved as a project folder (true) or a package bundle (false).
  public var hasProjectFolder: Bool {
    didSet { self["HasProjectFolder"] = hasProjectFolder }
  }
  /// Variant (alternative) names keyed by string index (e.g. {"0": "Project"}).
  public var variantNames: [String: String] {
    didSet { self["VariantNames"] = variantNames }
  }

  // Full parsed plist for round-trip and re-serialization.
  private var plist: PlistDict
  private let format: PropertyListSerialization.PropertyListFormat
  // Original bytes when loaded from disk; nil when constructed programmatically.
  // Cleared when the plist is mutated so that data() re-serializes from the dictionary.
  private var raw: Data?

  /// Parse project information from raw plist bytes.
  ///
  /// - Parameter data: The complete `ProjectInformation.plist` file contents.
  /// - Throws: `LogicxProjectInformationError.invalidFormat` if the data is not a valid plist dictionary.
  public init(data: Data) throws {
    var fmt = PropertyListSerialization.PropertyListFormat.binary
    let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: &fmt)
    guard let dict = obj as? [String: Any] else {
      throw LogicxProjectInformationError.invalidFormat
    }
    self.plist = PlistDict(dict)
    self.format = fmt
    self.raw = data
    let content = try PropertyListDecoder().decode(Content.self, from: data)
    self.bundleVersion = content.bundleVersion
    self.lastSavedFrom = content.lastSavedFrom
    self.hasProjectFolder = content.hasProjectFolder
    self.variantNames = content.variantNames
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
    let bundleVersion: Int
    let lastSavedFrom: String
    let hasProjectFolder: Bool
    let variantNames: [String: String]
    enum CodingKeys: String, CodingKey {
      case bundleVersion = "BundleVersion"
      case lastSavedFrom = "LastSavedFrom"
      case hasProjectFolder = "HasProjectFolder"
      case variantNames = "VariantNames"
    }
    init(from decoder: Decoder) throws {
      let c = try decoder.container(keyedBy: CodingKeys.self)
      bundleVersion = try c.decode(Int.self, forKey: .bundleVersion)
      lastSavedFrom = try c.decode(String.self, forKey: .lastSavedFrom)
      hasProjectFolder = try c.decodeIfPresent(Bool.self, forKey: .hasProjectFolder) ?? false
      variantNames = try c.decode([String: String].self, forKey: .variantNames)
    }
  }
}

extension LogicxProjectInformation {
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

/// Errors thrown when parsing a `ProjectInformation.plist`.
public enum LogicxProjectInformationError: Error {
  /// The plist data could not be parsed as a valid dictionary.
  case invalidFormat
}

extension LogicxProjectInformation {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(data: try container.decode(Data.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(try data())
  }
}
