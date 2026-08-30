import SwiftUI

/// Approval card for AI agent proposals (spec §4.6).
/// P0 ships the visual shell only; approval policies (alwaysAsk / autoReview /
/// read-only), the dangerous-command classifier, and the kill switch land in P5.
public struct ApprovalCard: View {
    public struct Proposal: Equatable {
        public var titleKey: LocalizedStringKey
        public var command: String
        public var impactSummaryKey: LocalizedStringKey
        public var isDangerous: Bool

        public init(
            titleKey: LocalizedStringKey,
            command: String,
            impactSummaryKey: LocalizedStringKey,
            isDangerous: Bool = false
        ) {
            self.titleKey = titleKey
            self.command = command
            self.impactSummaryKey = impactSummaryKey
            self.isDangerous = isDangerous
        }
    }

    private let proposal: Proposal
    private let onApprove: () -> Void
    private let onReject: () -> Void

    public init(
        proposal: Proposal,
        onApprove: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) {
        self.proposal = proposal
        self.onApprove = onApprove
        self.onReject = onReject
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: GlassSpacing.md) {
            Label {
                Text(proposal.titleKey)
            } icon: {
                Image(systemName: proposal.isDangerous ? "exclamationmark.triangle.fill" : "terminal")
            }
            .font(.headline)
            .foregroundStyle(proposal.isDangerous ? Color.glassDanger : Color.glassPrimaryText)

            Text(proposal.command)
                .font(.glassMono(13))
                .foregroundStyle(Color.glassPrimaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(GlassSpacing.sm)
                .background(
                    Color.glassSurface,
                    in: RoundedRectangle(cornerRadius: GlassSpacing.sm, style: .continuous)
                )
                .textSelection(.enabled)

            Text(proposal.impactSummaryKey)
                .font(.footnote)
                .foregroundStyle(Color.glassSecondaryText)

            HStack(spacing: GlassSpacing.md) {
                GlassButton("approval.reject", role: .regular, action: onReject)
                Spacer()
                GlassButton("approval.approve", role: .prominent, action: onApprove)
            }
        }
        .padding(GlassSpacing.lg)
        .glassEffect(
            glass,
            in: RoundedRectangle(cornerRadius: GlassSpacing.xl, style: .continuous)
        )
    }

    private var glass: Glass {
        proposal.isDangerous ? Glass.regular.tint(.glassDanger) : Glass.regular
    }
}
