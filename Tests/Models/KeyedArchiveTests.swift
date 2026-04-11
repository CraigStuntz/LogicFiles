import Foundation
import Testing

@testable import LogicFiles

// MARK: - Helpers

private func keyedArchiveBlob(resource: String, subdirectory: String, atFileOffset offset: Int)
  throws -> Data
{
  let url = requireTestResourceURL(resource, extension: "cst", subdirectory: subdirectory)
  let data = try Data(contentsOf: url)
  let lengthIndex = offset - 4
  let length = Int(
    data.subdata(in: lengthIndex..<(lengthIndex + 4)).withUnsafeBytes {
      $0.load(as: UInt32.self).littleEndian
    })
  return data.subdata(in: offset..<(offset + length))
}

private let channelStripSubdir = "Retro Synth Defaults"

// MARK: - KeyedArchive init

@Test func testKeyedArchiveInvalidData() {
  #expect(throws: KeyedArchiveError.self) {
    _ = try KeyedArchive(data: Data("not a plist".utf8))
  }
}

@Test func testKeyedArchiveNotNSKeyedArchiver() throws {
  let regularPlist: [String: Any] = ["key": "value"]
  let plistData = try PropertyListSerialization.data(
    fromPropertyList: regularPlist, format: .binary, options: 0)
  #expect(throws: KeyedArchiveError.self) {
    _ = try KeyedArchive(data: plistData)
  }
}

@Test func testKeyedArchiveRoundTrip() throws {
  let blob = try keyedArchiveBlob(
    resource: "Channel Strip", subdirectory: channelStripSubdir, atFileOffset: 11146)
  let archive = try KeyedArchive(data: blob)
  #expect(try archive.data() == blob)
}

@Test func testKeyedArchiveCodableRoundTrip() throws {
  let blob = try keyedArchiveBlob(
    resource: "Channel Strip", subdirectory: channelStripSubdir, atFileOffset: 11146)
  let archive = try KeyedArchive(data: blob)
  let encoded = try JSONEncoder().encode(archive)
  let decoded = try JSONDecoder().decode(KeyedArchive.self, from: encoded)
  #expect(try decoded.data() == blob)
}

// MARK: - decoded dict

@Test func testKeyedArchiveDecodedTopKeys() throws {
  let blob = try keyedArchiveBlob(
    resource: "Channel Strip", subdirectory: channelStripSubdir, atFileOffset: 11146)
  let archive = try KeyedArchive(data: blob)
  let d = archive.decoded
  #expect(d.keys.contains("dictionary"), "Top-level decoded dict should have a 'dictionary' key")
}

@Test func testKeyedArchiveDecodedDictionaryKeys() throws {
  let blob = try keyedArchiveBlob(
    resource: "Channel Strip", subdirectory: channelStripSubdir, atFileOffset: 11146)
  let archive = try KeyedArchive(data: blob)
  guard let inner = archive.decoded["dictionary"] as? [String: Any] else {
    #expect(Bool(false), "decoded['dictionary'] should be [String: Any]")
    return
  }
  #expect(inner.keys.contains("layer"))
  #expect(inner.keys.contains("Track Settings"))
}

// MARK: - MAKeyboardLayer

@Test func testMAKeyboardLayerDefaults() throws {
  let blob = try keyedArchiveBlob(
    resource: "Channel Strip", subdirectory: channelStripSubdir, atFileOffset: 11146)
  let archive = try KeyedArchive(data: blob)
  guard let layer = archive.environmentLayer else {
    #expect(Bool(false), "Should have an MAKeyboardLayer")
    return
  }
  #expect(layer.lowNote == 0)
  #expect(layer.highNote == 127)
  #expect(layer.lowVelocity == 1)
  #expect(layer.highVelocity == 127)
  #expect(layer.transpose == 0)
  #expect(!layer.noTranspose)
  #expect(!layer.multitimbralEnabled)
  #expect(layer.keyboardIndex == 0)
}

@Test func testMAKeyboardLayerGraphPoints() throws {
  let blob = try keyedArchiveBlob(
    resource: "Channel Strip", subdirectory: channelStripSubdir, atFileOffset: 11146)
  let archive = try KeyedArchive(data: blob)
  guard let layer = archive.environmentLayer else {
    #expect(Bool(false), "Should have an MAKeyboardLayer")
    return
  }
  #expect(layer.keyScalingGraph.count == 2)
  #expect(layer.velocityResponseGraph.count == 2)
  let vr = layer.velocityResponseGraph
  #expect(vr[0].x == 0.0)
  #expect(vr[0].y == 0.0)
  #expect(vr[1].x == 1.0)
  #expect(vr[1].y == 1.0)
}

@Test func testKeyedArchiveWithoutEnvironmentLayer() throws {
  let blob = try keyedArchiveBlob(
    resource: "Channel Strip", subdirectory: channelStripSubdir, atFileOffset: 7245)
  let archive = try KeyedArchive(data: blob)
  #expect(
    archive.environmentLayer == nil,
    "MAPlugInParameterMapping archive should have no environmentLayer")
}
