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
    guard let versionPatches = dict["VersionPatches"] as? Int,
      let channelDicts = dict["channels"] as? [[String: Any]]
    else { throw PatchDataError.invalidFormat }
    self.versionPatches = versionPatches
    self.channels = try channelDicts.map { try PatchChannelSettings(plistDict: $0) }
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
  public var filename: String {
    didSet { setPlist("Filename", value: filename) }
  }
  /// Unique identifier for this channel strip.
  public var uuid: UUID {
    didSet { setPlist("UUID", value: uuid.uuidString) }
  }
  /// Display name shown in the channel strip.
  public var name: String {
    didSet { setPlist("Channel_name", value: name) }
  }
  /// `true` for the root channel strip; absent (i.e. `false`) for additional strips.
  public var isRoot: Bool {
    didSet {
      if isRoot { setPlist("Root", value: true) } else { removePlist("Root") }
    }
  }
  /// Whether the channel strip is muted.
  public var isMuted: Bool {
    didSet { setPlist("Channel_isMuted", value: isMuted) }
  }
  /// Whether the channel strip is soloed.
  public var isSolo: Bool {
    didSet { setPlist("Channel_isSolo", value: isSolo) }
  }
  /// Logic Pro internal instrument identifier. Meaning of specific values is unknown.
  public var instrID: Int {
    didSet { setPlist("Channel_instID", value: instrID) }
  }
  /// Index of the channel strip's audio input.
  public var inputIndex: Int {
    didSet { setPlist("Channel_inputIndex_1", value: inputIndex) }
  }
  /// Whether the input is a bus rather than a physical input.
  public var inputIsBus: Bool {
    didSet { setPlist("Channel_inputIsBus", value: inputIsBus) }
  }
  /// Whether the audio input is stereo. `nil` when absent (e.g. MIDI/instrument channel strips).
  public var inputIsStereo: Bool? {
    didSet { setPlist("Channel_inputIsStereo", value: inputIsStereo) }
  }
  /// Index of the channel strip's audio output.
  public var outputIndex: Int {
    didSet { setPlist("Channel_outputIndex", value: outputIndex) }
  }
  /// Whether the output is a bus rather than a physical output.
  public var outputIsBus: Bool {
    didSet { setPlist("Channel_outputIsBus", value: outputIsBus) }
  }
  /// Whether the output is stereo. Absent for some channel configurations (e.g. multichannel).
  public var outputIsStereo: Bool? {
    didSet { setPlist("Channel_outputIsStereo", value: outputIsStereo) }
  }
  /// MIDI receive channel for this channel strip.
  public var receiveChannel: Int {
    didSet { setPlist("Channel_receiveChannel", value: receiveChannel) }
  }
  /// Color index used in the arrange/mixer view.
  public var seqColorIndex: Int {
    didSet { setPlist("Channel_seqColorIndex", value: seqColorIndex) }
  }
  /// Icon index for the track header in the arrange window.
  public var trackIcon: Int {
    didSet { setPlist("Track_icon", value: trackIcon) }
  }
  /// Whether the user has manually edited the Smart Controls mapping.
  public var userDidModifySmartControls: Bool {
    didSet { setPlist("Channel_userDidModifySmartControls", value: userDidModifySmartControls) }
  }
  /// Channel strip category. Present on root strips; absent on additional strips in summing stacks.
  public var chaStrCategory: String? {
    didSet { setPlist("Channel_chaStrCategory", value: chaStrCategory) }
  }
  /// Send slot configurations. The populated structure is unknown; all available
  /// examples contain empty send slots.
  public var sends: [PatchSend] {
    didSet { setPlist("Channel_sends", value: sends.map { _ in [String: Any]() }) }
  }

  // Full parsed plist dictionary for round-trip fidelity; unknown keys survive mutation.
  private var plist: PlistDict

  /// The selected hardware audio input, if any.
  ///
  /// Returns `nil` when `inputIsBus` is `true` (the input is a bus, not a physical
  /// hardware input) or when `inputIsStereo` is `nil` (non-audio channel strips such
  /// as instruments).
  public var audioInput: AudioInput? {
    guard !inputIsBus, let isStereo = inputIsStereo else { return nil }
    return AudioInput(inputIndex: inputIndex, isStereo: isStereo)
  }

  private mutating func setPlist(_ key: String, value: Any?) {
    var dict = plist.storage
    if let value = value {
      dict[key] = value
    } else {
      dict.removeValue(forKey: key)
    }
    plist = PlistDict(dict)
  }

  private mutating func removePlist(_ key: String) {
    var dict = plist.storage
    dict.removeValue(forKey: key)
    plist = PlistDict(dict)
  }

  /// Initialize from a raw plist dictionary, extracting typed fields and
  /// preserving the full dictionary for round-trip serialization.
  init(plistDict dict: [String: Any]) throws {
    guard let filename = dict["Filename"] as? String,
      let uuidString = dict["UUID"] as? String,
      let uuid = UUID(uuidString: uuidString),
      let name = dict["Channel_name"] as? String,
      let isMuted = dict["Channel_isMuted"] as? Bool,
      let isSolo = dict["Channel_isSolo"] as? Bool,
      let instrID = dict["Channel_instID"] as? Int,
      let inputIndex = dict["Channel_inputIndex_1"] as? Int,
      let inputIsBus = dict["Channel_inputIsBus"] as? Bool,
      let outputIndex = dict["Channel_outputIndex"] as? Int,
      let outputIsBus = dict["Channel_outputIsBus"] as? Bool,
      let receiveChannel = dict["Channel_receiveChannel"] as? Int,
      let seqColorIndex = dict["Channel_seqColorIndex"] as? Int,
      let trackIcon = dict["Track_icon"] as? Int,
      let userDidModifySmartControls = dict["Channel_userDidModifySmartControls"] as? Bool,
      let sendsArray = dict["Channel_sends"] as? [[String: Any]]
    else { throw PatchDataError.invalidFormat }
    self.filename = filename
    self.uuid = uuid
    self.name = name
    self.isRoot = dict["Root"] as? Bool ?? false
    self.isMuted = isMuted
    self.isSolo = isSolo
    self.instrID = instrID
    self.inputIndex = inputIndex
    self.inputIsBus = inputIsBus
    self.inputIsStereo = dict["Channel_inputIsStereo"] as? Bool
    self.outputIndex = outputIndex
    self.outputIsBus = outputIsBus
    self.outputIsStereo = dict["Channel_outputIsStereo"] as? Bool
    self.receiveChannel = receiveChannel
    self.seqColorIndex = seqColorIndex
    self.trackIcon = trackIcon
    self.userDidModifySmartControls = userDidModifySmartControls
    self.chaStrCategory = dict["Channel_chaStrCategory"] as? String
    self.sends = sendsArray.map { _ in PatchSend() }
    self.plist = PlistDict(dict)
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
    plist = PlistDict([:])
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
  /// Patches typed property values into the original plist dictionary so that
  /// unknown keys survive round-trip serialization.
  fileprivate func toPlistDict() -> [String: Any] {
    plist.storage
  }
}
