import Foundation
import Testing

@testable import LogicFiles

@Test func testPSTRoundTrip() throws {
  let url = requireTestResourceURL("RS2", extension: Pst.pathExtension)
  let data = try Data(contentsOf: url)
  let pst = try Pst(data: data)
  let out = try pst.data()
  #expect(data == out)
}

@Test func testEmagicParsing() throws {
  let url = requireTestResourceURL("RS2", extension: Pst.pathExtension)
  let data = try Data(contentsOf: url)
  let pst = try Pst(data: data)

  #expect(pst.magic == "GAMETSPP")
  #expect(pst.formatVersion == 1)
  #expect(pst.payload.count > 0)

  let serialized = try pst.data()
  #expect(serialized == data)
}

@Test func testInvalidPstThrows() throws {
  let url = requireTestResourceURL("sample", extension: Pst.pathExtension)
  let data = try Data(contentsOf: url)
  #expect(throws: (any Error).self) {
    _ = try Pst(data: data)
  }
}

@Test func testPayloadAnalyzer() throws {
  let url = requireTestResourceURL("RS2", extension: Pst.pathExtension)
  let data = try Data(contentsOf: url)
  let pst = try Pst(data: data)
  let regions = try pst.analyzePayload(windowFloats: 8)
  #expect(regions.count > 0)
  let first = regions[0]
  #expect(first.floatCount == 8)
  #expect(first.sampleValues.count == 8)
  #expect(first.sampleValues[0].isFinite)
}

@Test func testPSTTryParsePreset() throws {
  let url = requireTestResourceURL("RS2", extension: Pst.pathExtension)
  let data = try Data(contentsOf: url)
  let pst = try Pst(data: data)
  let detection = pst.tryParsePreset()
  #expect(detection.size > 0)
}

@Test func testPstCodable() throws {
  let url = requireTestResourceURL("RS2", extension: Pst.pathExtension)
  let data = try Data(contentsOf: url)
  let originalPst = try Pst(data: data)

  let jsonData = try JSONEncoder().encode(originalPst)
  let decodedPst = try JSONDecoder().decode(Pst.self, from: jsonData)

  #expect(try decodedPst.data() == (try originalPst.data()))
  #expect(decodedPst.magic == originalPst.magic)
  #expect(decodedPst.payload == originalPst.payload)
}
