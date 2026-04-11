import Foundation
import Testing

@testable import LogicFiles

@Test func testAnalyzePayloadDirect() throws {
  let url = requireTestResourceURL("RS2", extension: "pst")
  let data = try Data(contentsOf: url)

  let pst = try Pst(data: data)
  let payload = pst.payload

  let regions = try PayloadAnalyzer.analyze(payload: payload, windowFloats: 8)
  #expect(regions.count > 0)
  let first = regions[0]
  #expect(first.sampleValues.count == first.floatCount)
  #expect(first.sensibleCount >= 1)
}

@Test func testAnalyzePayloadViaPST() throws {
  let url = requireTestResourceURL("RS2", extension: "pst")
  let data = try Data(contentsOf: url)
  let pst = try Pst(data: data)

  let regions = try pst.analyzePayload(windowFloats: 8)
  #expect(regions.count > 0)
  #expect(regions[0].start >= 0)
}
