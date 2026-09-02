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

    func testEntryFromComponentMapsFields() {
        var attrs = SFTPFileAttributes()
        attrs.permissions = 0o100644
        attrs.size = 42
        let comp = SFTPPathComponent(
            filename: "notes.txt",
            longname: "-rw-r--r-- 1 u g 42 Jan 1 00:00 notes.txt",
            attributes: attrs
        )
        let entry = CitadelSFTP.entry(from: comp)
        XCTAssertEqual(entry.name, "notes.txt")
        XCTAssertEqual(entry.kind, .file)
        XCTAssertEqual(entry.size, 42)
        XCTAssertEqual(entry.permissions, 0o100644)
    }

    func testEntryFromComponentDirWithoutSize() {
        let comp = component("drwxr-xr-x", permissions: 0o040755)
        let entry = CitadelSFTP.entry(from: comp)
        XCTAssertEqual(entry.kind, .directory)
        XCTAssertNil(entry.size)
    }
}
