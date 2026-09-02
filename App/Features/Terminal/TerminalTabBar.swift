import GlassKit
import SwiftUI
import TerminalKit

/// Bottom glass tab bar for terminal sessions (spec §4.3: 标签页式，左滑关闭).
struct TerminalTabBar: View {
    @Bindable var model: SessionTabsModel
    let onClose: (UUID) -> Void

    var body: some View {
        GlassEffectContainer(spacing: GlassSpacing.sm) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GlassSpacing.sm) {
                    ForEach(model.tabs) { tab in
                        tabChip(tab)
                    }
                }
                .padding(.horizontal, GlassSpacing.md)
                .padding(.vertical, GlassSpacing.sm)
            }
        }
    }

    private func tabChip(_ tab: SessionTabsModel.Tab) -> some View {
        Button {
            model.activate(id: tab.id)
        } label: {
            HStack(spacing: 6) {
                Text(tab.title)
                    .font(.footnote)
                    .lineLimit(1)
                if tab.isActive {
                    Button {
                        onClose(tab.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                tab.isActive ? Color.glassSurface : Color.clear,
                in: Capsule()
            )
            .foregroundStyle(tab.isActive ? Color.glassPrimaryText : Color.glassSecondaryText)
        }
        .buttonStyle(.plain)
    }
}
