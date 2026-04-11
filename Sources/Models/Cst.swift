import Foundation

/// Represents a plugin setting that can be either a PST or AU Preset file.
public enum PluginSetting: Codable, Sendable {
  /// A Logic Pro Preset (PST) binary plugin setting.
  case pst(Pst)
  /// An Apple AU Preset plist plugin setting.
  case aupreset(Aupreset)
  /// An NSKeyedArchiver plist blob. Raw bytes preserved verbatim; UID graph accessible via `decoded`.
  case keyedArchive(KeyedArchive)
  /// A plugin whose format is not yet modelled. Raw bytes preserved verbatim.
  case unknown(Data)

  /// True for system/metadata blocks that are not user-visible plugins.
  var isSystemBlock: Bool {
    switch self {
    case .unknown, .keyedArchive: return true
    case .pst, .aupreset: return false
    }
  }

  func data() throws -> Data {
    switch self {
    case .pst(let pst): return try pst.data()
    case .aupreset(let au): return try au.data()
    case .keyedArchive(let archive): return try archive.data()
    case .unknown(let raw): return raw
    }
  }

  /// The AudioUnit component triple, if available.
  ///
  /// Returns non-nil for `.aupreset` (which carries manufacturer/type/subtype in its plist).
  /// Returns nil for `.pst`, `.keyedArchive`, and `.unknown`.
  public var pluginIdentifier: PluginIdentifier? {
    switch self {
    case .aupreset(let au): return au.pluginIdentifier
    case .pst, .keyedArchive, .unknown: return nil
    }
  }

  /// Accesses the IEEE 754 float parameter at `byteOffset` within the plugin's payload.
  ///
  /// Traps if used on `.keyedArchive` or `.unknown`, or if the offset is out of range.
  public subscript(byteOffset byteOffset: Int) -> Float {
    get {
      switch self {
      case .pst(let pst): return pst[byteOffset: byteOffset]
      case .aupreset(let au): return au[byteOffset: byteOffset]
      case .keyedArchive, .unknown:
        preconditionFailure("No parameter payload for \(self)")
      }
    }
    set {
      switch self {
      case .pst(var pst):
        pst[byteOffset: byteOffset] = newValue
        self = .pst(pst)
      case .aupreset(var au):
        au[byteOffset: byteOffset] = newValue
        self = .aupreset(au)
      case .keyedArchive, .unknown:
        preconditionFailure("No parameter payload for \(self)")
      }
    }
  }
}

/// A UCuA sub-container block within a CST file.
///
/// - `plugin`: a parseable plugin setting, split into the UCuA wrapper prefix,
///   the plugin payload, and any trailing suffix bytes inside the block.
/// - `opaque`: a block whose content could not be parsed as a plugin (e.g. a
///   patch-reference record); stored verbatim for round-trip fidelity.
private enum CstBlock: Sendable {
  case plugin(prefix: Data, setting: PluginSetting, suffix: Data)
  case opaque(Data)

  func serialized() throws -> Data {
    switch self {
    case .plugin(let prefix, let setting, let suffix):
      let pluginData = try setting.data()
      var raw = prefix + pluginData + suffix
      // Recalculate the UCuA block size field at offset 28 (LE uint32).
      // The field value = total block size - 36.
      let newSizeField = UInt32(raw.count - 36)
      var le = newSizeField.littleEndian
      withUnsafeBytes(of: &le) { raw.replaceSubrange(28..<32, with: $0) }
      return raw
    case .opaque(let bytes):
      return bytes
    }
  }

  var pluginSetting: PluginSetting? {
    if case .plugin(_, let s, _) = self { return s }
    return nil
  }
}

/// Represents a Logic Pro Channel Strip (CST) file.
///
/// A CST file contains an **ordered collection** of plugin settings (PST and AU Preset files).
/// Each setting corresponds to one plugin (instrument or effect) in the channel strip.
/// The order matters because it determines the signal flow.
///
/// - A CST can contain a maximum of one instrument plugin; nil when no instrument is selected
/// - The instrument slot is present in both Instrument and Track channel strips; only absent when empty
/// - If it has an instrument, it can have zero or more MIDI plugins
/// - Both Track and Instrument channel strips can have zero or more audio FX plugins
/// - Not all embedded files have filenames; some are just raw data
///
/// See also: [CST_FORMAT.md](CST_FORMAT.md) for detailed format specification.
public struct Cst: Codable, Sendable, LogicFileData {
  /// The canonical lowercase URL path extension for CST files.
  public static let pathExtension = "cst"

  /// Outer OCuA container header (bytes before the first UCuA block).
  private var ocuaHeader: Data

  /// UCuA sub-container blocks in signal-flow order.
  private var blocks: [CstBlock]

  /// Trailing OCuA footer bytes after all UCuA blocks.
  private var ocuaFooter: Data

  // MARK: - Public plugin properties (computed from blocks)

  /// All user-visible parseable plugin settings in signal-flow order (system blocks excluded).
  private var pluginSettings: [PluginSetting] {
    blocks.compactMap { $0.pluginSetting }.filter { !$0.isSystemBlock }
  }

  /// The instrument plugin, if any (maximum one).
  ///
  /// Uses the role byte at UCuA block offset 187 (0x08 = instrument) for real Logic CSTs.
  /// Falls back to "first PST" heuristic for from-scratch CSTs with short block prefixes.
  public var instrument: PluginSetting? {
    for block in blocks {
      guard case .plugin(let prefix, let setting, _) = block else { continue }
      if setting.isSystemBlock { continue }
      if prefix.count > 187 {
        // Bit 0x08 = instrument. 0x18 (RS Antimatter) also has this bit set.
        if prefix[187] & 0x08 != 0 { return setting }
      } else {
        // Short-prefix (from-scratch) fallback: first PST is the instrument.
        if case .pst = setting { return setting }
      }
    }
    return nil
  }

  /// MIDI plugins (only present in Instrument channel strips, not Track channel strips; may be present without an instrument).
  ///
  /// Uses the role byte at UCuA block offset 187 (0x02 = MIDI FX) for real Logic CSTs.
  /// From-scratch CSTs with short block prefixes cannot distinguish MIDI FX from audio FX.
  public var midiPlugins: [PluginSetting] {
    var result: [PluginSetting] = []
    for block in blocks {
      guard case .plugin(let prefix, let setting, _) = block else { continue }
      if setting.isSystemBlock { continue }
      if prefix.count > 187, prefix[187] & 0x02 != 0, prefix[187] & 0x08 == 0 {
        result.append(setting)
      }
    }
    return result
  }

  /// Audio FX plugins (present in both Track and Instrument channel strips).
  ///
  /// Uses the role byte at UCuA block offset 187 (excludes 0x08 instrument and 0x02 MIDI FX)
  /// for real Logic CSTs. Falls back to "all non-first-PST" for from-scratch CSTs.
  public var audioFxPlugins: [PluginSetting] {
    var result: [PluginSetting] = []
    var seenFirstPst = false
    for block in blocks {
      guard case .plugin(let prefix, let setting, _) = block else { continue }
      if setting.isSystemBlock { continue }
      if prefix.count > 187 {
        let role = prefix[187]
        // Exclude instrument (bit 0x08) and MIDI FX (bit 0x02).
        if role & 0x08 == 0 && role & 0x02 == 0 { result.append(setting) }
      } else {
        // Short-prefix (from-scratch) fallback: skip the first PST (instrument).
        if case .pst = setting {
          if seenFirstPst { result.append(setting) } else { seenFirstPst = true }
        } else {
          result.append(setting)
        }
      }
    }
    return result
  }

  /// The keyboard layer settings for this channel strip, if present.
  ///
  /// Returns the `MAKeyboardLayer` from the first `KeyedArchive` block that contains one.
  /// Present in Instrument channel strips with a keyboard range configured; nil for Track channel strips
  /// and Instrument channel strips with no keyboard range. Note: Session Player tracks store theirs in
  /// an opaque slot ≥ 12, so this property also returns nil for them.
  public var environmentLayer: MAKeyboardLayer? {
    for block in blocks {
      guard case .plugin(_, let setting, _) = block else { continue }
      guard case .keyedArchive(let archive) = setting else { continue }
      if let layer = archive.environmentLayer { return layer }
    }
    return nil
  }

  // MARK: - Mutation

  /// The number of user-visible plugin slots in this channel strip.
  ///
  /// Counts instruments, MIDI FX, and audio FX. Excludes system blocks such as
  /// keyboard layers (`KeyedArchive`) and opaque infrastructure slots.
  public var pluginCount: Int { pluginSettings.count }

  /// Replace the plugin at the given index (in signal-flow order among parseable plugins).
  ///
  /// Index 0 is the instrument (if present), followed by audio FX plugins.
  /// The UCuA block size field is recalculated automatically on the next call to `data()`.
  ///
  /// - Parameters:
  ///   - index: Plugin index in signal-flow order.
  ///   - newSetting: The replacement plugin data.
  ///   - presetName: Optional preset name to display in Logic Pro (e.g. "Access Codes").
  ///     The `.pst` or `.aupreset` extension is appended automatically based on plugin type.
  ///     Only applies to blocks with extended prefixes (PST and named AU blocks).
  public mutating func replacePlugin(
    at index: Int, with newSetting: PluginSetting, presetName: String? = nil
  ) {
    // Map the plugin index to the corresponding block index, skipping system blocks.
    var pluginIdx = 0
    for blockIdx in blocks.indices {
      if case .plugin(var prefix, let existingSetting, let suffix) = blocks[blockIdx] {
        if existingSetting.isSystemBlock { continue }
        if pluginIdx == index {
          if let name = presetName {
            Cst.writePresetFilename(into: &prefix, presetName: name, pluginType: newSetting)
          }
          blocks[blockIdx] = .plugin(prefix: prefix, setting: newSetting, suffix: suffix)
          return
        }
        pluginIdx += 1
      }
    }
    preconditionFailure("Plugin index \(index) out of range (have \(pluginIdx) plugins)")
  }

  /// The preset filename displayed by Logic Pro for the plugin at the given index,
  /// or `nil` if the block has no filename field.
  ///
  /// - Parameter index: Plugin index in signal-flow order (0 = instrument or first slot).
  public func presetName(at index: Int) -> String? {
    var pluginIdx = 0
    for block in blocks {
      if case .plugin(let prefix, let setting, _) = block {
        if setting.isSystemBlock { continue }
        if pluginIdx == index {
          return Cst.readPresetFilename(from: prefix)
        }
        pluginIdx += 1
      }
    }
    return nil
  }

  // MARK: - Initializers

  /// Parse a CST from raw file bytes.
  public init(data: Data) throws {
    let parsed = try Cst.parseOCuA(from: data)
    self.ocuaHeader = parsed.header
    self.blocks = parsed.blocks
    self.ocuaFooter = parsed.footer
  }

  /// Create a CST from plugin settings without raw file bytes.
  ///
  /// Generates a valid OCuA container with minimal UCuA block wrappers. The resulting
  /// file round-trips through `init(data:)` / `data()` and can be loaded by Logic Pro,
  /// although Logic uses the UCuA block prefix metadata to identify which plugin to
  /// instantiate — for from-scratch CSTs the prefix is minimal, so Logic may not
  /// associate the correct plugin UI. For full fidelity, prefer parsing a real CST
  /// with `init(data:)` and using `replacePlugin(at:with:)` to swap payloads.
  public init(
    instrument: PluginSetting?,
    midiPlugins: [PluginSetting],
    audioFxPlugins: [PluginSetting]
  ) throws {
    let allPlugins = ([instrument].compactMap { $0 }) + midiPlugins + audioFxPlugins

    // Assign slot numbers: instrument=2, then sequential from 3.
    var slot: UInt16 = 2
    var generatedBlocks: [CstBlock] = []
    for plugin in allPlugins {
      let prefix = Cst.generateUCuAPrefix(for: plugin, slot: slot)
      generatedBlocks.append(.plugin(prefix: prefix, setting: plugin, suffix: Data()))
      slot += 1
    }

    let slotCapacity = allPlugins.isEmpty ? 0 : Int(slot)
    let trackType: UInt8 = instrument != nil ? 0x43 : 0x40
    self.ocuaHeader = Cst.generateOCuAHeader(trackType: trackType, slotCapacity: slotCapacity)
    self.blocks = generatedBlocks
    self.ocuaFooter = Cst.defaultOCuAFooter
  }

  /// Create a new CST by cloning another CST's container structure and replacing
  /// plugin payloads.
  ///
  /// The template provides the OCuA header (track type, UUIDs, slot metadata),
  /// UCuA block prefixes (plugin identification that Logic uses to instantiate the
  /// correct plugin UI), system blocks, and footer. Only the plugin payloads are
  /// replaced.
  ///
  /// This is the recommended way to build CSTs that Logic Pro can fully load.
  /// The template should have at least as many plugin slots as `newPlugins`.
  ///
  /// - Parameters:
  ///   - template: A parsed CST whose structure will be cloned.
  ///   - newPlugins: Replacement plugin payloads in signal-flow order.
  ///     Must have the same count as `template.pluginCount`.
  public init(cloningStructureOf template: Cst, replacingPluginsWith newPlugins: [PluginSetting]) {
    precondition(
      newPlugins.count == template.pluginCount,
      "newPlugins count (\(newPlugins.count)) must match template plugin count (\(template.pluginCount))"
    )
    self.ocuaHeader = template.ocuaHeader
    self.ocuaFooter = template.ocuaFooter
    self.blocks = template.blocks
    var pluginIdx = 0
    for blockIdx in blocks.indices {
      if case .plugin(let prefix, let existingSetting, let suffix) = blocks[blockIdx] {
        if existingSetting.isSystemBlock { continue }
        blocks[blockIdx] = .plugin(prefix: prefix, setting: newPlugins[pluginIdx], suffix: suffix)
        pluginIdx += 1
      }
    }
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let rawData = try container.decode(Data.self)
    self = try Cst(data: rawData)
  }

  // MARK: - Serialization

  /// Serialize the CST to file bytes.
  ///
  /// For instances created with `init(data:)`, this produces byte-for-byte identical
  /// output (round-trip invariant). For instances created with
  /// `init(instrument:midiPlugins:audioFxPlugins:)`, this produces a valid OCuA
  /// container with minimal block wrappers.
  public func data() throws -> Data {
    var out = ocuaHeader
    for block in blocks {
      out += try block.serialized()
    }
    out += ocuaFooter
    return out
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(data())
  }

  // MARK: - Block prefix filename

  /// Byte range within a UCuA block prefix that holds the preset filename.
  /// 60 bytes, null-terminated, zero-padded. Only present in blocks with the
  /// 424-byte sub-header (PST and named AU blocks).
  private static let filenameRange = 50..<110

  /// Minimum prefix length required to contain the filename field.
  private static let minPrefixForFilename = 110

  /// Read the preset filename from a block prefix, or nil if the prefix
  /// doesn't have a filename field.
  private static func readPresetFilename(from prefix: Data) -> String? {
    guard prefix.count >= minPrefixForFilename else { return nil }
    let field = prefix.subdata(in: filenameRange)
    // Find null terminator
    guard let nullIndex = field.firstIndex(of: 0) else {
      return String(data: field, encoding: .utf8)
    }
    let nameBytes = field[field.startIndex..<nullIndex]
    guard !nameBytes.isEmpty else { return nil }
    return String(data: nameBytes, encoding: .utf8)
  }

  /// Write a preset filename into a block prefix. Appends the appropriate
  /// file extension (.pst or .aupreset) based on plugin type.
  private static func writePresetFilename(
    into prefix: inout Data, presetName: String, pluginType: PluginSetting
  ) {
    guard prefix.count >= minPrefixForFilename else { return }
    let ext: String
    switch pluginType {
    case .pst: ext = ".pst"
    case .aupreset: ext = ".aupreset"
    case .keyedArchive, .unknown: ext = ""
    }
    let filename = presetName + ext
    var field = Data(count: filenameRange.count)  // zero-filled
    if let nameData = filename.data(using: .utf8) {
      let copyCount = min(nameData.count, filenameRange.count - 1)  // leave room for null
      field.replaceSubrange(0..<copyCount, with: nameData[0..<copyCount])
    }
    prefix.replaceSubrange(filenameRange, with: field)
  }

  // MARK: - OCuA generation

  /// The constant 50-byte OCuA footer found in all observed CST files.
  private static let defaultOCuAFooter = Data([
    0x4f, 0x43, 0x75, 0x41, 0x07, 0x00, 0x0e, 0x00,
    0x00, 0x00, 0x24, 0x00, 0x00, 0x00, 0x01, 0x00,
    0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0x02, 0x00,
    0x00, 0x00, 0x02, 0x00, 0x0e, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00,
    0xff, 0xff, 0x00, 0x00, 0x00, 0x00, 0x35, 0x12,
    0x00, 0x00,
  ])

  /// The 237-byte base OCuA header template (from a minimal audio track CST with 0 slots).
  /// Bytes 28–31 encode the header content size (header_total - 36).
  /// Byte 40 encodes the track type (0x40 audio, 0x42 aux, 0x43 instrument).
  /// Byte 62 encodes the slot capacity (max_slot + 1).
  /// Header total = 237 + slotCapacity * 4.
  private static let ocuaHeaderBase = Data([
    0x4f, 0x43, 0x75, 0x41, 0x07, 0x00, 0x0e, 0x00,
    0x00, 0x00, 0x24, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0xff, 0xff, 0xff, 0xff, 0x02, 0x00,
    0x00, 0x00, 0x02, 0x00, 0xc9, 0x00, 0x00, 0x00,  // [28]=0xc9=201 → 201+36=237
    0x00, 0x00, 0x00, 0x00, 0xf8, 0x00, 0x00, 0x00,
    0x40, 0x00, 0x00, 0x00, 0x35, 0x12, 0x35, 0x12,  // [40]=track type
    0x00, 0x00, 0x00, 0x00, 0xf8, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x01, 0x00, 0x01, 0x01, 0x00, 0x00,  // [62]=slot capacity
    0x02, 0x00, 0x02, 0x00, 0x02, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x03, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x20, 0x43, 0x53, 0x54, 0x00, 0x00, 0x00, 0x00,  // " CST" channel name
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x5a, 0x00, 0x00, 0x00, 0x40, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x23, 0x12, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5a,
    0x06, 0x00, 0x7f, 0x01, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0xee, 0x00, 0x00,
  ])

  /// Generate an OCuA header for a given track type and slot capacity.
  ///
  /// The header is 237 + slotCapacity * 4 bytes. Slot array entries are zero-filled.
  private static func generateOCuAHeader(trackType: UInt8, slotCapacity: Int) -> Data {
    var header = ocuaHeaderBase
    // Set track type at offset 40
    header[40] = trackType
    // Set slot capacity at offset 62
    header[62] = UInt8(clamping: slotCapacity)
    // Append zero-filled slot array (4 bytes per slot)
    header.append(contentsOf: [UInt8](repeating: 0, count: slotCapacity * 4))
    // Update header size field at offset 28: value = total - 36
    var sizeField = UInt32(header.count - 36).littleEndian
    withUnsafeBytes(of: &sizeField) { header.replaceSubrange(28..<32, with: $0) }
    return header
  }

  /// Generate a minimal UCuA block prefix for a plugin at the given slot number.
  ///
  /// - PST plugins: 36-byte UCuA header (PST self-identifies via its GAMETSPP magic
  ///   and internal fileSize field).
  /// - AU presets and unknown data: 40-byte prefix (36-byte UCuA header + 4-byte LE
  ///   data-length field). The parser uses this length field to locate AU preset
  ///   boundaries.
  ///
  /// The UCuA size field at offset 28 is set to a placeholder and recalculated by
  /// `CstBlock.serialized()`.
  private static func generateUCuAPrefix(for plugin: PluginSetting, slot: UInt16) -> Data {
    var prefix = Data([
      0x55, 0x43, 0x75, 0x41,  // bytes  0– 3: "UCuA" magic
      0x04, 0x00, 0x0e, 0x00,  // bytes  4– 7: constant
      0x00, 0x00, 0x24, 0x00,  // bytes  8–11: constant
      0x00, 0x00, 0x00, 0x00,  // bytes 12–15: constant
      0x00, 0x00,  // bytes 16–17: constant zeros
    ])
    // Bytes 18–19: slot number (LE uint16)
    var slotLE = slot.littleEndian
    withUnsafeBytes(of: &slotLE) { prefix.append(contentsOf: $0) }
    prefix.append(contentsOf: [
      0x00, 0x00, 0x02, 0x00,  // bytes 20–23: constant
      0x00, 0x00, 0x02, 0x00,  // bytes 24–27: constant
    ])
    // Bytes 28-31: size field placeholder (recalculated by serialized())
    prefix.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
    // Bytes 32-35: constant zero
    prefix.append(contentsOf: [0x00, 0x00, 0x00, 0x00])

    // For non-PST plugins, append a 4-byte LE data-length field so the parser's
    // xmlLengthHeader / binaryAupresetLengthHeader can locate the plugin boundary.
    switch plugin {
    case .pst:
      break  // PST has its own internal size field
    case .aupreset(let au):
      let dataLength = (try? au.data().count) ?? 0
      var len = UInt32(dataLength).littleEndian
      withUnsafeBytes(of: &len) { prefix.append(contentsOf: $0) }
    case .keyedArchive(let archive):
      var len = UInt32(archive.byteCount).littleEndian
      withUnsafeBytes(of: &len) { prefix.append(contentsOf: $0) }
    case .unknown(let raw):
      var len = UInt32(raw.count).littleEndian
      withUnsafeBytes(of: &len) { prefix.append(contentsOf: $0) }
    }

    return prefix
  }

  // MARK: - OCuA parsing

  /// Parse an OCuA container into its structural components.
  ///
  /// The OCuA format consists of:
  /// - An outer header whose size is encoded at bytes 28–31 (value + 36 = total bytes).
  /// - Zero or more UCuA sub-container blocks, each self-sized the same way.
  /// - A trailing footer (always 50 bytes in observed files).
  private static func parseOCuA(from data: Data) throws -> (
    header: Data, blocks: [CstBlock], footer: Data
  ) {
    guard data.count >= 4, data.prefix(4) == Data("OCuA".utf8) else {
      return (data, [], Data())
    }
    guard data.count >= 32 else {
      return (data, [], Data())
    }

    let headerSizeField = Int(readUInt32LE(data, at: 28))
    let headerSize = headerSizeField + 36
    guard headerSize > 0, headerSize <= data.count else {
      return (data, [], Data())
    }

    let ocuaHeader = data.subdata(in: 0..<headerSize)
    var pos = headerSize
    var blocks: [CstBlock] = []

    while pos + 4 <= data.count {
      guard data.subdata(in: pos..<pos + 4) == Data("UCuA".utf8) else { break }
      guard pos + 32 <= data.count else { break }

      let blockSizeField = Int(readUInt32LE(data, at: pos + 28))
      let blockSize = blockSizeField + 36
      guard blockSize > 36, pos + blockSize <= data.count else { break }

      let blockData = data.subdata(in: pos..<pos + blockSize)
      let block = try parseUCuABlock(blockData)
      blocks.append(block)
      pos += blockSize
    }

    let footer = pos < data.count ? data.subdata(in: pos..<data.count) : Data()
    return (ocuaHeader, blocks, footer)
  }

  /// Parse a single UCuA block into a plugin block or opaque block.
  private static func parseUCuABlock(_ blockData: Data) throws -> CstBlock {
    // Slot number is at bytes 18–19 (LE uint16). Slots ≥ 12 are system/infrastructure
    // blocks (channel EQ, dynamics, smart controls, etc.) — not user-visible plugins.
    // MIDI FX can occupy slots up to 10; slots 0–11 are potentially user plugins.
    guard blockData.count >= 20 else { return .opaque(blockData) }
    let slotNumber = UInt16(blockData[18]) | (UInt16(blockData[19]) << 8)
    guard slotNumber < 12 else { return .opaque(blockData) }

    let pluginOffsets = try pluginStartOffsets(in: blockData).sorted()

    for pluginStart in pluginOffsets {
      let candidateEnds = pluginOffsets.filter { $0 > pluginStart } + [blockData.count]
      if let (setting, pluginEnd) = try extractPluginSetting(
        from: blockData, start: pluginStart, candidateEnds: candidateEnds
      ) {
        let prefix = blockData.subdata(in: 0..<pluginStart)
        let suffix = blockData.subdata(in: pluginEnd..<blockData.count)
        return .plugin(prefix: prefix, setting: setting, suffix: suffix)
      }
    }

    return .opaque(blockData)
  }

  private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
    data.subdata(in: offset..<offset + 4)
      .withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
  }

  // MARK: - Plugin data detection (unchanged from original)

  private static func pluginStartOffsets(in data: Data) throws -> [Int] {
    var offsets = Set<Int>()
    let pstMagic = Data("GAMETSPP".utf8)
    let pstMagicAlt = Data("PPSTEMAG".utf8)
    let xmlMagic = Data("<?xml".utf8)
    let binMagic = Data("bplist00".utf8)

    func addPstOffsets(for magic: Data) {
      var searchRange = data.startIndex..<data.endIndex
      while let range = data.range(of: magic, in: searchRange) {
        let start = range.lowerBound - 12
        if start >= 0 && start + 24 <= data.count {
          offsets.insert(start)
        }
        searchRange = (range.lowerBound + 1)..<data.endIndex
      }
    }

    addPstOffsets(for: pstMagic)
    addPstOffsets(for: pstMagicAlt)

    for magic in [xmlMagic, binMagic] {
      var searchRange = data.startIndex..<data.endIndex
      while let range = data.range(of: magic, in: searchRange) {
        offsets.insert(range.lowerBound)
        searchRange = (range.lowerBound + 1)..<data.endIndex
      }
    }

    return offsets.sorted()
  }

  private static func extractPluginSetting(from data: Data, start: Int, candidateEnds: [Int]) throws
    -> (PluginSetting, Int)?
  {
    guard start >= 0, start < data.count else {
      return nil
    }

    for end in candidateEnds where end > start {
      let slice = data.subdata(in: start..<end)

      if slice.starts(with: Data("<?xml".utf8)) {
        if let (au, exactEnd) = try Cst.parseXmlAupreset(from: data, start: start, maxEnd: end) {
          return (.aupreset(au), exactEnd)
        }
      }

      if slice.starts(with: Data("bplist00".utf8)) {
        if let (au, exactEnd) = try parseBinaryAupreset(from: data, start: start, maxEnd: end) {
          return (.aupreset(au), exactEnd)
        }
        // NSKeyedArchiver plist — preserve verbatim, expose decoded graph
        if let length = binaryAupresetLengthHeader(in: data, start: start), start + length <= end {
          let raw = data.subdata(in: start..<start + length)
          if let archive = try? KeyedArchive(data: raw) {
            return (.keyedArchive(archive), start + length)
          }
          return (.unknown(raw), start + length)
        }
      }

      if isPstHeader(start: start, in: data) {
        let fileSize = Int(
          data.subdata(in: start..<start + 4).withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
          })
        let actualEnd = start + fileSize
        if actualEnd <= end {
          let pstSlice = data.subdata(in: start..<actualEnd)
          let pst = try Pst(data: pstSlice)
          return (.pst(pst), actualEnd)
        }
      }
    }

    return nil
  }

  private static func isPstHeader(start: Int, in data: Data) -> Bool {
    guard start + 20 <= data.count else { return false }
    let magic = data.subdata(in: start + 12..<start + 20)
    return magic == Data("GAMETSPP".utf8) || magic == Data("PPSTEMAG".utf8)
  }

  private static func xmlPlistEnd(in data: Data) -> Int? {
    guard let closeRange = data.range(of: Data("</plist>".utf8)) else {
      return nil
    }
    return closeRange.upperBound
  }

  private static func xmlLengthHeader(in data: Data, start: Int) -> Int? {
    let offsets = [4, 8, 12, 16, 20, 24]
    for offset in offsets {
      let lengthIndex = start - offset
      guard lengthIndex >= 0 && lengthIndex + 4 <= start else { continue }
      let length = Int(
        data.subdata(in: lengthIndex..<(lengthIndex + 4)).withUnsafeBytes {
          $0.load(as: UInt32.self).littleEndian
        })
      guard length > 0, start + length <= data.count else { continue }
      if let xmlEnd = xmlPlistEnd(in: data.subdata(in: start..<start + length)), xmlEnd <= length {
        return length
      }
    }
    return nil
  }

  private static func parseXmlAupreset(from data: Data, start: Int, maxEnd: Int) throws -> (
    Aupreset, Int
  )? {
    if let length = xmlLengthHeader(in: data, start: start), start + length <= maxEnd {
      let slice = data.subdata(in: start..<start + length)
      let au = try Aupreset(data: slice)
      return (au, start + length)
    }
    return nil
  }

  private static func binaryAupresetLengthHeader(in data: Data, start: Int) -> Int? {
    let lengthIndex = start - 4
    guard lengthIndex >= 0 else { return nil }
    let length = Int(
      data.subdata(in: lengthIndex..<(lengthIndex + 4)).withUnsafeBytes {
        $0.load(as: UInt32.self).littleEndian
      })
    guard length > 0, start + length <= data.count else { return nil }
    return length
  }

  private static func parseBinaryAupreset(from data: Data, start: Int, maxEnd: Int) throws -> (
    Aupreset, Int
  )? {
    if let length = binaryAupresetLengthHeader(in: data, start: start), start + length <= maxEnd {
      let slice = data.subdata(in: start..<start + length)
      // NSKeyedArchiver plists contain "$archiver" key and cannot round-trip through Aupreset
      if let (obj, _) = try? parsePlist(from: slice),
        let dict = obj as? [String: Any],
        dict["$archiver"] != nil
      {
        return nil
      }
      let au = try Aupreset(data: slice)
      return (au, start + length)
    }
    return nil
  }
}
