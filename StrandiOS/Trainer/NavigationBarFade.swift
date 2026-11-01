import SwiftUI
import UIKit

/// Fades the navigation bar (and its Back button) out while the screen is scrolled down, and back in at
/// the top. Only the bar's alpha changes: the layout doesn't move, swipe-from-the-edge still goes back,
/// and taps pass through the invisible bar to the content. The bar is restored when the screen leaves.
struct NavigationBarFade: UIViewControllerRepresentable {
    let hidden: Bool

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.hidden = hidden
    }

    final class Controller: UIViewController {
        var hidden = false {
            didSet { if hidden != oldValue { apply(animated: true) } }
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply(animated: false)
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            navigationController?.navigationBar.alpha = 1
        }

        private func apply(animated: Bool) {
            guard let bar = navigationController?.navigationBar, view.window != nil else { return }
            let alpha: CGFloat = hidden ? 0 : 1
            if animated {
                UIView.animate(withDuration: 0.2) { bar.alpha = alpha }
            } else {
                bar.alpha = alpha
            }
        }
    }
}

extension View {
    /// Hides the Back button once the screen scrolls more than `threshold` points, measured from the
    /// scroll view's own offset (iOS 18+; on iOS 17 the bar simply stays). Attach to a `ScreenScaffold`.
    func fadesNavigationBarOnScroll(threshold: CGFloat = 6) -> some View {
        modifier(NavigationBarScrollFade(threshold: threshold))
    }
}

private struct NavigationBarScrollFade: ViewModifier {
    let threshold: CGFloat
    @State private var scrolled = false

    func body(content: Content) -> some View {
        content
            .environment(\.screenScrollOffset, ScreenScrollOffset { offset in
                let now = offset > threshold
                if now != scrolled { scrolled = now }
            })
            .background(NavigationBarFade(hidden: scrolled).frame(width: 0, height: 0))
    }
}

/// How far a `ScreenScaffold` has scrolled from its top (content offset plus the top inset), for a screen
/// that wants to react to it. Nil by default, so other screens don't track scrolling at all.
struct ScreenScrollOffset {
    let changed: (CGFloat) -> Void
}

private struct ScreenScrollOffsetKey: EnvironmentKey {
    static let defaultValue: ScreenScrollOffset? = nil
}

extension EnvironmentValues {
    var screenScrollOffset: ScreenScrollOffset? {
        get { self[ScreenScrollOffsetKey.self] }
        set { self[ScreenScrollOffsetKey.self] = newValue }
    }
}

/// Applied by `ScreenScaffold` to its scroll view.
struct ReportsScreenScrollOffset: ViewModifier {
    let report: ScreenScrollOffset?

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *), let report {
            content.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                report.changed(offset)
            }
        } else {
            content
        }
    }
}
