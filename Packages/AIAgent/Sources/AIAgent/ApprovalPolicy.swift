/// ApprovalStrategy — how the UI decides whether an agent tool proposal needs
/// human sign-off.
public enum ApprovalStrategy: String, Codable, Sendable, Equatable {
    /// Every proposal is surfaced for review.
    case alwaysAsk
    /// Read-only, model-declared-safe proposals auto-approve; everything else
    /// is reviewed.
    case autoReview
    /// Only read-only operations are allowed at all.
    case readOnly
}

/// ApprovalDecision — the outcome the policy produced for a single proposal.
public enum ApprovalDecision: Sendable, Equatable {
    /// Proceeds without human involvement.
    case autoApprove
    /// Show the proposal to the user for review.
    case requireReview
    /// Require the user to type the confirmation phrase (optionally the full
    /// dangerous command) instead of a single tap.
    case requireTypedConfirmation(typingRequired: Bool)
    /// The proposal must not run.
    case deny
}

/// ApprovalDeciding — pure decision logic for tool proposals.
///
/// The decision function is stated in terms of the classification and safe
/// flags rather than an `AgentProposal` to avoid coupling P5 to P4. The raw
/// `commandText` is included so the read-only strategy can consult the
/// whitelist for `run_command`; when the P4 `AgentProposal` type lands, a thin
/// adapter can feed these fields from it.
public protocol ApprovalDeciding: Sendable {
    func decide(
        classification: CommandClassification,
        modelDeclaredSafe: Bool,
        toolName: String,
        isReadonlyTool: Bool,
        commandText: String,
        strategy: ApprovalStrategy
    ) -> ApprovalDecision
}

/// ApprovalDecider — the canonical implementation of the decision state
/// machine.
///
/// The state machine is ordered and non-swappable:
/// 1. critical classification  → typed confirmation (full command)
/// 2. dangerous classification → typed confirmation (short phrase)
/// 3. safe classification      → strategy-specific rules
public struct ApprovalDecider: ApprovalDeciding, Sendable {
    public let classifier: DangerousCommandClassifier

    public init(classifier: DangerousCommandClassifier = DangerousCommandClassifier()) {
        self.classifier = classifier
    }

    public func decide(
        classification: CommandClassification,
        modelDeclaredSafe: Bool,
        toolName: String,
        isReadonlyTool: Bool,
        commandText: String,
        strategy: ApprovalStrategy
    ) -> ApprovalDecision {
        switch classification.verdict {
        case .critical:
            return .requireTypedConfirmation(typingRequired: true)
        case .dangerous:
            return .requireTypedConfirmation(typingRequired: false)
        case .safe:
            switch strategy {
            case .alwaysAsk:
                return .requireReview
            case .autoReview:
                if modelDeclaredSafe && isReadonlyTool {
                    return .autoApprove
                }
                return .requireReview
            case .readOnly:
                if toolName == "run_command" {
                    return classifier.isReadOnlyWhitelisted(commandText) ? .autoApprove : .deny
                }
                return isReadonlyTool ? .autoApprove : .deny
            }
        }
    }
}
