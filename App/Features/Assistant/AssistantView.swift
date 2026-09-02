import AIAgent
import GlassKit
import SwiftUI

/// AI assistant chat (spec §4.5): multi-session transcript, streaming turns,
/// Markdown rendering and a "what will be sent" preview.
struct AssistantView: View {
    @Environment(AIProviderManager.self) private var providers
    @Environment(ChatManager.self) private var chat

    enum Mode: String, CaseIterable, Identifiable {
        case chat
        case agent
        var id: String {
            rawValue
        }
    }

    @State private var mode = Mode.chat
    @State private var draft = ""
    @State private var showPreview = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("assistant.mode", selection: $mode) {
                    Text("assistant.mode.chat").tag(Mode.chat)
                    Text("assistant.mode.agent").tag(Mode.agent)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, GlassSpacing.md)
                .padding(.top, GlassSpacing.xs)

                ZStack {
                    if mode == .chat {
                        content
                    } else {
                        AgentView()
                    }
                }
            }
            .navigationTitle(Text("tab.assistant"))
            .navigationBarTitleDisplayMode(.inline)
            .background(Color.glassBackground.ignoresSafeArea())
            .accessibilityIdentifier("screen.assistant.heading")
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    if mode == .chat {
                        sessionMenu
                    }
                }
            }
        }
    }

    private var sessionMenu: some View {
        Menu {
            Button("chat.new", systemImage: "square.and.pencil") {
                chat.newSession()
            }
            ForEach(chat.sessions, id: \.id) { session in
                Button {
                    chat.load(sessionID: session.id)
                } label: {
                    Text(session.title)
                }
            }
        } label: {
            Label(activeSessionTitle, systemImage: "text.bubble")
        }
    }

    private var activeSessionTitle: String {
        chat.sessions.first(where: { $0.id == chat.activeSessionID })?.title
            ?? String(localized: "chat.placeholder")
    }

    private var content: some View {
        GlassEffectContainer(spacing: GlassSpacing.md) {
            VStack(spacing: 0) {
                if providers.activeProviderConfig != nil {
                    transcript
                } else {
                    noProvider
                }
                composer
            }
        }
    }

    /// Placeholder when no provider is configured yet.
    private var noProvider: some View {
        VStack(spacing: GlassSpacing.md) {
            ContentUnavailableView(
                "chat.noProvider",
                systemImage: "brain.head.profile",
                description: Text("chat.noProviderHint")
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: GlassSpacing.md) {
                    ForEach(chat.turns) { turn in
                        TurnBubble(turn: turn)
                    }
                    if chat.isStreaming {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("chat.streaming")
                                .font(.caption)
                                .foregroundStyle(Color.glassSecondaryText)
                            Spacer()
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(GlassSpacing.md)
            }
            .onChange(of: chat.turns.count) {
                withAnimation {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: chat.isStreaming) {
                if chat.isStreaming {
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: GlassSpacing.sm) {
            HStack {
                TextField("chat.input", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .lineLimit(1 ... 6)
                    .focused($inputFocused)
                Button("chat.send", systemImage: "arrow.up.circle.fill") {
                    send()
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isStreaming)
            }
            .padding(.horizontal, GlassSpacing.md)
            .padding(.vertical, GlassSpacing.sm)
            .background(
                Color.glassSurface,
                in: RoundedRectangle(cornerRadius: GlassSpacing.lg, style: .continuous)
            )

            HStack {
                Button("chat.preview", systemImage: "eye") {
                    showPreview = true
                }
                .font(.caption)
                Spacer()
                if chat.lastError != nil {
                    Text(chat.lastError!)
                        .font(.caption2)
                        .foregroundStyle(Color.glassDanger)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, GlassSpacing.sm)
        }
        .padding(.horizontal, GlassSpacing.md)
        .padding(.bottom, GlassSpacing.sm)
        .sheet(isPresented: $showPreview) {
            previewSheet
        }
    }

    private var previewSheet: some View {
        NavigationStack {
            ScrollView {
                Text("chat.previewIntro")
                    .font(.subheadline)
                    .foregroundStyle(Color.glassSecondaryText)
                Text(chat.systemPrompt())
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .navigationTitle(Text("chat.preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.close") { showPreview = false }
                }
            }
        }
    }

    private func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        guard let config = providers.activeProviderConfig else { return }
        draft = ""
        Task {
            _ = await chat.send(prompt, provider: config)
        }
    }
}

/// One message bubble in the transcript.
private struct TurnBubble: View {
    let turn: ChatTurn

    var body: some View {
        HStack(alignment: .bottom) {
            if turn.role == .user {
                Spacer(minLength: 48)
            }
            VStack(alignment: turn.role == .user ? .trailing : .leading, spacing: 2) {
                Text(turn.role == .user ? "chat.you" : "chat.assistant")
                    .font(.caption2)
                    .foregroundStyle(Color.glassSecondaryText)
                bubble
            }
            .frame(maxWidth: .infinity, alignment: turn.role == .user ? .trailing : .leading)
            if turn.role == .assistant {
                Spacer(minLength: 48)
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        switch turn.body {
        case let .text(text):
            Text(markdown(text))
                .textSelection(.enabled)
                .font(.body)
                .padding(GlassSpacing.md)
                .background(
                    turn.role == .user ? Color.glassAccent.opacity(0.18) : Color.glassSurface,
                    in: RoundedRectangle(cornerRadius: GlassSpacing.lg, style: .continuous)
                )
        case let .toolCall(json):
            VStack(alignment: .leading, spacing: 4) {
                Label("chat.tool", systemImage: "hammer")
                    .font(.caption)
                    .foregroundStyle(Color.glassSecondaryText)
                Text(json)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding(GlassSpacing.md)
            .background(
                Color.glassSurface,
                in: RoundedRectangle(cornerRadius: GlassSpacing.lg, style: .continuous)
            )
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}
