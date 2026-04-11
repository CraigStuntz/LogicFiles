import Foundation
import Testing

@testable import LogicFiles

@Test func testParseAUPreset() throws {
  let url = requireTestResourceURL("PP", extension: Aupreset.pathExtension)
  let data = try Data(contentsOf: url)
  let au = try Aupreset(data: data)
  #expect(au.format == .binary || au.format == .xml)
  let round = try au.data()
  #expect(round == data)
}

@Test func testDecodeAUPresetPayload() throws {
  let url = requireTestResourceURL("PP", extension: Aupreset.pathExtension)
  let data = try Data(contentsOf: url)
  let au = try Aupreset(data: data)
  let payload = au.payload
  #expect(payload != nil)
  #expect(payload!.count > 0)
}

@Test func testAUPresetAnalyzePayload() throws {
  let url = requireTestResourceURL("PP", extension: Aupreset.pathExtension)
  let data = try Data(contentsOf: url)
  let au = try Aupreset(data: data)
  let regions = try au.analyzePayload(windowFloats: 8)
  #expect(regions.count >= 0)  // allow zero for non-PST payloads, but ensure call succeeds
  if regions.count > 0 {
    let r = regions[0]
    #expect(r.sampleValues.count == r.floatCount)
  }
}

@Test func testAUPresetTryParsePreset() throws {
  let url = requireTestResourceURL("PP", extension: Aupreset.pathExtension)
  let data = try Data(contentsOf: url)
  let au = try Aupreset(data: data)
  let detection = au.tryParsePreset()
  #expect(detection.size > 0)
}

@Test func testAupresetCodable() throws {
  let url = requireTestResourceURL("PP", extension: Aupreset.pathExtension)
  let data = try Data(contentsOf: url)
  let originalAu = try Aupreset(data: data)

  let jsonData = try JSONEncoder().encode(originalAu)
  let decodedAu = try JSONDecoder().decode(Aupreset.self, from: jsonData)

  #expect(try decodedAu.data() == (try originalAu.data()))
  #expect(decodedAu.format == originalAu.format)
}
