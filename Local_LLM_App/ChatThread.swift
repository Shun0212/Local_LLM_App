import Foundation
import SwiftData

@Model
final class ChatThread {
    var id: UUID
    var title: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Item.thread) var messages: [Item]

    /// 最初のクエリ（メッセージ）でタイトルを初期化する
    init(firstQuery: String, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.title = firstQuery
        self.createdAt = createdAt
        self.messages = []
    }

    /// タイトルを直接指定して初期化（スレッド名を明示したい場合用）
    init(title: String, id: UUID = UUID(), createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.messages = []
    }
}

// Hashable を付与して NavigationLink(value:) で使えるように
extension ChatThread: Hashable {
    static func == (lhs: ChatThread, rhs: ChatThread) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// Sheet(item:) / List(id:) などで使うため
extension ChatThread: Identifiable {}
