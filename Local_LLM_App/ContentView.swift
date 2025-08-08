import SwiftUI
import SwiftData
import AVFoundation
import UIKit


private enum ConnectionStatus: Equatable {
    case notConfigured
    case connected(model: String)
    case error
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]
    @State private var messageText: String = ""
    @State private var serverURL: URL? = nil
    @State private var isPresentingScanner: Bool = false
    @State private var isSending: Bool = false
    @State private var cameraDeniedAlert: Bool = false
    @State private var provider: ChatProvider = .ollama
    @State private var streamingText: String? = nil
    @State private var streamingAccumulated: String = ""
    @State private var streamTask: Task<Void, Never>? = nil
    @State private var lastStreamUpdate: Date = .distantPast
    @FocusState private var inputFocused: Bool
    @State private var connectionStatus: ConnectionStatus = .notConfigured
    @EnvironmentObject private var config: AppConfig
    @State private var usagePrompt: Int? = nil
    @State private var usageCompletion: Int? = nil
    @State private var usageTotal: Int? = nil


    private let thread: ChatThread

    init(thread: ChatThread) {
        self.thread = thread
        let threadId: UUID = thread.id
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> { item in
                item.thread?.id == threadId
            },
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        _items = Query(descriptor)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        // ChatGPT風の中央カラム幅（最大約760pt）
                        let available = max(CGFloat(0), geometry.size.width - CGFloat(24))
                        let bubbleWidth = min(available, CGFloat(760))
                        LazyVStack(alignment: .leading, spacing: 16) {
                            // デバッグ用に固定メッセージを追加（アイテムがない場合）
                            if items.isEmpty {
                                HStack {
                                    Text(L10n.t("start_chat_hint"))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                }
                                .padding()
                            }
                            
                            ForEach(items) { item in
                                messageBubble(item, maxBubbleWidth: bubbleWidth)
                                    .id(item.id)
                            }
                            if let streamingText {
                                streamingBubble(text: streamingText, maxBubbleWidth: bubbleWidth)
                                    .id("streaming")
                            }
                        }
                        .padding()
                        .padding(.bottom, 12) // safeAreaInset に任せ、余白のみ確保
                    }
                    .background(
                        LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)], startPoint: .top, endPoint: .bottom)
                    )
                    .scrollDismissesKeyboard(.interactively)
                    .contentShape(Rectangle())
                    .onTapGesture { inputFocused = false }
                    .onChange(of: items.count) { _, _ in
                        // 新しいメッセージが追加されたら最下部にスクロール
                        if let lastItem = items.last {
                            withAnimation(.easeInOut(duration: 0.5)) {
                                proxy.scrollTo(lastItem.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: streamingText) { _, _ in
                        // ストリーミング中も最下部にスクロール
                        if streamingText != nil {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo("streaming", anchor: .bottom)
                            }
                        }
                    }
                }
                
                Spacer()
            }
        }
        // 入力バーは safeAreaInset で下部に固定し、キーボード回避は SwiftUI に任せる
        .safeAreaInset(edge: .bottom) {
            inputBar()
                .background(.ultraThinMaterial)
                .overlay(Divider(), alignment: .top)
        }
        .navigationTitle(thread.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    Text(thread.title).font(.headline)
                    connectionDot()
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // プロバイダはOllama固定
                    Section {
                        Button { openScanner() } label: { Label(L10n.t("menu_server_qr"), systemImage: "qrcode.viewfinder") }
                        if let s = config.serverURL?.absoluteString {
                            ShareLink(item: s) { Label(L10n.t("menu_share_server"), systemImage: "square.and.arrow.up") }
                        }
                        Button { createNewChat() } label: { Label(L10n.t("menu_new_chat"), systemImage: "plus") }
                    }
                    if isSending {
                        Section {
                            Button(role: .destructive) { stopStreaming() } label: { Label(L10n.t("action_stop"), systemImage: "stop.fill") }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").imageScale(.large)
                }
            }
            // キーボード上に閉じるボタンを追加
            ToolbarItemGroup(placement: .keyboard) {
                Button { inputFocused = false } label: { Label(L10n.t("keyboard_close"), systemImage: "keyboard.chevron.compact.down") }
                Spacer()
                Text(L10n.t("send_hint"))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .task {
            // 起動時に既存設定があれば接続状態をサイレントチェック
            if let url = config.serverURL {
                serverURL = url
                await updateConnectionStatus()
            }
        }
        .sheet(isPresented: $isPresentingScanner) {
            QRScannerView { result in
                switch result {
                case .success(let code):
                    if let url = URL(string: code) {
                        adoptServerURL(url)
                    }
                case .failure:
                    break
                }
                isPresentingScanner = false
            }
        }
        .alert(L10n.t("alert_camera_title"), isPresented: $cameraDeniedAlert) {
            Button(L10n.t("ok"), role: .cancel) {}
        } message: {
            Text(L10n.t("alert_camera_message"))
        }
    }

    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let userText = messageText
        // 最初のユーザー or アシスタント発話がまだ無いかを送信前に判定
        let isFirstConversation = !items.contains { $0.role == "user" || $0.role == "assistant" }
        // タイトルが既定の「新しいチャット/ New Chat」のときのみ、最初のユーザー入力でリネーム
        if isFirstConversation && isDefaultThreadTitle(thread.title) {
            let derived = deriveTitle(from: userText)
            if !derived.isEmpty { thread.title = derived }
        }
        withAnimation {
            let newItem = Item(timestamp: Date(), text: userText, role: "user", thread: thread)
            modelContext.insert(newItem)
            messageText = ""
        }
        try? modelContext.save()
        // 軽い触覚フィードバック
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        inputFocused = false
        // 接続先の決定（個別設定が無ければ共有設定を使う）
        let targetURL = serverURL ?? config.serverURL
        guard let serverURL = targetURL else {
            let sys = Item(timestamp: Date(), text: L10n.t("server_not_set"), role: "system")
            modelContext.insert(sys)
            return
        }
        isSending = true
        streamingText = ""
        streamingAccumulated = ""
        streamTask?.cancel()

        // タイトル変更は送信前に実施済み（「新しいチャット」の場合のみ）

        // 履歴をサーバーに送る（user/assistantのみ）。
        // サーバーの "message" に今回のユーザー発話を渡し、"messages" にはそれ以前の履歴だけを渡す。
        // こうすることで重複を避け、モデルが会話を「覚える」確度を高める。
        let convoHistory: [Message] = items.compactMap { it in
            guard let t = it.text else { return nil }
            guard it.role == "user" || it.role == "assistant" else { return nil }
            return Message(role: it.role, content: t)
        }
        // 直近のユーザー発話（今回分）が convoHistory の末尾に含まれている可能性が高いので除外
        var priorHistory = convoHistory
        if let last = priorHistory.last, last.role == "user", last.content == userText {
            priorHistory.removeLast()
        }
        // ベースのシステム指示は毎回先頭に入れる（安定した振る舞いのため）
        let systemPrompt = L10n.t("system_prompt")
        let effectiveHistory: [Message] = [Message(role: "system", content: systemPrompt)] + priorHistory
        streamTask = Task { [serverURL, provider, effectiveHistory] in
            do {
                let service = ChatService(baseURL: serverURL, provider: provider)
                var lastUpdate = Date.distantPast
                var lastLen = 0
                try await service.sendMessageStreaming(userText, history: effectiveHistory, onToken: { chunk in
                    streamingAccumulated += chunk
                    let now = Date()
                    let deltaTime = now.timeIntervalSince(lastUpdate)
                    let deltaLen = streamingAccumulated.count - lastLen
                    if deltaTime >= 0.08 || deltaLen >= 48 {
                        lastUpdate = now
                        lastLen = streamingAccumulated.count
                        Task { @MainActor in
                            streamingText = streamingAccumulated
                        }
                    }
                }, onUsage: { p, c, t in
                    Task { @MainActor in
                        usagePrompt = p
                        usageCompletion = c
                        usageTotal = t
                    }
                })
                await MainActor.run { finalizeStreaming(successText: streamingAccumulated) }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run { finalizeStreaming(successText: streamingAccumulated.isEmpty ? "エラー: \(error.localizedDescription)" : streamingAccumulated) }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(_ item: Item, maxBubbleWidth: CGFloat) -> some View {
        let isAssistant = (item.role == "assistant" || item.role == "system")
        let bgColor = isAssistant ? Color(.secondarySystemBackground) : Color.accentColor
        let timeText = item.timestamp.formatted(date: .omitted, time: .shortened)

        // 本文
        let content: AnyView = {
            if isAssistant {
                return AnyView(
                    markdownText(item.text ?? "")
                        .fixedSize(horizontal: false, vertical: true)
                        .contextMenu { Button { UIPasteboard.general.string = item.text ?? "" } label: { Label("コピー", systemImage: "doc.on.doc") } }
                )
            } else {
                return AnyView(
                    Text(item.text ?? "")
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                        .contextMenu { Button { UIPasteboard.general.string = item.text ?? "" } label: { Label("コピー", systemImage: "doc.on.doc") } }
                        .foregroundColor(.white)
                )
            }
        }()

        let bubble = content
            .padding(12)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                isAssistant ? AnyView(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)) : AnyView(EmptyView())
            )

        let bubbleWithTime = VStack(alignment: isAssistant ? .leading : .trailing, spacing: 4) {
            bubble
            Text(timeText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }

        HStack(alignment: .bottom) {
            if isAssistant {
                bubbleWithTime
                    .frame(maxWidth: maxBubbleWidth, alignment: .leading)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                bubbleWithTime
                    .frame(maxWidth: maxBubbleWidth, alignment: .trailing)
            }
        }
        .padding(.horizontal, 12)
    }


    @ViewBuilder
    private func streamingBubble(text: String, maxBubbleWidth: CGFloat) -> some View {
        let nowText = Date().formatted(date: .omitted, time: .shortened)
        let bg = Color(.secondarySystemBackground)
        let content: AnyView = {
            if text.isEmpty {
                return AnyView(
                    HStack(spacing: 8) {
                        ThinkingDotsView()
                        Text(L10n.t("thinking"))
                    }
                    .font(.body)
                    .foregroundColor(.primary)
                )
            } else {
                return AnyView(
                    markdownText(text + " ▍")
                        .fixedSize(horizontal: false, vertical: true)
                )
            }
        }()

        let bubble = content
            .padding(12)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )

        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                bubble
                Text(nowText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: maxBubbleWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
    }

    private func markdownText(_ text: String) -> some View {
        if let att = try? AttributedString(markdown: text) {
            return Text(att)
                .textSelection(.enabled)
        } else {
            return Text(text)
                .textSelection(.enabled)
        }
    }

    // 旧: maybeUpdateStreaming は使用しない（タスク内で合成してからメインに反映）

    private func finalizeStreaming(successText: String) {
        let text = successText
        if !text.isEmpty {
            let assistantItem = Item(timestamp: Date(), text: text, role: "assistant", thread: thread)
            modelContext.insert(assistantItem)
            try? modelContext.save()
        }
        streamingText = nil
        streamingAccumulated = ""
        isSending = false
        streamTask = nil
    }

    private func stopStreaming() {
        streamTask?.cancel()
        finalizeStreaming(successText: streamingAccumulated)
    }

    // 既定のチャット名かどうか（日本語・英語の両方を許容）
    private func isDefaultThreadTitle(_ title: String) -> Bool {
        let normalized = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaults = Localizer.shared.localizedNewChatTitlesBoth().map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return defaults.contains(normalized)
    }

    // 最初のユーザークエリからチャットタイトルを生成
    private func deriveTitle(from text: String, maxLen: Int = 16) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        // 改行や連続空白を整形
        var singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        while singleLine.contains("  ") { singleLine = singleLine.replacingOccurrences(of: "  ", with: " ") }
        // 先頭に記号が続く場合は除去
        let cleaned = singleLine.trimmingCharacters(in: CharacterSet(charactersIn: "#*•-・:：、。 "))
        if cleaned.count <= maxLen { return cleaned }
        let idx = cleaned.index(cleaned.startIndex, offsetBy: maxLen)
        return String(cleaned[..<idx])
    }

    private struct ThinkingDotsView: View {
        @State private var animate = false
        var body: some View {
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .frame(width: 6, height: 6)
                        .scaleEffect(animate ? 1.0 : 0.6)
                        .opacity(animate ? 1.0 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                            .repeatForever()
                            .delay(Double(i) * 0.15),
                            value: animate
                        )
                }
            }
            .onAppear { animate = true }
        }
    }

    private func openScanner() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isPresentingScanner = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.isPresentingScanner = true }
                    else { self.cameraDeniedAlert = true }
                }
            }
        default:
            cameraDeniedAlert = true
        }
    }

    private func createNewChat() {
        let firstQuery = L10n.t("new_chat")
        let t = ChatThread(firstQuery: firstQuery)
        modelContext.insert(t)
        // ナビゲーションで新チャットに遷移したい場合は、上位でNavigationLinkを使う構成に拡張可能
    }

    // サーバーURLの採用とヘルスチェック
    private func adoptServerURL(_ url: URL) {
        serverURL = url
        config.serverURL = url
        Task {
            do {
                let svc = ChatService(baseURL: url)
                let health = try await svc.checkHealth()
                await MainActor.run {
                    let msg = String(format: L10n.t("connection_ok"), health.model)
                    let sys = Item(timestamp: Date(), text: msg, role: "system")
                    modelContext.insert(sys)
                    connectionStatus = .connected(model: health.model)
                }
            } catch {
                await MainActor.run {
                    let sys = Item(timestamp: Date(), text: String(format: L10n.t("connection_error"), error.localizedDescription), role: "system")
                    modelContext.insert(sys)
                    connectionStatus = .error
                }
            }
        }
    }

    // 入力バー
    @ViewBuilder
    private func inputBar() -> some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField(L10n.t("input_placeholder"), text: $messageText, axis: .vertical)
                .lineLimit(1...7)
                .padding(.vertical, 10)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .strokeBorder(Color(.separator), lineWidth: 0.5)
                )
                .font(.system(size: 16))
                .focused($inputFocused)
                .frame(minHeight: 44)

            if isSending {
                Button(action: stopStreaming) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.red.opacity(0.1)))
                }
                .accessibilityLabel(L10n.t("action_stop"))
            } else {
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .accentColor)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.accentColor.opacity(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.1 : 0.2)))
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(L10n.t("action_send"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.2), value: messageText)
        .animation(.easeInOut(duration: 0.25), value: isSending)
    }

    // タイトル横の接続状態ドット
    @ViewBuilder
    private func connectionDot() -> some View {
        switch connectionStatus {
        case .connected:
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                .accessibilityLabel(L10n.t("status_connected"))
        case .error:
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                .accessibilityLabel(L10n.t("status_error"))
        case .notConfigured:
            Circle()
                .fill(Color.gray.opacity(0.5))
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.white.opacity(0.8), lineWidth: 1))
                .accessibilityLabel(L10n.t("status_not_configured"))
        }
    }

    // サイレントな接続状態チェック
    private func updateConnectionStatus() async {
        guard let url = serverURL ?? config.serverURL else {
            await MainActor.run { connectionStatus = .notConfigured }
            return
        }
        do {
            let svc = ChatService(baseURL: url)
            let health = try await svc.checkHealth()
            await MainActor.run { connectionStatus = .connected(model: health.model) }
        } catch {
            await MainActor.run { connectionStatus = .error }
        }
    }
}

#Preview {
    do {
        let container = try ModelContainer(for: Item.self, ChatThread.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let thread = ChatThread(firstQuery: "プレビュー")
        container.mainContext.insert(thread)
        return ContentView(thread: thread)
            .modelContainer(container)
    } catch {
        return Text("Preview Error: \(error.localizedDescription)")
    }
}
