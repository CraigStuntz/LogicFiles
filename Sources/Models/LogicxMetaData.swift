import Foundation

/// Per-alternative song metadata from a `.logicx` bundle's `MetaData.plist`.
///
/// See also: [LOGICX_FORMAT.md](LOGICX_FORMAT.md) for detailed format specification.
public struct LogicxMetaData: Codable, Sendable {
  /// Project tempo in BPM.
  public var beatsPerMinute: Double {
    didSet { self["BeatsPerMinute"] = beatsPerMinute }
  }
  /// Audio sample rate in Hz (e.g. 48000).
  public var sampleRate: Int {
    didSet { self["SampleRate"] = sampleRate }
  }
  /// Musical key (e.g. "C").
  public var songKey: String {
    didSet { self["SongKey"] = songKey }
  }
  /// Mode — "major" or "minor".
  public var songGenderKey: String {
    didSet { self["SongGenderKey"] = songGenderKey }
  }
  /// Time signature numerator.
  public var songSignatureNumerator: Int {
    didSet { self["SongSignatureNumerator"] = songSignatureNumerator }
  }
  /// Time signature denominator.
  public var songSignatureDenominator: Int {
    didSet { self["SongSignatureDenominator"] = songSignatureDenominator }
  }
  /// Number of tracks in this alternative.
  public var numberOfTracks: Int {
    didSet { self["NumberOfTracks"] = numberOfTracks }
  }
  /// Metadata format version.
  public var version: Int {
    didSet { self["Version"] = version }
  }

  // Full parsed plist for round-trip and re-serialization.
  private var plist: PlistDict
  private let format: PropertyListSerialization.PropertyListFormat
  // Original bytes when loaded from disk; nil when constructed programmatically.
  // Cleared when the plist is mutated so that data() re-serializes from the dictionary.
  private var raw: Data?

  /// Parse metadata from raw plist bytes.
  ///
  /// - Parameter data: The complete `MetaData.plist` file contents.
  /// - Throws: `LogicxMetaDataError.invalidFormat` if the data is not a valid plist dictionary.
  public init(data: Data) throws {
    var fmt = PropertyListSerialization.PropertyListFormat.binary
    let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: &fmt)
    guard let dict = obj as? [String: Any] else {
      throw LogicxMetaDataError.invalidFormat
    }
    self.plist = PlistDict(dict)
    self.format = fmt
    self.raw = data
    let content = try PropertyListDecoder().decode(Content.self, from: data)
    self.beatsPerMinute = content.beatsPerMinute
    self.sampleRate = content.sampleRate
    self.songKey = content.songKey
    self.songGenderKey = content.songGenderKey
    self.songSignatureNumerator = content.songSignatureNumerator
    self.songSignatureDenominator = content.songSignatureDenominator
    self.numberOfTracks = content.numberOfTracks
    self.version = content.version
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
    let beatsPerMinute: Double
    let sampleRate: Int
    let songKey: String
    let songGenderKey: String
    let songSignatureNumerator: Int
    let songSignatureDenominator: Int
    let numberOfTracks: Int
    let version: Int
    enum CodingKeys: String, CodingKey {
      case beatsPerMinute = "BeatsPerMinute"
      case sampleRate = "SampleRate"
      case songKey = "SongKey"
      case songGenderKey = "SongGenderKey"
      case songSignatureNumerator = "SongSignatureNumerator"
      case songSignatureDenominator = "SongSignatureDenominator"
      case numberOfTracks = "NumberOfTracks"
      case version = "Version"
    }
  }
}

extension LogicxMetaData {
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

/// Errors thrown when parsing a `MetaData.plist`.
public enum LogicxMetaDataError: Error {
  /// The plist data could not be parsed as a valid dictionary.
  case invalidFormat
}

extension LogicxMetaData {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(data: try container.decode(Data.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(try data())
  }
}
