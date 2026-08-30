import GlassKit
import SwiftUI

struct AssistantView: View {
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text("tab.assistant"))
                .background(Color.glassBackground.ignoresSafeArea())
        }
    }

    private var content: some View {
        GlassEffectContainer(spacing: GlassSpacing.md) {
            ScrollView {
                VStack(spacing: GlassSpacing.md) {
                    PlaceholderSection(
                        headingID: "screen.assistant.heading",
                        titleKey: "placeholder.assistant.title",
                        bodyKey: "placeholder.assistant.body"
                    )
                    ApprovalCard(
                        proposal: ApprovalCard.Proposal(
                            titleKey: "approval.sample.title",
                            command: "df -h /",
                            impactSummaryKey: "approval.sample.impact"
                        ),
                        onApprove: {},
                        onReject: {}
                    )
                }
                .padding(GlassSpacing.lg)
            }
        }
    }
}
