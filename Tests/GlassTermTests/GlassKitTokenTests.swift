import GlassKit
import XCTest

final class GlassKitTokenTests: XCTestCase {
    func testSpacingScaleMatchesDesignSpec() {
        XCTAssertEqual(GlassSpacing.all, [4, 8, 12, 16, 24, 32])
    }

    func testSpacingScaleIsStrictlyAscendingWithoutDuplicates() {
        let values = GlassSpacing.all
        XCTAssertEqual(values, values.sorted())
        XCTAssertEqual(Set(values).count, values.count)
    }
}
