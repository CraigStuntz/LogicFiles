import Foundation

/// The top-level structure of a Logic Pro patch bundle's `data.plist` file.
public struct PatchData: Codable, Sendable {
  /// Logic Pro format version.
  public var versionPatches: Int {
    didSet { updatePlist("VersionPatches", value: versionPatches) }
  }
  /// Per-channel settings, one entry per `.cst` file in the patch.
  public var channels: [PatchChannelSettings] {
    didSet { updatePlist("channels", value: channels.map { $0.toPlistDict() }) }
  }

  // Full parsed plist stored for faithful round-trip serialization, preserving any
  // fields not yet modeled as typed properties above.
  private var plist: PlistDict
  private var format: PropertyListSerialization.PropertyListFormat
  // Original bytes when loaded from disk; nil when constructed programmatically.
  // Cleared when a property is mutated so that data() re-serializes from the dictionary.
  private var raw: Data?

  /// Parse patch data from raw plist bytes.
  ///
  /// - Parameter data: The complete `data.plist` file contents.
  /// - Throws: `PatchDataError.invalidFormat` if the data is not a valid patch data plist.
  public init(data: Data) throws {
    var fmt = PropertyListSerialization.PropertyListFormat.binary
    let obj = try PropertyListSerialization.propertyList(from: data, options: [], format: &fmt)
    guard let dict = obj as? [String: Any] else {
      throw PatchDataError.invalidFormat
    }
    self.plist = PlistDict(dict)
    self.format = fmt
    self.raw = data
    let content = try PropertyListDecoder().decode(Content.self, from: data)
    self.versionPatches = content.versionPatches
    self.channels = content.channels
  }

  /// Serialize the patch data back to plist bytes.
  ///
  /// Returns the original bytes verbatim when loaded from disk; re-serializes from
  /// the parsed plist when constructed programmatically or when a property has been mutated.
  public func data() throws -> Data {
    if let raw { return raw }
    return try PropertyListSerialization.data(
      fromPropertyList: plist.storage, format: format, options: 0)
  }

  private mutating func updatePlist(_ key: String, value: Any) {
    var dict = plist.storage
    dict[key] = value
    plist = PlistDict(dict)
    raw = nil
  }

  private struct Content: Decodable {
    let versionPatches: Int
    let channels: [PatchChannelSettings]
    enum CodingKeys: String, CodingKey {
      case versionPatches = "VersionPatches"
      case channels
    }
  }
}

/// Errors thrown when parsing a patch data plist.
public enum PatchDataError: Error {
  /// The plist data could not be parsed as a valid patch data dictionary.
  case invalidFormat
}

extension PatchData {
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    try self.init(data: try container.decode(Data.self))
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(try data())
  }
}

/// Settings for a single channel strip within a patch bundle.
///
/// Each entry corresponds to one `.cst` file in the patch and stores the channel strip's
/// surface-level settings (name, routing, mute/solo state, etc.) from `data.plist`.
public struct PatchChannelSettings: Codable, Sendable {
  /// Filename of the corresponding `.cst` file (e.g. `"#Root.cst"`).
  public var filename: String
  /// Unique identifier for this channel strip.
  public var uuid: UUID
  /// Display name shown in the channel strip.
  public var name: String
  /// `true` for the root channel strip; absent (i.e. `false`) for additional strips.
  public var isRoot: Bool
  /// Whether the channel strip is muted.
  public var isMuted: Bool
  /// Whether the channel strip is soloed.
  public var isSolo: Bool
  /// Logic Pro internal instrument identifier. Meaning of specific values is unknown.
  public var instrID: Int
  /// Index of the channel strip's audio input.
  public var inputIndex: Int
  /// Whether the input is a bus rather than a physical input.
  public var inputIsBus: Bool
  /// Whether the audio input is stereo. `nil` when absent (e.g. MIDI/instrument channel strips).
  public var inputIsStereo: Bool?
  /// Index of the channel strip's audio output.
  public var outputIndex: Int
  /// Whether the output is a bus rather than a physical output.
  public var outputIsBus: Bool
  /// Whether the output is stereo. Absent for some channel configurations (e.g. multichannel).
  public var outputIsStereo: Bool?
  /// MIDI receive channel for this channel strip.
  public var receiveChannel: Int
  /// Color index used in the arrange/mixer view.
  public var seqColorIndex: Int
  /// Icon index for the track header in the arrange window.
  public var trackIcon: Int
  /// Whether the user has manually edited the Smart Controls mapping.
  public var userDidModifySmartControls: Bool
  /// Channel strip category. Present on root strips; absent on additional strips in summing stacks.
  public var chaStrCategory: String?
  /// Send slot configurations. The populated structure is unknown; all available
  /// examples contain empty send slots.
  public var sends: [PatchSend]

  /// The selected hardware audio input, if any.
  ///
  /// Returns `nil` when `inputIsBus` is `true` (the input is a bus, not a physical
  /// hardware input) or when `inputIsStereo` is `nil` (non-audio channel strips such
  /// as instruments).
  public var audioInput: AudioInput? {
    guard !inputIsBus, let isStereo = inputIsStereo else { return nil }
    return AudioInput(inputIndex: inputIndex, isStereo: isStereo)
  }

  enum CodingKeys: String, CodingKey {
    case filename = "Filename"
    case uuid = "UUID"
    case name = "Channel_name"
    case isRoot = "Root"
    case isMuted = "Channel_isMuted"
    case isSolo = "Channel_isSolo"
    case instrID = "Channel_instID"
    case inputIndex = "Channel_inputIndex_1"
    case inputIsBus = "Channel_inputIsBus"
    case inputIsStereo = "Channel_inputIsStereo"
    case outputIndex = "Channel_outputIndex"
    case outputIsBus = "Channel_outputIsBus"
    case outputIsStereo = "Channel_outputIsStereo"
    case receiveChannel = "Channel_receiveChannel"
    case seqColorIndex = "Channel_seqColorIndex"
    case trackIcon = "Track_icon"
    case userDidModifySmartControls = "Channel_userDidModifySmartControls"
    case chaStrCategory = "Channel_chaStrCategory"
    case sends = "Channel_sends"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    filename = try c.decode(String.self, forKey: .filename)
    let uuidString = try c.decode(String.self, forKey: .uuid)
    guard let parsed = UUID(uuidString: uuidString) else {
      throw DecodingError.dataCorruptedError(
        forKey: .uuid, in: c,
        debugDescription: "Invalid UUID: \(uuidString)")
    }
    uuid = parsed
    name = try c.decode(String.self, forKey: .name)
    isRoot = try c.decodeIfPresent(Bool.self, forKey: .isRoot) ?? false
    isMuted = try c.decode(Bool.self, forKey: .isMuted)
    isSolo = try c.decode(Bool.self, forKey: .isSolo)
    instrID = try c.decode(Int.self, forKey: .instrID)
    inputIndex = try c.decode(Int.self, forKey: .inputIndex)
    inputIsBus = try c.decode(Bool.self, forKey: .inputIsBus)
    inputIsStereo = try c.decodeIfPresent(Bool.self, forKey: .inputIsStereo)
    outputIndex = try c.decode(Int.self, forKey: .outputIndex)
    outputIsBus = try c.decode(Bool.self, forKey: .outputIsBus)
    outputIsStereo = try c.decodeIfPresent(Bool.self, forKey: .outputIsStereo)
    receiveChannel = try c.decode(Int.self, forKey: .receiveChannel)
    seqColorIndex = try c.decode(Int.self, forKey: .seqColorIndex)
    trackIcon = try c.decode(Int.self, forKey: .trackIcon)
    userDidModifySmartControls = try c.decode(Bool.self, forKey: .userDidModifySmartControls)
    chaStrCategory = try c.decodeIfPresent(String.self, forKey: .chaStrCategory)
    sends = try c.decode([PatchSend].self, forKey: .sends)
  }
}

/// A send slot configuration within a channel strip.
///
/// The populated structure is unknown — all available examples have empty send slots.
/// Expand this type when populated examples are available.
public struct PatchSend: Codable, Sendable {}

extension PatchChannelSettings {
  /// Re-encode to the plist dictionary representation used in `data.plist`.
  ///
  /// Mirrors the CodingKeys mapping so that mutations to typed properties are
  /// correctly reflected when `PatchData.data()` re-serializes the plist.
  fileprivate func toPlistDict() -> [String: Any] {
    var dict: [String: Any] = [:]
    dict["Filename"] = filename
    dict["UUID"] = uuid.uuidString
    dict["Channel_name"] = name
    if isRoot { dict["Root"] = true }
    dict["Channel_isMuted"] = isMuted
    dict["Channel_isSolo"] = isSolo
    dict["Channel_instID"] = instrID
    dict["Channel_inputIndex_1"] = inputIndex
    dict["Channel_inputIsBus"] = inputIsBus
    if let v = inputIsStereo { dict["Channel_inputIsStereo"] = v }
    dict["Channel_outputIndex"] = outputIndex
    dict["Channel_outputIsBus"] = outputIsBus
    if let v = outputIsStereo { dict["Channel_outputIsStereo"] = v }
    dict["Channel_receiveChannel"] = receiveChannel
    dict["Channel_seqColorIndex"] = seqColorIndex
    dict["Track_icon"] = trackIcon
    dict["Channel_userDidModifySmartControls"] = userDidModifySmartControls
    if let v = chaStrCategory { dict["Channel_chaStrCategory"] = v }
    dict["Channel_sends"] = sends.map { _ in [String: Any]() }
    return dict
  }
}
