import Foundation
import LogicFiles

let args = CommandLine.arguments

func usage() -> Never {
  fputs(
    """
    Usage:
      logicfiles info <file>
        Print file metadata. Accepts .cst, .pst, .aupreset, and .patch files.

      logicfiles replace <base.cst> <donor.cst> <output.cst>
        Replace the instrument in base with the one from donor.

      logicfiles from-scratch <source.cst> <output.cst>
        Parse source, extract its plugins, and rebuild from scratch
        using generated OCuA container bytes.

      logicfiles clone <template.cst> <donor.cst> <output.cst>
        Clone template's structure and replace the instrument with donor's.

    Output CSTs can be copied to:
      ~/Music/Audio Music Apps/Channel Strip Settings/Instrument/

    """, stderr)
  exit(1)
}

// MARK: - Helpers

/// Convert an OSType integer to a printable four-character-code string.
func fourCC(_ value: Int) -> String {
  let u = UInt32(bitPattern: Int32(truncatingIfNeeded: value))
  let bytes: [UInt8] = [
    UInt8((u >> 24) & 0xff),
    UInt8((u >> 16) & 0xff),
    UInt8((u >> 8) & 0xff),
    UInt8(u & 0xff),
  ]
  if let s = String(bytes: bytes, encoding: .macOSRoman),
    s.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value < 0x7f })
  {
    return "'\(s)'"
  }
  return String(format: "0x%08x", u)
}

func pluginKind(_ setting: PluginSetting) -> String {
  switch setting {
  case .pst: return "PST"
  case .aupreset(let au): return "AU Preset (\(au.name))"
  case .keyedArchive: return "Keyed Archive"
  case .unknown: return "Unknown"
  }
}

// MARK: - Info

func printInfo(filePath: String) throws {
  let url = URL(fileURLWithPath: filePath)
  switch url.pathExtension.lowercased() {
  case Cst.pathExtension:
    let data = try Data(contentsOf: url)
    let cst = try Cst(data: data)
    print("File:       \(filePath)")
    print("Size:       \(data.count) bytes")
    print("Plugins:    \(cst.pluginCount)")
    print("Instrument: \(cst.instrument.map { pluginKind($0) } ?? "(none)")")
    print("MIDI FX:    \(cst.midiPlugins.count)")
    print("Audio FX:   \(cst.audioFxPlugins.count)")
    if let layer = cst.environmentLayer {
      print(
        "Keyboard:   notes \(layer.lowNote)–\(layer.highNote), velocity \(layer.lowVelocity)–\(layer.highVelocity)"
      )
    }

  case Pst.pathExtension:
    let data = try Data(contentsOf: url)
    let pst = try Pst(data: data)
    print("File:    \(filePath)")
    print("Size:    \(data.count) bytes")
    print("Version: \(pst.formatVersion)")
    print("Payload: \(pst.payload.count) bytes")
    print("Flags:   0x\(String(format: "%08x", pst.flags))")

  case Aupreset.pathExtension:
    let data = try Data(contentsOf: url)
    let au = try Aupreset(data: data)
    print("File:         \(filePath)")
    print("Name:         \(au.name)")
    print("Manufacturer: \(fourCC(au.manufacturer))")
    print("Type:         \(fourCC(au.type))")
    print("Subtype:      \(fourCC(au.subtype))")
    print("Version:      \(au.version)")
    if let payload = au.payload {
      print("Payload:      \(payload.count) bytes")
    }

  case Patch.pathExtension:
    let patch = try Patch(contentsOf: url)
    let root = patch.rootChannelStrip
    print("File:       \(filePath)")
    print("Root strip: \(root.pluginCount) plugins")
    if let inst = root.instrument {
      print("  Instrument: \(pluginKind(inst))")
    }
    print("  Audio FX:   \(root.audioFxPlugins.count)")
    if !patch.additionalChannelStrips.isEmpty {
      print("Additional:  \(patch.additionalChannelStrips.count) strips")
      for (name, cst) in patch.additionalChannelStrips.sorted(by: { $0.key < $1.key }) {
        print("  \(name): \(cst.pluginCount) plugins")
      }
    }

  default:
    fputs("Unknown file type: .\(url.pathExtension)\n", stderr)
    exit(1)
  }
}

// MARK: - Dispatch

guard args.count >= 2 else { usage() }

do {
  switch args[1] {
  case "info":
    guard args.count == 3 else { usage() }
    try printInfo(filePath: args[2])

  case "replace":
    guard args.count == 5 else { usage() }
    let baseData = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    var cst = try Cst(data: baseData)
    let donorData = try Data(contentsOf: URL(fileURLWithPath: args[3]))
    let donor = try Cst(data: donorData)
    guard let donorInstrument = donor.instrument else {
      fputs("Error: donor CST has no instrument plugin\n", stderr)
      exit(1)
    }
    print("Base:  \(args[2]) (\(baseData.count) bytes, \(cst.pluginCount) plugins)")
    print("Donor: \(args[3])")
    cst.replacePlugin(at: 0, with: donorInstrument)
    let outputData = try cst.data()
    try outputData.write(to: URL(fileURLWithPath: args[4]))
    print("Wrote: \(args[4]) (\(outputData.count) bytes)")

  case "from-scratch":
    guard args.count == 4 else { usage() }
    let sourceData = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    let source = try Cst(data: sourceData)
    print("Source: \(args[2]) (\(sourceData.count) bytes, \(source.pluginCount) plugins)")
    let fromScratch = try Cst(
      instrument: source.instrument,
      midiPlugins: source.midiPlugins,
      audioFxPlugins: source.audioFxPlugins
    )
    let outputData = try fromScratch.data()
    try outputData.write(to: URL(fileURLWithPath: args[3]))
    print("Wrote: \(args[3]) (\(outputData.count) bytes)")

  case "clone":
    guard args.count == 5 else { usage() }
    let templateData = try Data(contentsOf: URL(fileURLWithPath: args[2]))
    let template = try Cst(data: templateData)
    let donorData = try Data(contentsOf: URL(fileURLWithPath: args[3]))
    let donor = try Cst(data: donorData)
    print("Template: \(args[2]) (\(templateData.count) bytes, \(template.pluginCount) plugins)")
    print("Donor:    \(args[3]) (\(donorData.count) bytes, \(donor.pluginCount) plugins)")
    // Clone template's structure with its own plugins, then swap in donor's instrument.
    let templatePlugins =
      [template.instrument].compactMap { $0 } + template.midiPlugins + template.audioFxPlugins
    var cloned = Cst(cloningStructureOf: template, replacingPluginsWith: templatePlugins)
    if let donorInst = donor.instrument {
      var presetName: String?
      if let donorFilename = donor.presetName(at: 0) {
        let name = (donorFilename as NSString).deletingPathExtension
        if !name.isEmpty { presetName = name }
      }
      cloned.replacePlugin(at: 0, with: donorInst, presetName: presetName)
    }
    let outputData = try cloned.data()
    try outputData.write(to: URL(fileURLWithPath: args[4]))
    print("Wrote: \(args[4]) (\(outputData.count) bytes)")

  default:
    usage()
  }
} catch {
  fputs("Error: \(error)\n", stderr)
  exit(1)
}
