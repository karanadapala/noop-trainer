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
    /// Hides the Back button while scrolled more than `threshold` points down from where the view first
    /// appeared. Attach to the first view in the scrolling column.
    func fadesNavigationBarOnScroll(threshold: CGFloat = 24) -> some View {
        modifier(NavigationBarScrollFade(threshold: threshold))
    }
}

private struct NavigationBarScrollFade: ViewModifier {
    let threshold: CGFloat
    @State private var restY: CGFloat?
    @State private var scrolled = false

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { y in
                // The first reading is the top of the screen; a pull-down bounce only goes above it.
                let rest = restY ?? y
                if restY == nil { restY = y }
                scrolled = y < rest - threshold
            }
            .background(NavigationBarFade(hidden: scrolled).frame(width: 0, height: 0))
    }
}
