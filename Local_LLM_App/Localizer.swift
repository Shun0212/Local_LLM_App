import Foundation

enum AppLanguage: String, CaseIterable {
    case ja
    case en

    var displayName: String {
        switch self {
        case .ja: return "日本語"
        case .en: return "English"
        }
    }
}

final class Localizer {
    static let shared = Localizer()
    private(set) var language: AppLanguage = .ja
    private var bundle: Bundle = .main

    func set(language: AppLanguage) {
        self.language = language
        if let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
           let b = Bundle(path: path) {
            self.bundle = b
        } else {
            self.bundle = .main
        }
    }

    func t(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    func t(_ key: String, _ args: CVarArg...) -> String {
        let fmt = t(key)
        return String(format: fmt, arguments: args)
    }

    func localizedNewChatTitlesBoth() -> [String] {
        var titles: [String] = []
        if let path = Bundle.main.path(forResource: "ja", ofType: "lproj"), let b = Bundle(path: path) {
            titles.append(b.localizedString(forKey: "new_chat", value: nil, table: nil))
        }
        if let path = Bundle.main.path(forResource: "en", ofType: "lproj"), let b = Bundle(path: path) {
            titles.append(b.localizedString(forKey: "new_chat", value: nil, table: nil))
        }
        return titles
    }
}

enum L10n {
    static func t(_ key: String) -> String { Localizer.shared.t(key) }
    static func t(_ key: String, _ args: CVarArg...) -> String { Localizer.shared.t(key, args) }
}

