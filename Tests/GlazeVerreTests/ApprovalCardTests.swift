import GlassKit
import XCTest

final class ApprovalCardTests: XCTestCase {
    func testProposalDefaultsToNonDangerous() {
        let proposal = ApprovalCard.Proposal(
            titleKey: "approval.sample.title",
            command: "df -h /",
            impactSummaryKey: "approval.sample.impact"
        )

        XCTAssertFalse(proposal.isDangerous)
        XCTAssertEqual(proposal.command, "df -h /")
    }

    func testDangerousProposalCarriesFullCommandForHumanReview() {
        let proposal = ApprovalCard.Proposal(
            titleKey: "approval.sample.title",
            command: "rm -rf /tmp/build",
            impactSummaryKey: "approval.sample.impact",
            isDangerous: true
        )

        XCTAssertTrue(proposal.isDangerous)
        XCTAssertEqual(proposal.command, "rm -rf /tmp/build")
    }
}
