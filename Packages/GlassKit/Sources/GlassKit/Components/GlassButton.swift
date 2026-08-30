import SwiftUI

/// Glass button built on the system glass button styles (spec §3.2).
public struct GlassButton: View {
    public enum Role {
        case regular
        case prominent
        case destructive
    }

    private let titleKey: LocalizedStringKey
    private let systemImage: String?
    private let role: Role
    private let action: () -> Void

    public init(
        _ titleKey: LocalizedStringKey,
        systemImage: String? = nil,
        role: Role = .regular,
        action: @escaping () -> Void
    ) {
        self.titleKey = titleKey
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    public var body: some View {
        switch role {
        case .regular:
            button.buttonStyle(.glass)
        case .prominent:
            button.buttonStyle(.glassProminent)
        case .destructive:
            button
                .buttonStyle(.glass)
                .tint(.glassDanger)
        }
    }

    private var button: some View {
        Button(action: action) {
            if let systemImage {
                Label(titleKey, systemImage: systemImage)
            } else {
                Text(titleKey)
            }
        }
    }
}
