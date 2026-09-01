import CoreSSH
import XCTest

final class SFTPPathTests: XCTestCase {
    func testNormalizedRemovesTrailingSlash() {
        XCTAssertEqual(SFTPPath.normalized("/home/user/"), "/home/user")
        XCTAssertEqual(SFTPPath.normalized("/"), "/")
        XCTAssertEqual(SFTPPath.normalized(""), "/")
        XCTAssertEqual(SFTPPath.normalized("//"), "/")
    }

    func testJoining() {
        XCTAssertEqual(SFTPPath.joining("/home", "file.txt"), "/home/file.txt")
        XCTAssertEqual(SFTPPath.joining("/home/", "/file.txt"), "/home/file.txt")
        XCTAssertEqual(SFTPPath.joining("/", "etc"), "/etc")
        XCTAssertEqual(SFTPPath.joining("/home", ""), "/home")
        XCTAssertEqual(SFTPPath.joining("/", "a/b"), "/a/b")
    }

    func testParent() {
        XCTAssertEqual(SFTPPath.parent(of: "/home/user"), "/home")
        XCTAssertEqual(SFTPPath.parent(of: "/home"), "/")
        XCTAssertEqual(SFTPPath.parent(of: "/"), "/")
        XCTAssertEqual(SFTPPath.parent(of: "/a/b/c"), "/a/b")
        XCTAssertEqual(SFTPPath.parent(of: "file"), "/")
    }

    func testDisplayName() {
        XCTAssertEqual(SFTPPath.displayName(of: "/home/user/file.txt"), "file.txt")
        XCTAssertEqual(SFTPPath.displayName(of: "/"), "/")
        XCTAssertEqual(SFTPPath.displayName(of: "file.txt"), "file.txt")
        XCTAssertEqual(SFTPPath.displayName(of: "/a/b/"), "b")
    }

    func testNormalizedPreservesNonSlashPath() {
        XCTAssertEqual(SFTPPath.normalized("etc"), "etc")
        XCTAssertEqual(SFTPPath.normalized("etc/passwd"), "etc/passwd")
    }
}
