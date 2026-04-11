import Foundation
import Testing

@testable import LogicFiles

@Test func testCstParsePst() throws {
  let resourceURL = requireTestResourceURL(
    "Channel Strip", extension: Cst.pathExtension, subdirectory: "Retro Synth Defaults")

  let data = try Data(contentsOf: resourceURL)
  let cst = try Cst(data: data)
  let serialized = try cst.data()
  #expect(serialized == data)
}

@Test func testCstParseAupreset() throws {
  let resourceURL = requireTestResourceURL(
    "Channel Strip", extension: Cst.pathExtension, subdirectory: "Retro Synth Defaults")

  let data = try Data(contentsOf: resourceURL)
  let cst = try Cst(data: data)

  #expect(cst.instrument != nil, "Channel Strip.cst should contain an instrument plugin")
  #expect(cst.midiPlugins.isEmpty, "No MIDI plugins expected in this example")
  #expect(
    cst.audioFxPlugins.count == 2,
    "Channel Strip.cst should contain 2 audio FX plugins (kHs Compactor + Phat FX); system blocks at slots ≥ 9 are excluded"
  )

  if let instrument = cst.instrument {
    switch instrument {
    case .pst: break
    default: #expect(Bool(false), "Instrument should be a PST")
    }
  }

  for fx in cst.audioFxPlugins {
    switch fx {
    case .pst, .aupreset, .keyedArchive: break
    case .unknown:
      #expect(
        Bool(false),
        "Unrecognized plugin format (.unknown) — investigate what data is at this block")
    }
  }

  let serialized = try cst.data()
  #expect(serialized == data, "CST round-trip serialization should be identical")
}

@Test func testCstAudioWithAudioFx() throws {
  let resourceURL = requireTestResourceURL(
    "Audio with 1 audio FX", extension: Cst.pathExtension, subdirectory: "Audio with Audio FX")

  let data = try Data(contentsOf: resourceURL)
  let cst = try Cst(data: data)

  #expect(
    cst.instrument == nil,
    "Track channel strip with no instrument selected should have nil instrument")
  #expect(cst.midiPlugins.isEmpty, "No MIDI plugins expected in this example")
  #expect(cst.audioFxPlugins.count == 1, "Should contain 1 audio FX plugin (Step FX)")

  let serialized = try cst.data()
  #expect(serialized == data, "CST round-trip serialization should be identical")
}

@Test func testCstMidiTrackNoInstrument() throws {
  let resourceURL = requireTestResourceURL(
    "No instrument", extension: Cst.pathExtension, subdirectory: "MIDI track with no instrument")

  let data = try Data(contentsOf: resourceURL)
  let cst = try Cst(data: data)

  #expect(
    cst.instrument == nil, "Instrument channel strip with no instrument should have nil instrument")
  #expect(cst.midiPlugins.isEmpty, "No MIDI FX selected in this example")
  #expect(cst.audioFxPlugins.isEmpty, "No audio FX selected in this example")

  let serialized = try cst.data()
  #expect(serialized == data, "CST round-trip serialization should be identical")
}

@Test func testCstAudioTrackNoInput() throws {
  let resourceURL = requireTestResourceURL(
    "Audio track no input", extension: Cst.pathExtension, subdirectory: "Audio track no input")

  let data = try Data(contentsOf: resourceURL)
  let cst = try Cst(data: data)

  #expect(cst.instrument == nil, "Audio track with no input should have nil instrument")
  #expect(cst.audioFxPlugins.isEmpty, "Audio track with no input should have no audio FX plugins")

  let serialized = try cst.data()
  #expect(serialized == data, "CST round-trip serialization should be identical")
}

@Test func testCstMidiFxWithAudioFx() throws {
  let resourceURL = requireTestResourceURL(
    "4 Midi FX plus 2 Audio FX", extension: Cst.pathExtension,
    subdirectory: "Instrument with 4 MIDI FX")

  let data = try Data(contentsOf: resourceURL)
  let cst = try Cst(data: data)

  #expect(cst.instrument != nil, "Should have an instrument plugin (Retro Synth)")
  #expect(
    cst.midiPlugins.count == 4, "Should have 4 MIDI FX (Arp, Chord Trigger, Transposer, Modifier)")
  #expect(cst.audioFxPlugins.count == 2, "Should have 2 audio FX (Exciter, Channel EQ)")

  let serialized = try cst.data()
  #expect(serialized == data, "CST round-trip serialization should be identical")
}

@Test func testCstRoundTrip() throws {
  // Gather all .cst files under examples
  var resourceURLs =
    Bundle.module.urls(forResourcesWithExtension: Cst.pathExtension, subdirectory: "examples") ?? []

  // Fallback: if SPM didn't expose the nested `examples` dir, read directly
  if resourceURLs.isEmpty {
    let thisFile = URL(fileURLWithPath: #file)
    let testsDir = thisFile.deletingLastPathComponent()
    let resourcesDir = testsDir.appendingPathComponent("Resources/examples")
    var urls: [URL] = []
    if FileManager.default.fileExists(atPath: resourcesDir.path) {
      let enumerator = FileManager.default.enumerator(
        at: resourcesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])!
      for case let u as URL in enumerator {
        if u.pathExtension.lowercased() == Cst.pathExtension {
          var isDir: ObjCBool = false
          if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), !isDir.boolValue {
            urls.append(u)
          }
        }
      }
    }
    resourceURLs = urls
  }

  for url in resourceURLs {
    let data = try Data(contentsOf: url)
    let cst = try Cst(data: data)
    let serialized = try cst.data()
    #expect(serialized == data, "CST round-trip failed for \(url.lastPathComponent)")
  }
}

@Test func testCstReplacePlugin() throws {
  let channelStripURL = requireTestResourceURL(
    "Channel Strip", extension: Cst.pathExtension, subdirectory: "Retro Synth Defaults")
  let donorURL = requireTestResourceURL(
    "RS Antimatter", extension: Cst.pathExtension,
    subdirectory: "Same instrument different preset no audiofx")

  let csData = try Data(contentsOf: channelStripURL)
  var cst = try Cst(data: csData)
  let donorData = try Data(contentsOf: donorURL)
  let donor = try Cst(data: donorData)

  guard let donorInstrument = donor.instrument else {
    #expect(Bool(false), "Donor CST should have an instrument")
    return
  }

  let originalPluginCount = cst.pluginCount

  cst.replacePlugin(at: 0, with: donorInstrument)

  let mutatedData = try cst.data()
  let reparsed = try Cst(data: mutatedData)
  #expect(reparsed.pluginCount == originalPluginCount, "Plugin count should be preserved")
  #expect(reparsed.instrument != nil, "Instrument should still be present")

  let reround = try reparsed.data()
  #expect(reround == mutatedData, "Mutated CST should round-trip")
  #expect(mutatedData != csData, "Mutated CST should differ from original")
}

@Test func testCstFromScratch() throws {
  let resourceURL = requireTestResourceURL(
    "Channel Strip", extension: Cst.pathExtension, subdirectory: "Retro Synth Defaults")

  let data = try Data(contentsOf: resourceURL)
  let original = try Cst(data: data)

  let fromScratch = try Cst(
    instrument: original.instrument,
    midiPlugins: original.midiPlugins,
    audioFxPlugins: original.audioFxPlugins
  )

  let serialized = try fromScratch.data()
  #expect(serialized.count > 0)
  #expect(serialized.prefix(4) == Data("OCuA".utf8))

  let reparsed = try Cst(data: serialized)
  #expect(reparsed.instrument != nil, "Instrument should survive round-trip")
  #expect(reparsed.audioFxPlugins.count == original.audioFxPlugins.count)
  #expect(reparsed.pluginCount == fromScratch.pluginCount)

  let reround = try reparsed.data()
  #expect(reround == serialized, "From-scratch CST should round-trip")
}

@Test func testCstFromScratchEmpty() throws {
  let empty = try Cst(instrument: nil, midiPlugins: [], audioFxPlugins: [])
  let serialized = try empty.data()
  #expect(serialized.prefix(4) == Data("OCuA".utf8))

  let reparsed = try Cst(data: serialized)
  #expect(reparsed.instrument == nil)
  #expect(reparsed.audioFxPlugins.isEmpty)

  let reround = try reparsed.data()
  #expect(reround == serialized)
}

@Test func testCstPresetName() throws {
  let url = requireTestResourceURL(
    "RS Antimatter", extension: Cst.pathExtension,
    subdirectory: "Same instrument different preset no audiofx")
  let data = try Data(contentsOf: url)
  var cst = try Cst(data: data)

  #expect(cst.presetName(at: 0) == "Antimatter Synth.pst")

  let donorURL = requireTestResourceURL(
    "RS Access Codes", extension: Cst.pathExtension,
    subdirectory: "Same instrument different preset no audiofx")
  let donor = try Cst(data: try Data(contentsOf: donorURL))

  cst.replacePlugin(at: 0, with: donor.instrument!, presetName: "Access Codes")
  #expect(cst.presetName(at: 0) == "Access Codes.pst")

  let serialized = try cst.data()
  let reparsed = try Cst(data: serialized)
  #expect(reparsed.presetName(at: 0) == "Access Codes.pst")
  #expect(try reparsed.data() == serialized)
}

@Test func testCstCloneStructure() throws {
  let channelStripURL = requireTestResourceURL(
    "Channel Strip", extension: Cst.pathExtension, subdirectory: "Retro Synth Defaults")
  let csData = try Data(contentsOf: channelStripURL)
  let template = try Cst(data: csData)

  let allPlugins =
    [template.instrument].compactMap { $0 } + template.midiPlugins + template.audioFxPlugins
  let cloned = Cst(cloningStructureOf: template, replacingPluginsWith: allPlugins)

  let clonedData = try cloned.data()
  #expect(clonedData == csData, "Cloning with same plugins should produce identical bytes")

  let antimatterURL = requireTestResourceURL(
    "RS Antimatter", extension: Cst.pathExtension,
    subdirectory: "Same instrument different preset no audiofx")
  let donor = try Cst(data: try Data(contentsOf: antimatterURL))

  var newPlugins = allPlugins
  if let donorInst = donor.instrument {
    newPlugins[0] = donorInst
  }
  let swapped = Cst(cloningStructureOf: template, replacingPluginsWith: newPlugins)
  let swappedData = try swapped.data()

  let reparsed = try Cst(data: swappedData)
  let reround = try reparsed.data()
  #expect(reround == swappedData, "Cloned CST should round-trip")
  #expect(reparsed.pluginCount == template.pluginCount)
}

@Test func testCstCodable() throws {
  let resourceURL = requireTestResourceURL(
    "Channel Strip", extension: Cst.pathExtension, subdirectory: "Retro Synth Defaults")

  let data = try Data(contentsOf: resourceURL)
  let originalCst = try Cst(data: data)

  let encoder = JSONEncoder()
  let jsonData = try encoder.encode(originalCst)

  let decoder = JSONDecoder()
  let decodedCst = try decoder.decode(Cst.self, from: jsonData)

  #expect(try decodedCst.data() == (try originalCst.data()))
  #expect((decodedCst.instrument != nil) == (originalCst.instrument != nil))
  #expect(decodedCst.midiPlugins.count == originalCst.midiPlugins.count)
  #expect(decodedCst.audioFxPlugins.count == originalCst.audioFxPlugins.count)
}

@Test func testKeyedArchiveEnvironmentLayer() throws {
  let url = requireTestResourceURL(
    "Channel Strip", extension: Cst.pathExtension, subdirectory: "Retro Synth Defaults")

  let data = try Data(contentsOf: url)
  let cst = try Cst(data: data)

  #expect(try cst.data() == data)

  let layer = cst.environmentLayer
  #expect(layer != nil, "Channel Strip.cst (Retro Synth) should have an MAKeyboardLayer")
  if let layer {
    #expect(layer.lowNote == 0)
    #expect(layer.highNote == 127)
    #expect(layer.lowVelocity == 1)
    #expect(layer.highVelocity == 127)
    #expect(layer.transpose == 0)
    #expect(!layer.multitimbralEnabled)
  }
}
