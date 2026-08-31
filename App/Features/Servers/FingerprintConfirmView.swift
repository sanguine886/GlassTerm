import CoreSSH
import GlassKit
import SwiftUI

/// Host-key confirmation (TOFU, spec §4.1). `.new` shows the fingerprint for a
/// first connection; `.changed` is the red warning form for a key change —
/// the connection stays blocked until the user explicitly re-pins.
struct FingerprintConfirmView: View {
    let kind: FingerprintFlowKind
    /// Called with `true` when the user chooses to trust / re-pin.
    let onDecision: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GlassSpacing.md) {
            Label {
                Text(titleKey)
            } icon: {
                Image(systemName: isChanged ? "exclamationmark.triangle.fill" : "fingerprint")
            }
            .font(.headline)
            .foregroundStyle(isChanged ? Color.glassDanger : Color.glassPrimaryText)

            Text(bodyKey)
                .font(.subheadline)
                .foregroundStyle(Color.glassSecondaryText)

            VStack(alignment: .leading, spacing: GlassSpacing.xs) {
                if case .changed(let pinned, _) = kind {
                fingerprintRow(labelKey: "fp.pinned", fingerprint: pinned)
            }
                fingerprintRow(labelKey: "fp.presented", fingerprint: presented)
            }
            .padding(GlassSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.glassSurface,
                in: RoundedRectangle(cornerRadius: GlassSpacing.md, style: .continuous)
            )

            Text("fp.warning")
                .font(.footnote)
                .foregroundStyle(Color.glassSecondaryText)

            HStack(spacing: GlassSpacing.md) {
                GlassButton("common.cancel") { onDecision(false) }
                Spacer()
                GlassButton(confirmKey, role: isChanged ? .destructive : .prominent) {
                    onDecision(true)
                }
            }
        }
        .padding(GlassSpacing.lg)
        .glassEffect(
            Glass.regular.tint(isChanged ? .glassDanger : nil),
            in: RoundedRectangle(cornerRadius: GlassSpacing.xl, style: .continuous)
        )
        .padding(GlassSpacing.xl)
        .presentationDetents([.medium])
    }

    private var isChanged: Bool {
        if case .changed = kind {
            return true
        }
        return false
    }

    private var titleKey: LocalizedStringKey {
        isChanged ? "fp.changed.title" : "fp.new.title"
    }

    private var bodyKey: LocalizedStringKey {
        isChanged ? "fp.changed.body" : "fp.new.body"
    }

    private var confirmKey: LocalizedStringKey {
        isChanged ? "fp.changed.confirm" : "fp.new.confirm"
    }

    private var presented: HostKeyFingerprint {
        switch kind {
        case let .new():
            fingerprint
        case let .changed(_, ):
            changed
        }
    }

    private func fingerprintRow(labelKey: LocalizedStringKey, fingerprint: HostKeyFingerprint) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(labelKey)
                .font(.caption2)
                .foregroundStyle(Color.glassSecondaryText)
            Text("\(fingerprint.algorithm)  \(fingerprint.sha256)")
                .font(.glassMono(11))
                .foregroundStyle(Color.glassPrimaryText)
                .textSelection(.enabled)
        }
    }
}
