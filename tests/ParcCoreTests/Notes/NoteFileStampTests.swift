import Foundation
import Testing
@testable import ParcCore

struct NoteFileStampTests {
    @Test func aDeviceNumberWithItsHighBitSetStillMakesAStamp() {
        var info = stat()
        info.st_dev = -1
        info.st_ino = 42
        info.st_size = 7
        let stamp = NoteFileStamp(info)
        #expect(stamp.inode == 42)
        #expect(stamp.size == 7)
        #expect(stamp.device == UInt64(truncatingIfNeeded: info.st_dev))
    }

    @Test func twoStampsOfTheSameFileAreEqual() {
        var info = stat()
        info.st_dev = Int32.min
        #expect(NoteFileStamp(info) == NoteFileStamp(info))
    }
}
