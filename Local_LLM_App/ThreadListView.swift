import SwiftUI
import SwiftData

struct ThreadListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\ChatThread.createdAt, order: .reverse)]) private var threads: [ChatThread]
    @State private var showingCreate = false
    @State private var renamingThread: ChatThread? = nil
    @State private var renamingTitle: String = ""
    @EnvironmentObject private var config: AppConfig
    @State private var navigateTo: ChatThread? = nil
    @State private var path: [ChatThread] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if threads.isEmpty {
                    emptyState()
                } else {
                    List {
                        Section {
                            quickCreateRow()
                        }
                        ForEach(threads) { thread in
                            NavigationLink(value: thread) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(thread.title).font(.headline)
                                    Text(thread.createdAt, style: .date).font(.caption).foregroundColor(.gray)
                                }
                            }
                            .contextMenu {
                                Button { rename(thread) } label: { Label(L10n.t("rename_title"), systemImage: "pencil") }
                                Button(role: .destructive) { delete(thread) } label: { Label(L10n.t("delete"), systemImage: "trash") }
                            }
                        }
                        .onDelete { indexSet in
                            indexSet.map { threads[$0] }.forEach(delete)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle(L10n.t("nav_chats"))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button { config.serverURL = nil } label: { Label(L10n.t("clear_server"), systemImage: "xmark.circle") }
                        Section(L10n.t("language")) {
                            Button {
                                config.language = .ja
                            } label: { Label("日本語", systemImage: config.language == .ja ? "checkmark" : "globe") }
                            Button {
                                config.language = .en
                            } label: { Label("English", systemImage: config.language == .en ? "checkmark" : "globe") }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            let t = createThread()
                            path.append(t)
                        } label: {
                            Label(L10n.t("menu_new_chat"), systemImage: "plus")
                        }
                        Button {
                            showingCreate = true
                        } label: {
                            Label(L10n.t("menu_new_chat_with_title"), systemImage: "text.cursor")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill").imageScale(.large)
                    }
                    .accessibilityLabel("新規チャットオプション")
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateThreadView { title in
                    let t = ChatThread(title: title)
                    modelContext.insert(t)
                    path.append(t)
                }
            }
            .navigationDestination(for: ChatThread.self) { t in
                ContentView(thread: t)
            }
            .sheet(item: $renamingThread) { t in
                RenameThreadView(initialTitle: t.title) { newTitle in
                    var title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                    if title.isEmpty { title = "新しいチャット" }
                    t.title = title
                    try? modelContext.save()
                }
            }
        }
    }

    private func delete(_ thread: ChatThread) {
        modelContext.delete(thread)
    }

    private func rename(_ thread: ChatThread) {
        renamingThread = thread
        renamingTitle = thread.title
    }
    
    private func createThread(title: String = L10n.t("new_chat")) -> ChatThread {
        let t = ChatThread(title: title)
        modelContext.insert(t)
        return t
    }
    
    @ViewBuilder
    private func quickCreateRow() -> some View {
        Button {
            let t = createThread()
            path.append(t)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 24, weight: .semibold))
                Text(L10n.t("quick_create"))
                    .font(.body)
                    .foregroundColor(.accentColor)
                Spacer()
            }
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private func emptyState() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(L10n.t("empty_state_title"))
                .font(.headline)
            Button {
                let t = createThread()
                path.append(t)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                    Text(L10n.t("menu_new_chat"))
                }
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
            Button {
                showingCreate = true
            } label: {
                Text(L10n.t("menu_new_chat_with_title"))
                    .font(.subheadline)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

private struct CreateThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String = L10n.t("new_chat")
    let onCreate: (String) -> Void
    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.t("field_title"), text: $title)
            }
            .navigationTitle(L10n.t("create_chat_title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("action_create")) {
                        onCreate(title)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("action_cancel")) { dismiss() }
                }
            }
        }
    }
}

private struct RenameThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    let onRename: (String) -> Void

    init(initialTitle: String, onRename: @escaping (String) -> Void) {
        self._title = State(initialValue: initialTitle)
        self.onRename = onRename
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L10n.t("field_title"), text: $title)
            }
            .navigationTitle(L10n.t("rename_title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.t("action_save")) {
                        onRename(title)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.t("action_cancel")) { dismiss() }
                }
            }
        }
    }
}
