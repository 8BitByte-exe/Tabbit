import SwiftUI
import UIKit

extension AppearanceSetting {
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: return .unspecified
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Applies the Light / Dark / System setting to the app's window.
///
/// Switching with SwiftUI's `preferredColorScheme` inside an animation made every
/// shadow and gradient on all three tabs animate its color at once, which stuttered.
/// Instead the window cross-fades from a snapshot of the old look to the new one,
/// which the system does in a single, smooth step. Sheets and the camera live in
/// the same window, so they follow along.
struct AppearanceApplier: UIViewRepresentable {
    let setting: AppearanceSetting

    func makeUIView(context: Context) -> AppearanceHostView {
        let view = AppearanceHostView()
        view.setting = setting
        return view
    }

    func updateUIView(_ uiView: AppearanceHostView, context: Context) {
        uiView.setting = setting
    }
}

/// An invisible view that knows its window.
final class AppearanceHostView: UIView {
    var setting: AppearanceSetting = .system {
        didSet {
            if oldValue != setting {
                apply(animated: true)
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        isUserInteractionEnabled = false
        isHidden = true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        apply(animated: false)
    }

    private func apply(animated: Bool) {
        guard let window = window else {
            return
        }
        let style = setting.interfaceStyle
        guard window.overrideUserInterfaceStyle != style else {
            return
        }
        guard animated else {
            window.overrideUserInterfaceStyle = style
            return
        }
        // After SwiftUI has finished the current update, outside any SwiftUI animation.
        DispatchQueue.main.async {
            UIView.transition(with: window, duration: 0.35,
                              options: [.transitionCrossDissolve, .allowUserInteraction, .beginFromCurrentState],
                              animations: {
                                  window.overrideUserInterfaceStyle = style
                              }, completion: nil)
        }
    }
}
