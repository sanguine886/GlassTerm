import CoreSSH
import XCTest

final class SFTPModelTests: XCTestCase {
    func testEntryKindEquatable() {
        XCTAssertEqual(SFTPEntry.Kind.file, .file)
        XCTAssertNotEqual(SFTPEntry.Kind.file, .directory)
        XCTAssertNotEqual(SFTPEntry.Kind.symlink, .file)
    }

    func testEntryInitFields() {
        let entry = SFTPEntry(name: "a.txt", kind: .file, size: 12, permissions: 0o644)
        XCTAssertEqual(entry.name, "a.txt")
        XCTAssertEqual(entry.kind, .file)
        XCTAssertEqual(entry.size, 12)
        XCTAssertEqual(entry.permissions, 0o644)
    }

    func testEntryMissingMetadata() {
        let entry = SFTPEntry(name: "dir", kind: .directory, size: nil, permissions: nil)
        XCTAssertNil(entry.size)
        XCTAssertNil(entry.permissions)
    }

    func testEntryEquality() {
        let a = SFTPEntry(name: "x", kind: .file, size: 1, permissions: 0o644)
        let b = SFTPEntry(name: "x", kind: .file, size: 1, permissions: 0o644)
        let c = SFTPEntry(name: "y", kind: .file, size: 1, permissions: 0o644)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testSFTPErrorCasesEquatable() {
        XCTAssertEqual(SFTPError.notConnected, .notConnected)
        XCTAssertEqual(SFTPError.operationFailed("boom"), .operationFailed("boom"))
        XCTAssertNotEqual(SFTPError.operationFailed("a"), .operationFailed("b"))
        XCTAssertNotEqual(SFTPError.notConnected, .operationFailed("x"))
    }
}