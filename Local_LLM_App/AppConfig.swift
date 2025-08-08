import Foundation
import Combine

final class AppConfig: ObservableObject {
    @Published var serverURL: URL? {
        didSet { persistServerURL() }
    }
    @Published var language: AppLanguage {
        didSet {
            persistLanguage()
            Localizer.shared.set(language: language)
        }
    }

    init() {
        if let s = UserDefaults.standard.string(forKey: "serverURL"), let u = URL(string: s) {
            self.serverURL = u
        } else {
            self.serverURL = nil
        }
        if let code = UserDefaults.standard.string(forKey: "language"), let lang = AppLanguage(rawValue: code) {
            self.language = lang
        } else {
            // 推定: システム優先が日本語ならja、そうでなければen
            let pref = Locale.preferredLanguages.first ?? "en"
            self.language = pref.hasPrefix("ja") ? .ja : .en
        }
        Localizer.shared.set(language: self.language)
    }

    private func persistServerURL() {
        if let url = serverURL?.absoluteString {
            UserDefaults.standard.set(url, forKey: "serverURL")
        } else {
            UserDefaults.standard.removeObject(forKey: "serverURL")
        }
    }

    private func persistLanguage() {
        UserDefaults.standard.set(language.rawValue, forKey: "language")
    }
}

