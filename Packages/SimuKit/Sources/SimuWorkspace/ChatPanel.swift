import SwiftUI
import SimuCore

/// The consult conversation, ChatGPT-style: the user speaks in a tinted
/// bubble on the right; SNer answers from the left with an avatar and bare
/// text — no box, the way a live assistant types. Replies arrive through a
/// typewriter reveal (see `WorkspaceStore.chatStreamingText`) with a
/// blinking caret at the tail.
public struct ChatPanel: View {
    @Bindable private var store: WorkspaceStore
    @State private var draftText = ""
    @FocusState private var inputFocused: Bool
    /// macOS sheets carry no close affordance by default; iPhone keeps
    /// swipe-to-dismiss. One explicit button serves both platforms.
    @Environment(\.dismiss) private var dismiss

    public init(store: WorkspaceStore) {
        self._store = Bindable(wrappedValue: store)
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            thread
            inputBar
        }
        .frame(minWidth: 380, minHeight: 480)
        .onAppear { inputFocused = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            ChatAvatar()
            Text("SNer")
                .font(.headline)
                .accessibilityLabel("咨询对话")
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭咨询")
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var thread: some View {
        if store.chatTurns.isEmpty && store.chatStreamingText == nil {
            // Empty state greets the user in the assistant's own voice
            // (user request 2026-10-04): the default copy names the
            // consultant instead of describing the panel.
            ContentUnavailableView {
                Label("Hi，我是 SNer", systemImage: "bubble")
            } description: {
                if store.isChatAssistantConfigured {
                    Text("欢迎来问我 SimuNow 的相关问题，比如怎么用，或者某个数字是什么意思。")
                } else {
                    Text("欢迎来问我 SimuNow 的相关问题。还没有配置 DeepSeek 密钥，暂时不能对话；其余功能不受影响，数字都在对比页和检查器里。")
                }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(store.chatTurns) { turn in
                            ChatBubble(turn: turn)
                                .id(turn.id)
                        }
                        if let streaming = store.chatStreamingText {
                            // The half-typed reply, caret blinking at the tail.
                            AssistantMessage(text: streaming, showsCaret: true)
                                .id("streaming")
                        } else if store.isChatThinking {
                            // Waiting for the first word, not a pretend reply.
                            HStack(spacing: 8) {
                                ChatAvatar()
                                Text("正在思考…")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel("正在生成回答")
                            }
                            .id("thinking")
                        }
                    }
                    .padding()
                }
                .onChange(of: store.chatTurns.count) { _, _ in
                    scrollToLatest(proxy)
                }
                .onChange(of: store.chatStreamingText) { _, _ in
                    scrollToLatest(proxy)
                }
            }
        }
    }

    /// Follow the newest content: the streaming line while typing, the
    /// newest spoken turn once it lands.
    private func scrollToLatest(_ proxy: ScrollViewProxy) {
        if store.chatStreamingText != nil {
            proxy.scrollTo("streaming", anchor: .bottom)
        } else if let last = store.chatTurns.last {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("问一问，比如：全年电费怎么算的？", text: $draftText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($inputFocused)
                .onSubmit(send)
                .disabled(store.isChatThinking || store.chatStreamingText != nil)
                .accessibilityLabel("咨询输入")
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.5))
            .disabled(!canSend)
            .accessibilityLabel("发送咨询")
            if !store.chatTurns.isEmpty {
                Button {
                    store.clearChat()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空对话")
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var canSend: Bool {
        store.chatStreamingText == nil
            && !store.isChatThinking
            && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && store.isChatAssistantConfigured
    }

    private func send() {
        guard canSend else { return }
        let text = draftText
        draftText = ""
        Task {
            await store.sendChat(text)
        }
    }
}

/// SNer's round avatar: accent circle with a hand-drawn mini robot (user
/// request 2026-10-04). No SF Symbol for a robot exists in this OS's
/// symbol set (`robot`/`robot.fill` resolve to nil, leaving an empty
/// circle — verified 2026-10-04), so the mark is composed from plain
/// shapes: antenna, head, two eyes. One drawing so the header, the
/// thinking row and every reply read as the same speaker.
struct ChatAvatar: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
            RobotMark()
        }
        .frame(width: 26, height: 26)
        .accessibilityHidden(true) // the visible speaker name carries meaning
    }
}

/// The mini robot face: antenna ball + stem, rounded-square head, and two
/// accent-coloured eyes on a white head, inside the accent circle.
private struct RobotMark: View {
    var body: some View {
        VStack(spacing: 0.5) {
            Circle()
                .fill(.white)
                .frame(width: 3, height: 3)
            Capsule()
                .fill(.white)
                .frame(width: 1.4, height: 2.5)
            RoundedRectangle(cornerRadius: 4)
                .fill(.white)
                .frame(width: 13, height: 9)
                .overlay(
                    HStack(spacing: 3) {
                        Circle().frame(width: 2.4, height: 2.4)
                        Circle().frame(width: 2.4, height: 2.4)
                    }
                    .foregroundStyle(Color.accentColor)
                )
        }
    }
}

/// SNer's spoken lines: avatar + bare text on the left, no box — the
/// ChatGPT layout. A blinking caret rides the tail while the reply is
/// still typing; under Reduce Motion the caret stays solid instead.
struct AssistantMessage: View {
    let text: String
    var showsCaret = false
    @State private var caretVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ChatAvatar()
            HStack(alignment: .bottom, spacing: 1) {
                Text(text)
                    .textSelection(.enabled)
                if showsCaret {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.primary.opacity(0.8))
                        .frame(width: 2.5, height: 16)
                        .opacity(caretOpacity)
                        .task(id: showsCaret) {
                            // Blink only while the reply is still typing.
                            while showsCaret && !Task.isCancelled && !reduceMotion {
                                caretVisible.toggle()
                                try? await Task.sleep(for: .milliseconds(550))
                            }
                        }
                        .accessibilityHidden(true)
                }
            }
            Spacer(minLength: 24)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SNer 说：\(text)")
    }

    private var caretOpacity: Double {
        if reduceMotion { return 1 }
        return caretVisible ? 1 : 0.15
    }
}

/// One spoken turn. The user gets a tinted bubble on the right; SNer speaks
/// from the left with an avatar and bare text.
struct ChatBubble: View {
    let turn: ChatTurn

    var body: some View {
        if turn.role == .user {
            HStack {
                Spacer(minLength: 48)
                Text(turn.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.accentColor.opacity(0.18))
                    )
                    .accessibilityLabel("我说：\(turn.text)")
            }
        } else {
            AssistantMessage(text: turn.text)
        }
    }
}
