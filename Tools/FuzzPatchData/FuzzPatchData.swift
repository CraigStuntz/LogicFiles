import Foundation
import LogicFiles

@_cdecl("LLVMFuzzerTestOneInput")
public func testOneInput(_ start: UnsafeRawPointer, _ count: Int) -> CInt {
  autoreleasepool {
    let data = Data(bytes: start, count: count)
    _ = try? PatchData(data: data)
    return 0
  }
}
