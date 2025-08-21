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
    // 画像データ（base64エンコード）
    var imageData: String?
    var isImageGeneration: Bool = false

    init(timestamp: Date, text: String? = nil, role: String = "user", thread: ChatThread? = nil, imageData: String? = nil, isImageGeneration: Bool = false) {
        self.timestamp = timestamp
        self.text = text
        self.role = role
        self.thread = thread
        self.imageData = imageData
        self.isImageGeneration = isImageGeneration
    }
}
