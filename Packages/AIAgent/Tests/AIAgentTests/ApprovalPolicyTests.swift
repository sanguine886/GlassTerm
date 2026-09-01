@testable import AIAgent
import XCTest

final class ApprovalPolicyTests: XCTestCase {
    private let classifier = DangerousCommandClassifier()

    private func classify(_ command: String) -> CommandClassification {
        classifier.classify(command)
    }

    private func decider() -> ApprovalDecider {
        ApprovalDecider(classifier: classifier)
    }

    // MARK: - alwaysAsk

    func testAlwaysAskRequiresReviewForEveryTool() {
        for toolName in ["run_command", "read_file", "write_file", "get_system_info", "run_snippet"] {
            let decision = decider().decide(
                classification: classify("ls /home"),
                modelDeclaredSafe: true,
                toolName: toolName,
                isReadonlyTool: toolName == "read_file" || toolName == "get_system_info",
                commandText: "ls /home",
                strategy: .alwaysAsk
            )
            XCTAssertEqual(decision, .requireReview, "\(toolName) under alwaysAsk should require review")
        }
    }

    // MARK: - autoReview

    func testAutoReviewApprovesSafeReadonlyDeclared() {
        let decision = decider().decide(
            classification: classify("ls /home"),
            modelDeclaredSafe: true,
            toolName: "read_file",
            isReadonlyTool: true,
            commandText: "ls /home",
            strategy: .autoReview
        )
        XCTAssertEqual(decision, .autoApprove)
    }

    func testAutoReviewRequiresReviewForSafeWrite() {
        let decision = decider().decide(
            classification: classify("ls /home"),
            modelDeclaredSafe: true,
            toolName: "write_file",
            isReadonlyTool: false,
            commandText: "ls /home",
            strategy: .autoReview
        )
        XCTAssertEqual(decision, .requireReview)
    }

    func testAutoReviewRequiresReviewForReadonlyNotDeclaredSafe() {
        let decision = decider().decide(
            classification: classify("ls /home"),
            modelDeclaredSafe: false,
            toolName: "read_file",
            isReadonlyTool: true,
            commandText: "ls /home",
            strategy: .autoReview
        )
        XCTAssertEqual(decision, .requireReview)
    }

    func testAutoReviewRequiresReviewForRunCommand() {
        let decision = decider().decide(
            classification: classify("ls /home"),
            modelDeclaredSafe: true,
            toolName: "run_command",
            isReadonlyTool: false,
            commandText: "ls /home",
            strategy: .autoReview
        )
        XCTAssertEqual(decision, .requireReview)
    }

    // MARK: - readOnly

    func testReadOnlyRunCommandWhitelistAutoApproves() {
        let decision = decider().decide(
            classification: classify("ls -la /tmp"),
            modelDeclaredSafe: true,
            toolName: "run_command",
            isReadonlyTool: false,
            commandText: "ls -la /tmp",
            strategy: .readOnly
        )
        XCTAssertEqual(decision, .autoApprove)
    }

    func testReadOnlyRunCommandNonWhitelistDenies() {
        // A safe but non-whitelisted write command must be denied outright.
        let decision = decider().decide(
            classification: classify("touch /tmp/generated.tmp"),
            modelDeclaredSafe: true,
            toolName: "run_command",
            isReadonlyTool: false,
            commandText: "touch /tmp/generated.tmp",
            strategy: .readOnly
        )
        XCTAssertEqual(decision, .deny)
    }

    func testReadOnlyWriteFileDenies() {
        let decision = decider().decide(
            classification: classify("ls /home"),
            modelDeclaredSafe: true,
            toolName: "write_file",
            isReadonlyTool: false,
            commandText: "ls /home",
            strategy: .readOnly
        )
        XCTAssertEqual(decision, .deny)
    }

    func testReadOnlyReadonlyToolAutoApproves() {
        let decision = decider().decide(
            classification: classify("ls /home"),
            modelDeclaredSafe: true,
            toolName: "read_file",
            isReadonlyTool: true,
            commandText: "ls /home",
            strategy: .readOnly
        )
        XCTAssertEqual(decision, .autoApprove)
    }

    // MARK: - dangerous / critical across all strategies

    func testDangerousRequiresTypedConfirmationAcrossAllStrategies() {
        let strategies: [ApprovalStrategy] = [.alwaysAsk, .autoReview, .readOnly]
        let dangerous = classify("rm -rf /tmp")
        for strategy in strategies {
            let decision = decider().decide(
                classification: dangerous,
                modelDeclaredSafe: true,
                toolName: "run_command",
                isReadonlyTool: false,
                commandText: "rm -rf /tmp",
                strategy: strategy
            )
            XCTAssertEqual(decision, .requireTypedConfirmation(typingRequired: false), "strategy \(strategy.rawValue)")
        }
    }

    func testCriticalRequiresFullTypedConfirmationAcrossAllStrategies() {
        let strategies: [ApprovalStrategy] = [.alwaysAsk, .autoReview, .readOnly]
        let critical = classify("shutdown -h now")
        for strategy in strategies {
            let decision = decider().decide(
                classification: critical,
                modelDeclaredSafe: true,
                toolName: "run_command",
                isReadonlyTool: false,
                commandText: "shutdown -h now",
                strategy: strategy
            )
            XCTAssertEqual(decision, .requireTypedConfirmation(typingRequired: true), "strategy \(strategy.rawValue)")
        }
    }

    func testSafeNeverTypedConfirmation() {
        let safe = classify("df -h")
        let strategies: [ApprovalStrategy] = [.alwaysAsk, .autoReview, .readOnly]
        for strategy in strategies {
            let decision = decider().decide(
                classification: safe,
                modelDeclaredSafe: false,
                toolName: "run_command",
                isReadonlyTool: false,
                commandText: "df -h",
                strategy: strategy
            )
            XCTAssertNotEqual(decision, .requireTypedConfirmation(typingRequired: true))
            XCTAssertNotEqual(decision, .requireTypedConfirmation(typingRequired: false))
        }
    }

    func testDangerousClassificationOutranksReadonlyStrategy() {
        // Strategy readOnly normally denies write tools, but a dangerous
        // command must require typed confirmation rather than a flat deny.
        let decision = decider().decide(
            classification: classify("chmod -R 777 ."),
            modelDeclaredSafe: false,
            toolName: "run_command",
            isReadonlyTool: false,
            commandText: "chmod -R 777 .",
            strategy: .readOnly
        )
        XCTAssertEqual(decision, .requireTypedConfirmation(typingRequired: false))
    }
}
