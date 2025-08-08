import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    var text: String?
    // "user" | "assistant" | "system"
    var role: String
    // スレッド関連
    var thread: ChatThread?

    init(timestamp: Date, text: String? = nil, role: String = "user", thread: ChatThread? = nil) {
        self.timestamp = timestamp
        self.text = text
        self.role = role
        self.thread = thread
    }
}
