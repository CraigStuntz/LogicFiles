import Foundation
import Testing

@testable import LogicFiles

/// Locates the `Logicx Simple/Project.logicx` fixture.
///
/// SPM `.copy` resources preserve directory bundles, but the nested `.logicx` directory
/// may not be directly accessible via `Bundle.module.url(forResource:)`. Fall back to
/// `#file`-relative discovery when needed.
private func logicxFixtureURL(thisFile: String = #file) -> URL? {
  // Try Bundle.module first (works when SPM copies the examples directory).
  if let examplesURL = Bundle.module.url(forResource: "examples", withExtension: nil) {
    let candidate = examplesURL
      .appendingPathComponent("Logicx Simple")
      .appendingPathComponent("Project.logicx")
    if FileManager.default.fileExists(atPath: candidate.path) {
      return candidate
    }
  }

  // Fall back to #file-relative path (works in the workspace).
  let resourcesDir = URL(fileURLWithPath: thisFile)
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/examples/Logicx Simple/Project.logicx")
  if FileManager.default.fileExists(atPath: resourcesDir.path) {
    return resourcesDir
  }

  return nil
}

/// Locates the `Logicx simple as folder/Project as folder` fixture (the outer project folder,
/// not the inner `.logicx` bundle).
private func logicxFolderFixtureURL(thisFile: String = #file) -> URL? {
  if let examplesURL = Bundle.module.url(forResource: "examples", withExtension: nil) {
    let candidate = examplesURL
      .appendingPathComponent("Logicx simple as folder")
      .appendingPathComponent("Project as folder")
    if FileManager.default.fileExists(atPath: candidate.path) {
      return candidate
    }
  }

  let resourcesDir = URL(fileURLWithPath: thisFile)
    .deletingLastPathComponent()
    .appendingPathComponent(
      "Resources/examples/Logicx simple as folder/Project as folder")
  if FileManager.default.fileExists(atPath: resourcesDir.path) {
    return resourcesDir
  }

  return nil
}

// MARK: - Folder format loading

@Test func testLogicxFolderLoading() throws {
  let url = try #require(logicxFolderFixtureURL(), "Logicx folder fixture not found")
  let logicx = try Logicx(contentsOf: url)

  #expect(logicx.projectInformation.bundleVersion == 2)
  #expect(logicx.projectInformation.lastSavedFrom.contains("Logic Pro"))
  #expect(logicx.projectInformation.hasProjectFolder == true)
  #expect(logicx.projectInformation.variantNames["0"] == "Project as folder")

  #expect(logicx.alternatives.count == 1)
  let alt = try #require(logicx.alternatives["000"])
  #expect(alt.metaData.beatsPerMinute == 120)
  #expect(alt.metaData.songKey == "C")
}

@Test func testLogicxBundleAudioFilesURL() throws {
  let url = try #require(logicxFixtureURL(), "Logicx Simple fixture not found")
  let logicx = try Logicx(contentsOf: url)
  let audioURL = try #require(logicx.audioFilesURL, "Bundle should have audioFilesURL")
  #expect(audioURL.lastPathComponent == "Audio Files")
  // In bundle format, Audio Files is inside Media/ inside the bundle.
  #expect(audioURL.deletingLastPathComponent().lastPathComponent == "Media")
}

@Test func testLogicxFolderAudioFilesURL() throws {
  let url = try #require(logicxFolderFixtureURL(), "Logicx folder fixture not found")
  let logicx = try Logicx(contentsOf: url)
  let audioURL = try #require(logicx.audioFilesURL, "Folder should have audioFilesURL")
  #expect(audioURL.lastPathComponent == "Audio Files")
  // In folder format, Audio Files is at the top level of the outer folder.
  #expect(audioURL.deletingLastPathComponent().lastPathComponent == "Project as folder")
}

@Test func testLogicxHasProjectFolder() throws {
  let bundleURL = try #require(logicxFixtureURL(), "Logicx Simple fixture not found")
  let bundleLogicx = try Logicx(contentsOf: bundleURL)
  #expect(bundleLogicx.projectInformation.hasProjectFolder == false)

  let folderURL = try #require(logicxFolderFixtureURL(), "Logicx folder fixture not found")
  let folderLogicx = try Logicx(contentsOf: folderURL)
  #expect(folderLogicx.projectInformation.hasProjectFolder == true)
}

@Test func testLogicxWriteAsFolder() throws {
  let url = try #require(logicxFolderFixtureURL(), "Logicx folder fixture not found")
  let logicx = try Logicx(contentsOf: url)

  let tempURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: tempURL) }

  try logicx.write(to: tempURL, as: .folder)

  // Outer folder must contain the marker file.
  #expect(
    FileManager.default.fileExists(
      atPath: tempURL.appendingPathComponent(".musicapps-project-folder").path))
  // Audio Files at top level.
  #expect(
    FileManager.default.fileExists(
      atPath: tempURL.appendingPathComponent("Audio Files").path))
  // Inner .logicx bundle named after the outer folder.
  let innerName = tempURL.lastPathComponent + ".logicx"
  let innerURL = tempURL.appendingPathComponent(innerName)
  #expect(FileManager.default.fileExists(atPath: innerURL.path))
  // Inner bundle has Resources/ProjectInformation.plist.
  #expect(
    FileManager.default.fileExists(
      atPath: innerURL.appendingPathComponent("Resources/ProjectInformation.plist").path))
  // Inner bundle has no Media/ directory (audio files are at the outer level).
  #expect(
    !FileManager.default.fileExists(
      atPath: innerURL.appendingPathComponent("Media").path))
}

/// Locates the `Logicx with session player/Project with session player.logicx` fixture.
private func logicxSessionPlayerFixtureURL(thisFile: String = #file) -> URL? {
  if let examplesURL = Bundle.module.url(forResource: "examples", withExtension: nil) {
    let candidate = examplesURL
      .appendingPathComponent("Logicx with session player")
      .appendingPathComponent("Project with session player.logicx")
    if FileManager.default.fileExists(atPath: candidate.path) {
      return candidate
    }
  }

  let resourcesDir = URL(fileURLWithPath: thisFile)
    .deletingLastPathComponent()
    .appendingPathComponent(
      "Resources/examples/Logicx with session player/Project with session player.logicx")
  if FileManager.default.fileExists(atPath: resourcesDir.path) {
    return resourcesDir
  }

  return nil
}

// MARK: - Session Player

@Test func testSessionPlayerTrackStates() throws {
  let url = try #require(
    logicxSessionPlayerFixtureURL(), "Session player fixture not found")
  let logicx = try Logicx(contentsOf: url)
  let alt = try #require(logicx.alternatives["000"])

  let states = alt.sessionPlayerTrackStates()
  #expect(states.count == 2)

  let identifiers = Set(states.map(\.characterIdentifier))
  #expect(identifiers.contains("Acoustic Piano - Arpeggiated"))
  #expect(identifiers.contains("Acoustic Drummer - Pop Rock"))

  let piano = try #require(states.first { $0.characterIdentifier == "Acoustic Piano - Arpeggiated" })
  #expect(piano.characterTypeIdentifier == "Type_AcousticPianoV2")
  #expect(piano.isUsingProducerKit == false)
}

@Test func testSessionPlayerPresets() throws {
  let url = try #require(
    logicxSessionPlayerFixtureURL(), "Session player fixture not found")
  let logicx = try Logicx(contentsOf: url)
  let alt = try #require(logicx.alternatives["000"])

  let presets = alt.sessionPlayerPresets()
  // The fixture has one region on the Acoustic Piano track.
  #expect(presets.count == 1)

  let preset = try #require(presets.first)
  #expect(preset.name == "Power Ballad")
  #expect(preset.characterIdentifier == "Acoustic Piano - Arpeggiated")
  #expect(preset.regionType == "Type_AcousticPianoV2")
  #expect(preset.uniqueIdentifier == "Acoustic Piano - Arpeggiated - Power Ballad.dpst")

  #expect(preset.parameters.intensity == 46)
  #expect(preset.parameters.dynamics == 112)
  #expect(preset.parameters.humanize == 28)
  #expect(preset.parameters.rComp == 67)
}

@Test func testSessionPlayerPresetsEmptyForProjectWithNoGeneratedRegions() throws {
  // Logic embeds `genInstDrummerBaseModel.state` even in projects with no visible
  // session player tracks, so track states may be non-empty. Region presets are only
  // written when a region has been generated, so a project with no generated regions
  // must have an empty preset list.
  let url = try #require(logicxFixtureURL(), "Logicx Simple fixture not found")
  let logicx = try Logicx(contentsOf: url)
  let alt = try #require(logicx.alternatives["000"])
  #expect(alt.sessionPlayerPresets().isEmpty)
}

// MARK: - Basic loading

@Test func testLogicxBasicLoading() throws {
  let url = try #require(logicxFixtureURL(), "Logicx Simple fixture not found")
  let logicx = try Logicx(contentsOf: url)

  // Project information
  #expect(logicx.projectInformation.bundleVersion == 2)
  #expect(logicx.projectInformation.lastSavedFrom.contains("Logic Pro"))
  #expect(logicx.projectInformation.variantNames["0"] == "Project")

  // Alternatives
  #expect(logicx.alternatives.count == 1)
  let alt = try #require(logicx.alternatives["000"])

  // Metadata
  #expect(alt.metaData.beatsPerMinute == 120)
  #expect(alt.metaData.songKey == "C")
  #expect(alt.metaData.songGenderKey == "major")
  #expect(alt.metaData.songSignatureNumerator == 4)
  #expect(alt.metaData.songSignatureDenominator == 4)
  #expect(alt.metaData.sampleRate == 48000)
  #expect(alt.metaData.numberOfTracks == 1)

  // Binary data present
  #expect(alt.projectData.count > 0)
  #expect(alt.windowImage != nil)
}

// MARK: - Object → Data → Object round-trip tests
// These exercise the re-serialization path (via PlistDict), not the raw-bytes shortcut,
// by serializing an object to data and parsing it back. This verifies both code paths
// produce equivalent objects.

@Test func testLogicxProjectInformationObjectRoundTrip() throws {
  let url = try #require(logicxFixtureURL(), "Logicx Simple fixture not found")
  let logicx = try Logicx(contentsOf: url)
  let original = logicx.projectInformation

  // Serialize to data, then parse back into a new object.
  let reparsed = try LogicxProjectInformation(data: original.data())

  #expect(reparsed.bundleVersion == original.bundleVersion)
  #expect(reparsed.lastSavedFrom == original.lastSavedFrom)
  #expect(reparsed.variantNames == original.variantNames)
}

@Test func testLogicxMetaDataObjectRoundTrip() throws {
  let url = try #require(logicxFixtureURL(), "Logicx Simple fixture not found")
  let logicx = try Logicx(contentsOf: url)
  let alt = try #require(logicx.alternatives["000"])
  let original = alt.metaData

  let reparsed = try LogicxMetaData(data: original.data())

  #expect(reparsed.beatsPerMinute == original.beatsPerMinute)
  #expect(reparsed.sampleRate == original.sampleRate)
  #expect(reparsed.songKey == original.songKey)
  #expect(reparsed.songGenderKey == original.songGenderKey)
  #expect(reparsed.songSignatureNumerator == original.songSignatureNumerator)
  #expect(reparsed.songSignatureDenominator == original.songSignatureDenominator)
  #expect(reparsed.numberOfTracks == original.numberOfTracks)
  #expect(reparsed.version == original.version)
}

@Test func testLogicxDisplayStateObjectRoundTrip() throws {
  let url = try #require(logicxFixtureURL(), "Logicx Simple fixture not found")
  let logicx = try Logicx(contentsOf: url)
  let alt = try #require(logicx.alternatives["000"])
  let original = alt.displayState

  // The fixture has 1 screenset ("Screenset 1" in the UI), active slot 1.
  #expect(original.displayDataVersion == 1)
  #expect(original.screensetCurrSlot == 1)

  let reparsed = try LogicxDisplayState(data: original.data())

  #expect(reparsed.displayDataVersion == original.displayDataVersion)
  #expect(reparsed.screensetCurrSlot == original.screensetCurrSlot)
}

// MARK: - Mutation invalidates raw cache

@Test func testLogicxMetaDataTypedPropertyMutation() throws {
  let url = try #require(logicxFixtureURL(), "Logicx Simple fixture not found")
  let logicx = try Logicx(contentsOf: url)
  var metaData = try #require(logicx.alternatives["000"]).metaData
  #expect(metaData.beatsPerMinute == 120)
  metaData.beatsPerMinute = 140
  let reparsed = try LogicxMetaData(data: metaData.data())
  #expect(reparsed.beatsPerMinute == 140)
}

@Test func testLogicxModifyWriteReadBack() throws {
  let url = try #require(logicxFixtureURL(), "Logicx Simple fixture not found")
  var logicx = try Logicx(contentsOf: url)
  var alt = try #require(logicx.alternatives["000"])
  alt.metaData.beatsPerMinute = 140
  logicx.alternatives["000"] = alt

  let tempURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString + "." + Logicx.pathExtension)
  defer { try? FileManager.default.removeItem(at: tempURL) }

  try logicx.write(to: tempURL)
  let readBack = try Logicx(contentsOf: tempURL)
  let readBackAlt = try #require(readBack.alternatives["000"])
  #expect(readBackAlt.metaData.beatsPerMinute == 140)
}

@Test func testModifiedMetaDataPlistIsReflectedInData() throws {
  let url = try #require(logicxFixtureURL(), "Logicx Simple fixture not found")
  let logicx = try Logicx(contentsOf: url)
  let alt = try #require(logicx.alternatives["000"])
  var metaData = alt.metaData

  // Precondition: the fixture has songKey "C".
  #expect(metaData.songKey == "C")

  // Mutate the underlying plist dictionary.
  metaData["SongKey"] = "D"

  // Serialize and re-parse — the modified value should appear, not the original.
  let reparsed = try LogicxMetaData(data: metaData.data())
  #expect(reparsed.songKey == "D")
}

@Test func testModifiedDisplayStatePlistIsReflectedInData() throws {
  let url = try #require(logicxFixtureURL(), "Logicx Simple fixture not found")
  let logicx = try Logicx(contentsOf: url)
  let alt = try #require(logicx.alternatives["000"])
  var displayState = alt.displayState

  #expect(displayState.screensetCurrSlot == 1)

  displayState["screensetCurrSlot"] = 3

  let reparsed = try LogicxDisplayState(data: displayState.data())
  #expect(reparsed.screensetCurrSlot == 3)
}

@Test func testModifiedProjectInformationPlistIsReflectedInData() throws {
  let url = try #require(logicxFixtureURL(), "Logicx Simple fixture not found")
  let logicx = try Logicx(contentsOf: url)
  var projInfo = logicx.projectInformation

  #expect(projInfo.bundleVersion == 2)

  projInfo["BundleVersion"] = 99

  let reparsed = try LogicxProjectInformation(data: projInfo.data())
  #expect(reparsed.bundleVersion == 99)
}
