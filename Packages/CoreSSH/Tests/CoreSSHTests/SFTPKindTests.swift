import Citadel
@testable import CoreSSH
import XCTest

/// Tests the pure static `CitadelSFTP.kind(of:)` inference from Unix mode
/// type bits and the ls-style `longname` fallback.
final class SFTPKindTests: XCTestCase {
    private func component(_ longname: String, permissions: UInt32?) -> SFTPPathComponent {
        var attributes = SFTPFileAttributes()
        attributes.permissions = permissions
        return SFTPPathComponent(filename: "x", longname: longname, attributes: attributes)
    }

    func testKindFromModeBits() {
        // S_IFDIR 0x4000, S_IFREG 0x8000, S_IFLNK 0xA000
        XCTAssertEqual(CitadelSFTP.kind(of: component("-rw-r--r--", permissions: 0o100644)), .file)
        XCTAssertEqual(CitadelSFTP.kind(of: component("drwxr-xr-x", permissions: 0o040755)), .directory)
        XCTAssertEqual(CitadelSFTP.kind(of: component("lrwxrwxrwx", permissions: 0o120777)), .symlink)
    }

    func testKindFallsBackToLongname() {
        XCTAssertEqual(CitadelSFTP.kind(of: component("d……", permissions: nil)), .directory)
        XCTAssertEqual(CitadelSFTP.kind(of: component("-rw-r--r--", permissions: nil)), .file)
        XCTAssertEqual(CitadelSFTP.kind(of: component("lrwxrwxrwx", permissions: nil)), .symlink)
    }

    func testKindUnknownWithoutTypeBits() {
        XCTAssertEqual(CitadelSFTP.kind(of: component("???", permissions: nil)), .unknown)
    }
}

