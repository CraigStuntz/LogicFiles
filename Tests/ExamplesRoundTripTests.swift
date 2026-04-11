import Foundation
import Testing

@testable import LogicFiles

// MARK: - Helpers

private typealias ParsedRep = (url: URL, data: Data, pst: Pst?, au: Aupreset?, cst: Cst?)

/// Gathers all file URLs under the `examples` subdirectory, falling back to `#file`-relative discovery
/// when SPM doesn't expose the nested directory into the test bundle.
private func collectExampleURLs(thisFile: String = #file) -> [URL] {
  let bundleURLs =
    Bundle.module.urls(forResourcesWithExtension: nil, subdirectory: "examples") ?? []
  if !bundleURLs.isEmpty { return bundleURLs }

  let resourcesDir = URL(fileURLWithPath: thisFile)
    .deletingLastPathComponent()
    .appendingPathComponent("Resources/examples")
  guard FileManager.default.fileExists(atPath: resourcesDir.path),
    let enumerator = FileManager.default.enumerator(
      at: resourcesDir, includingPropertiesForKeys: nil)
  else { return [] }

  var urls: [URL] = []
  for case let u as URL in enumerator {
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), !isDir.boolValue {
      urls.append(u)
    }
  }
  return urls
}

/// Groups file URLs by the folder directly under `examples/`, so files inside `.patch` bundles
/// stay grouped with their sibling presets.
private func groupByExampleFolder(_ urls: [URL]) -> [URL: [URL]] {
  func exampleFolder(for url: URL) -> URL? {
    var u = url
    while u.pathComponents.count > 1 {
      let parent = u.deletingLastPathComponent()
      if parent.lastPathComponent == "examples" { return u }
      u = parent
    }
    return nil
  }
  var folders: [URL: [URL]] = [:]
  for url in urls {
    let key = exampleFolder(for: url) ?? url.deletingLastPathComponent()
    folders[key, default: []].append(url)
  }
  return folders
}

/// Parses a `.patch` bundle and verifies two round-trips:
/// 1. Filesystem: `write(to:)` then re-read — each file must be byte-for-byte identical.
/// 2. Codable: JSON encode → decode → `write(to:)` then re-read — each file must be byte-for-byte identical.
private func roundTripPatch(at url: URL) throws {
  let patch = try Patch(contentsOf: url)
  try assertPatchFilesMatch(original: url, written: writePatch(patch))

  let codableRoundTripped = try JSONDecoder().decode(Patch.self, from: JSONEncoder().encode(patch))
  try assertPatchFilesMatch(original: url, written: writePatch(codableRoundTripped))
}

private func writePatch(_ patch: Patch) throws -> URL {
  let tempURL = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString + ".\(Patch.pathExtension)")
  try patch.write(to: tempURL)
  return tempURL
}

private func assertPatchFilesMatch(original: URL, written tempURL: URL) throws {
  defer { try? FileManager.default.removeItem(at: tempURL) }

  let origRoot = try Data(contentsOf: original.appendingPathComponent("#Root.cst"))
  let writtenRoot = try Data(contentsOf: tempURL.appendingPathComponent("#Root.cst"))
  #expect(
    origRoot == writtenRoot, "Patch #Root.cst round-trip failed for \(original.lastPathComponent)")

  let origPlist = try Data(contentsOf: original.appendingPathComponent("data.plist"))
  let writtenPlist = try Data(contentsOf: tempURL.appendingPathComponent("data.plist"))
  #expect(
    origPlist == writtenPlist,
    "Patch data.plist round-trip failed for \(original.lastPathComponent)")

  let patch = try Patch(contentsOf: original)
  for filename in patch.additionalChannelStrips.keys {
    let origFile = try Data(contentsOf: original.appendingPathComponent(filename))
    let writtenFile = try Data(contentsOf: tempURL.appendingPathComponent(filename))
    #expect(
      origFile == writtenFile,
      "Patch \(filename) round-trip failed for \(original.lastPathComponent)")
  }
}

/// Asserts that all plugin slots in a CST use recognised formats: no `.unknown` cases,
/// and no unhandled ObjC classes (which degrade to dicts with a `__class__` key).
private func assertPluginSlotsRecognized(in cst: Cst, context: String) {
  for setting in [cst.instrument].compactMap({ $0 }) + cst.midiPlugins + cst.audioFxPlugins {
    switch setting {
    case .pst, .aupreset:
      break
    case .keyedArchive(let archive):
      let unknown = unknownClasses(in: archive.decoded)
      #expect(
        unknown.isEmpty,
        "KeyedArchive in \(context) has unrecognized ObjC classes: \(unknown) — add typed decoding for these"
      )
    case .unknown:
      #expect(
        Bool(false),
        "Unrecognized plugin format (.unknown) in \(context) — investigate what data is at this block"
      )
    }
  }
}

/// Returns URLs of `.patch` bundles found directly under `exampleURL`.
/// SPM flattens bundle resources, so this only returns results in the workspace.
private func patchBundleURLs(in exampleURL: URL) throws -> [URL] {
  guard FileManager.default.fileExists(atPath: exampleURL.path) else { return [] }
  let children = try FileManager.default.contentsOfDirectory(
    at: exampleURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
  return children.filter { child in
    var isDir: ObjCBool = false
    return FileManager.default.fileExists(atPath: child.path, isDirectory: &isDir)
      && isDir.boolValue
      && child.lastPathComponent.hasSuffix(".\(Patch.pathExtension)")
  }
}

/// Parses all channel-strip representations for one example folder and asserts binary round-trips.
/// Pass the result of `patchBundleURLs(in:)` so the caller controls patch discovery and round-tripping.
private func collectRepresentations(channelStrips: [URL], patchBundles: [URL]) throws -> [ParsedRep]
{
  var reps: [ParsedRep] = []

  for cs in channelStrips where cs.pathExtension.lowercased() == Cst.pathExtension {
    let csData = try Data(contentsOf: cs)
    let cst = try Cst(data: csData)
    #expect(try cst.data() == csData, "CST round-trip failed for \(cs.lastPathComponent)")
    assertPluginSlotsRecognized(in: cst, context: cs.lastPathComponent)
    reps.append((cs, csData, nil, nil, cst))
  }

  for bundle in patchBundles {
    let patchFiles = try FileManager.default.contentsOfDirectory(
      at: bundle, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    for pf in patchFiles {
      var pfIsDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: pf.path, isDirectory: &pfIsDir),
        !pfIsDir.boolValue
      else { continue }
      let pfData = try Data(contentsOf: pf)
      switch pf.pathExtension.lowercased() {
      case Cst.pathExtension:
        let cst = try Cst(data: pfData)
        #expect(try cst.data() == pfData, "CST round-trip failed for \(pf.lastPathComponent)")
        assertPluginSlotsRecognized(in: cst, context: pf.lastPathComponent)
        reps.append((pf, pfData, nil, nil, cst))
      case Pst.pathExtension:
        let pst = try Pst(data: pfData)
        #expect(try pst.data() == pfData, "PST round-trip failed for \(pf.lastPathComponent)")
        reps.append((pf, pfData, pst, nil, nil))
      case Aupreset.pathExtension:
        let au = try Aupreset(data: pfData)
        #expect(try au.data() == pfData, "Aupreset round-trip failed for \(pf.lastPathComponent)")
        reps.append((pf, pfData, nil, au, nil))
      default:
        break  // data.plist and other non-preset files are skipped
      }
    }
  }
  return reps
}

/// Builds the list of Data blobs to search when checking whether a child preset is embedded.
private func searchableBlobs(from rep: ParsedRep) -> [Data] {
  var blobs: [Data] = [rep.data]
  if let pst = rep.pst { blobs.append(pst.payload) }
  if let au = rep.au, let payload = au.payload { blobs.append(payload) }
  if let cst = rep.cst {
    for setting in [cst.instrument].compactMap({ $0 }) + cst.midiPlugins + cst.audioFxPlugins {
      if case .pst(let pst) = setting { blobs.append(pst.payload) }
      if case .aupreset(let au) = setting, let payload = au.payload { blobs.append(payload) }
    }
  }
  return blobs
}

/// Returns true if `childData` (an `.aupreset`) matches an XML plist block embedded in `repData`.
private func aupresetEmbeddedAsXML(childData: Data, in repData: Data) -> Bool {
  guard let childPlistObj = try? parsePlist(from: childData).0 else { return false }
  let xmlSig = Data("<?xml".utf8)
  let closingTag = Data("</plist>".utf8)
  var searchStart = 0
  while let range = repData.range(of: xmlSig, in: searchStart..<repData.count) {
    if let endRange = repData.range(of: closingTag, in: range.lowerBound..<repData.count) {
      let slice = repData.subdata(in: range.lowerBound..<endRange.upperBound)
      if let extracted = try? parsePlist(from: slice).0,
        let left = try? PropertyListSerialization.data(
          fromPropertyList: childPlistObj, format: .binary, options: 0),
        let right = try? PropertyListSerialization.data(
          fromPropertyList: extracted, format: .binary, options: 0),
        left == right
      {
        return true
      }
    }
    searchStart = range.lowerBound + 1
  }
  return false
}

/// Asserts that `childData` is embedded somewhere in the parsed representations, trying in order:
/// exact-byte match, XML plist equivalence (for `.aupreset`), and prefix-byte match.
private func assertChildEmbedded(_ child: URL, childData: Data, in reps: [ParsedRep]) {
  var foundAny = false
  for rep in reps {
    let blobs = searchableBlobs(from: rep)
    if blobs.first(where: { $0.range(of: childData) != nil }) != nil {
      foundAny = true
      break
    }

    if child.pathExtension.lowercased() == Aupreset.pathExtension {
      if aupresetEmbeddedAsXML(childData: childData, in: rep.data) {
        foundAny = true
        break
      }
      for pLen in [64, 256, 512] {
        let prefix = childData.subdata(in: 0..<min(pLen, childData.count))
        if blobs.first(where: { $0.range(of: prefix) != nil }) != nil {
          foundAny = true
          break
        }
      }
      if foundAny { break }
    }
  }

  #expect(
    foundAny, "Child \(child.lastPathComponent) should be embedded in a parent representation")
}

/// JSON-encodes then JSON-decodes each parsed type and re-asserts binary fidelity.
private func assertCodableRoundTrips(for reps: [ParsedRep]) throws {
  let encoder = JSONEncoder()
  let decoder = JSONDecoder()
  for rep in reps {
    if let cst = rep.cst {
      #expect(
        try decoder.decode(Cst.self, from: encoder.encode(cst)).data() == cst.data(),
        "Codable round-trip failed for \(rep.url.lastPathComponent)")
    }
    if let pst = rep.pst {
      #expect(
        try decoder.decode(Pst.self, from: encoder.encode(pst)).data() == pst.data(),
        "Codable round-trip failed for \(rep.url.lastPathComponent)")
    }
    if let au = rep.au {
      #expect(
        try decoder.decode(Aupreset.self, from: encoder.encode(au)).data() == au.data(),
        "Codable round-trip failed for \(rep.url.lastPathComponent)")
    }
  }
}

/// Recursively collects all `__class__` values found anywhere in a decoded KeyedArchive dict tree.
private func unknownClasses(in value: Any) -> [String] {
  if let dict = value as? [String: Any] {
    var found = dict["__class__"].flatMap { $0 as? String }.map { [$0] } ?? []
    for v in dict.values { found += unknownClasses(in: v) }
    return found
  }
  if let arr = value as? [Any] { return arr.flatMap { unknownClasses(in: $0) } }
  return []
}

/// Verifies all round-trip invariants for one example folder.
private func verifyExampleFolder(exampleURL: URL, items: [URL]) throws {
  let channelStrips = items.filter { ["cst", "patch"].contains($0.pathExtension.lowercased()) }
  let childAUFiles = items.filter { ["pst", "aupreset"].contains($0.pathExtension.lowercased()) }

  if !channelStrips.isEmpty {
    let patchBundles = try patchBundleURLs(in: exampleURL)
    for bundle in patchBundles { try roundTripPatch(at: bundle) }
    let reps = try collectRepresentations(channelStrips: channelStrips, patchBundles: patchBundles)
    for child in childAUFiles {
      assertChildEmbedded(child, childData: try Data(contentsOf: child), in: reps)
    }
    try assertCodableRoundTrips(for: reps)
  }

  for child in childAUFiles {
    let data = try Data(contentsOf: child)
    if child.pathExtension.lowercased() == Pst.pathExtension {
      #expect(
        try Pst(data: data).data() == data, "PST round-trip failed for \(child.lastPathComponent)")
    } else if child.pathExtension.lowercased() == Aupreset.pathExtension {
      #expect(
        try Aupreset(data: data).data() == data,
        "Aupreset round-trip failed for \(child.lastPathComponent)")
    }
  }
}

// MARK: - Test

/// End-to-end smoke test over every fixture in `Tests/Resources/examples/`.
///
/// For each example folder the test:
/// - Parses every `.cst` and asserts binary round-trip fidelity.
/// - Parses every `.patch` bundle via `Patch(contentsOf:)`, writes it to a temp directory via `write(to:)`, and asserts each written file is byte-for-byte identical to the original.
/// - Parses every standalone `.pst` and `.aupreset` and asserts binary round-trip fidelity.
/// - Verifies that each standalone child preset file's bytes (or plist content) are embedded somewhere in the channel strip data.
/// - For `KeyedArchive` plugin slots, asserts that all ObjC classes in `decoded` are recognised — any unhandled class degrades to a plain dict with a `__class__` key, which is flagged as a test failure.
/// - Runs a JSON `Codable` round-trip on every parsed `Cst`, `Pst`, and `Aupreset` and re-checks binary fidelity after decode.
///
/// Each example folder is verified independently so that failures identify which fixture broke.
@Test func testExamplesRoundTrip() throws {
  let resourceURLs = collectExampleURLs()
  #expect(resourceURLs.count > 0, "No example fixtures found")

  let folders = groupByExampleFolder(resourceURLs)
  #expect(folders.count > 0, "No example folders found")

  for (exampleURL, items) in folders.sorted(by: { $0.key.path < $1.key.path }) {
    try verifyExampleFolder(exampleURL: exampleURL, items: items)
  }
}
