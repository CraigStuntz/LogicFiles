import Foundation
import Testing

@testable import LogicFiles

private func resolvePatchURL(_ name: String, in folder: String) -> URL {
  requireTestResourceURL(name, extension: Patch.pathExtension, subdirectory: folder)
}

@Test func testPatchParsing() throws {
  let patchURL = resolvePatchURL("Channel Strip", in: "Retro Synth Defaults")

  let patch = try Patch(contentsOf: patchURL)
  #expect((try patch.rootChannelStrip.data()).count > 0)
  #expect(patch.patchData.channels.count > 0)
}

@Test func testPatchRootChannelStrip() throws {
  let patchURL = resolvePatchURL("Channel Strip", in: "Retro Synth Defaults")

  let patch = try Patch(contentsOf: patchURL)
  let serialized = try patch.rootChannelStrip.data()
  #expect(serialized.count > 0)
}

@Test func testPatchRoundTrip() throws {
  let thisFile = URL(fileURLWithPath: #file)
  let resourcesDir =
    thisFile
    .deletingLastPathComponent()
    .appendingPathComponent("../Resources/examples")
    .standardized

  guard FileManager.default.fileExists(atPath: resourcesDir.path) else { return }

  let children = try FileManager.default.contentsOfDirectory(
    at: resourcesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

  for exampleDir in children {
    let enumerator = FileManager.default.enumerator(
      at: exampleDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    guard let enumerator else { continue }
    for case let url as URL in enumerator {
      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir),
        isDir.boolValue,
        url.pathExtension.lowercased() == Patch.pathExtension
      else { continue }
      let patch = try Patch(contentsOf: url)
      let rootOriginal = try Data(contentsOf: url.appendingPathComponent("#Root.cst"))
      #expect(
        try patch.rootChannelStrip.data() == rootOriginal,
        "Root CST round-trip failed in \(url.lastPathComponent)")
      for (filename, cst) in patch.additionalChannelStrips {
        let original = try Data(contentsOf: url.appendingPathComponent(filename))
        #expect(
          try cst.data() == original,
          "CST round-trip failed for \(filename) in \(url.lastPathComponent)")
      }
    }
  }
}

@Test func testPatchCodable() throws {
  let patchURL = resolvePatchURL("Channel Strip", in: "Retro Synth Defaults")

  let original = try Patch(contentsOf: patchURL)
  let jsonData = try JSONEncoder().encode(original)
  let decoded = try JSONDecoder().decode(Patch.self, from: jsonData)

  #expect(try decoded.rootChannelStrip.data() == (try original.rootChannelStrip.data()))
  #expect(decoded.additionalChannelStrips.count == original.additionalChannelStrips.count)
  #expect(decoded.patchData.versionPatches == original.patchData.versionPatches)
  #expect(decoded.patchData.channels.count == original.patchData.channels.count)
}

@Test func testSummingStackPatch() throws {
  let patchURL = resolvePatchURL("Summing Stack", in: "Summing Stack Patch")

  let patch = try Patch(contentsOf: patchURL)

  #expect((try patch.rootChannelStrip.data()).count > 0, "Patch should contain #Root.cst")

  var allCsts = patch.additionalChannelStrips
  allCsts["#Root.\(Cst.pathExtension)"] = patch.rootChannelStrip

  #expect(allCsts.count >= 3, "Summing stack should contain at least 3 CST files")
  #expect(allCsts.keys.contains("#Root.\(Cst.pathExtension)"))
  #expect(allCsts.keys.contains("Inst2.\(Cst.pathExtension)"))
  #expect(allCsts.keys.contains("TestPatch.\(Cst.pathExtension)"))

  #expect(patch.additionalChannelStrips.count >= 2, "Should have at least 2 additional strips")
  #expect(!patch.additionalChannelStrips.keys.contains("#Root.cst"))

  for (filename, cst) in allCsts {
    let original = try Data(contentsOf: patchURL.appendingPathComponent(filename))
    #expect(try cst.data() == original, "CST round-trip failed for \(filename)")
  }
}

@Test func testPatchDataParsing() throws {
  let patchURL = resolvePatchURL("Channel Strip", in: "Retro Synth Defaults")
  let patch = try Patch(contentsOf: patchURL)

  let pd = patch.patchData
  #expect(pd.versionPatches > 0)
  #expect(pd.channels.count == 1)

  let root = pd.channels[0]
  #expect(root.isRoot)
  #expect(root.filename == "#Root.cst")
  #expect(!root.name.isEmpty)
}

@Test func testSummingStackPatchData() throws {
  let patchURL = resolvePatchURL("Summing Stack", in: "Summing Stack Patch")
  let patch = try Patch(contentsOf: patchURL)

  let pd = patch.patchData
  #expect(pd.channels.count == 3)
  #expect(pd.channels.filter(\.isRoot).count == 1)
  let filenames = pd.channels.map(\.filename)
  #expect(filenames.contains("#Root.cst"))
}
