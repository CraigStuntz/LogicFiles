import Foundation

/// A type-erased wrapper around a parsed plist dictionary that satisfies `Sendable`.
/// Foundation's plist object types (NSString, NSNumber, NSData, NSDictionary, NSArray)
/// are all thread-safe, so @unchecked Sendable is appropriate here.
struct PlistDict: @unchecked Sendable {
  let storage: [String: Any]
  init(_ storage: [String: Any]) { self.storage = storage }
}

func parsePlist(from data: Data) throws -> (Any, PropertyListSerialization.PropertyListFormat) {
  var format = PropertyListSerialization.PropertyListFormat.xml
  let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
  return (plist, format)
}
