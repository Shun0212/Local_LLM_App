import UIKit
import Combine

final class KeyboardObserver: ObservableObject {
    @Published var height: CGFloat = 0
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let willChange = NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)
        let willHide = NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)

        willChange
            .merge(with: willHide)
            .sink { [weak self] note in
                guard let self else { return }
                if note.name == UIResponder.keyboardWillHideNotification {
                    self.height = 0
                    return
                }
                guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                    self.height = 0
                    return
                }
                // キーボードとウィンドウの重なり量を安全に計算（安全域を差し引き）
                if let windowScene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene }).first,
                   let window = windowScene.windows.first(where: { $0.isKeyWindow }) {
                    let converted = window.convert(frame, from: nil)
                    let overlap = max(0, window.bounds.maxY - converted.minY)
                    let effective = max(0, overlap - window.safeAreaInsets.bottom)
                    self.height = effective
                } else {
                    // フォールバック（厳密ではない）
                    self.height = max(0, frame.height)
                }
            }
            .store(in: &cancellables)
    }
}


