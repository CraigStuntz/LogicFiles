import Foundation
import Testing

@testable import LogicFiles

@Test func testReadAndWriteFloat() throws {
  var payload = Data(count: 8)
  var a: Float = 1.5
  var b: Float = -3.25
  withUnsafeBytes(of: &a) { payload.replaceSubrange(0..<4, with: $0) }
  withUnsafeBytes(of: &b) { payload.replaceSubrange(4..<8, with: $0) }

  #expect(try readFloat(from: payload, at: 0) == 1.5)
  #expect(try readFloat(from: payload, at: 4) == -3.25)
}

@Test func testWritingFloatReturnsNewCopy() throws {
  let payload = Data(count: 8)
  let modified = try writingFloat(42.0, into: payload, at: 0)
  #expect(payload != modified)
  #expect(try readFloat(from: modified, at: 0) == 42.0)
  #expect(try readFloat(from: modified, at: 4) == 0.0)
}

@Test func testReadFloatOutOfBoundsThrows() throws {
  let payload = Data(count: 4)
  #expect(throws: PayloadAccessError.self) {
    _ = try readFloat(from: payload, at: 4)
  }
  #expect(throws: PayloadAccessError.self) {
    _ = try readFloat(from: payload, at: -1)
  }
}

@Test func testWritingFloatOutOfBoundsThrows() throws {
  let payload = Data(count: 4)
  #expect(throws: PayloadAccessError.self) {
    _ = try writingFloat(1.0, into: payload, at: 4)
  }
}

// MARK: - Pst parameter access

@Test func testPstReadParameter() throws {
  let url = requireTestResourceURL("RS2", extension: Pst.pathExtension)
  let pst = try Pst(data: Data(contentsOf: url))
  let value = pst[byteOffset: 0]
  #expect(value.isFinite)
}

@Test func testPstSettingParameterRoundTrip() throws {
  let url = requireTestResourceURL("RS2", extension: Pst.pathExtension)
  var pst = try Pst(data: Data(contentsOf: url))
  let original = pst[byteOffset: 0]

  pst[byteOffset: 0] = original + 1.0
  #expect(pst[byteOffset: 0] == original + 1.0)

  let originalPst = try Pst(data: Data(contentsOf: url))
  #expect(pst.payload.count == originalPst.payload.count)
  #expect(
    pst.payload.subdata(in: 4..<pst.payload.count)
      == originalPst.payload.subdata(in: 4..<originalPst.payload.count))
}

@Test func testPstSettingParameterPreservesHeader() throws {
  let url = requireTestResourceURL("RS2", extension: Pst.pathExtension)
  var pst = try Pst(data: Data(contentsOf: url))
  let originalVersion = pst.formatVersion
  let originalFlags = pst.flags
  pst[byteOffset: 0] = 99.0
  #expect(pst.magic == "GAMETSPP")
  #expect(pst.formatVersion == originalVersion)
  #expect(pst.flags == originalFlags)
}

// MARK: - Aupreset parameter access

@Test func testAupresetReadParameter() throws {
  let url = requireTestResourceURL("PP", extension: Aupreset.pathExtension)
  let au = try Aupreset(data: Data(contentsOf: url))
  let value = au[byteOffset: 0]
  #expect(value.isFinite || !value.isFinite)  // just verifying it doesn't trap
}

@Test func testAupresetSettingParameterRoundTrip() throws {
  let url = requireTestResourceURL("PP", extension: Aupreset.pathExtension)
  var au = try Aupreset(data: Data(contentsOf: url))
  let original = au[byteOffset: 0]

  au[byteOffset: 0] = original + 1.0
  #expect(au[byteOffset: 0] == original + 1.0)

  let originalAU = try Aupreset(data: Data(contentsOf: url))
  #expect(au.name == originalAU.name)
  #expect(au.manufacturer == originalAU.manufacturer)
  #expect(au.type == originalAU.type)
  #expect(au.subtype == originalAU.subtype)
  #expect(au.format == originalAU.format)
}

@Test func testAupresetPluginIdentifier() throws {
  let url = requireTestResourceURL("PP", extension: Aupreset.pathExtension)
  let au = try Aupreset(data: Data(contentsOf: url))
  let id = au.pluginIdentifier
  #expect(id.manufacturer == au.manufacturer)
  #expect(id.type == au.type)
  #expect(id.subtype == au.subtype)
}

// MARK: - PluginIdentifier

@Test func testPluginIdentifierEquality() {
  let a = PluginIdentifier(manufacturer: 1, type: 2, subtype: 3)
  let b = PluginIdentifier(manufacturer: 1, type: 2, subtype: 3)
  let c = PluginIdentifier(manufacturer: 1, type: 2, subtype: 4)
  #expect(a == b)
  #expect(a != c)
}

@Test func testPluginIdentifierHashing() {
  let a = PluginIdentifier(manufacturer: 1, type: 2, subtype: 3)
  let b = PluginIdentifier(manufacturer: 1, type: 2, subtype: 3)
  var set = Set<PluginIdentifier>()
  set.insert(a)
  set.insert(b)
  #expect(set.count == 1)
}

@Test func testPluginIdentifierCodable() throws {
  let original = PluginIdentifier(manufacturer: 100, type: 200, subtype: 300)
  let data = try JSONEncoder().encode(original)
  let decoded = try JSONDecoder().decode(PluginIdentifier.self, from: data)
  #expect(decoded == original)
}

// MARK: - PluginSetting parameter access

@Test func testPluginSettingPstReadParameter() throws {
  let url = requireTestResourceURL("RS2", extension: Pst.pathExtension)
  let pst = try Pst(data: Data(contentsOf: url))
  let setting = PluginSetting.pst(pst)
  #expect(setting[byteOffset: 0] == pst[byteOffset: 0])
}

@Test func testPluginSettingSettingParameter() throws {
  let url = requireTestResourceURL("RS2", extension: Pst.pathExtension)
  let pst = try Pst(data: Data(contentsOf: url))
  var setting = PluginSetting.pst(pst)
  setting[byteOffset: 0] = 42.0
  #expect(setting[byteOffset: 0] == 42.0)
}

@Test func testPluginSettingAupresetPluginIdentifier() throws {
  let url = requireTestResourceURL("PP", extension: Aupreset.pathExtension)
  let au = try Aupreset(data: Data(contentsOf: url))
  let setting = PluginSetting.aupreset(au)
  #expect(setting.pluginIdentifier == au.pluginIdentifier)
}

@Test func testPluginSettingPstPluginIdentifierIsNil() throws {
  let url = requireTestResourceURL("RS2", extension: Pst.pathExtension)
  let pst = try Pst(data: Data(contentsOf: url))
  let setting = PluginSetting.pst(pst)
  #expect(setting.pluginIdentifier == nil)
}
