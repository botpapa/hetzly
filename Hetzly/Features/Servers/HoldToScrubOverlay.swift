import SwiftUI
import UIKit

/// A transparent UIKit overlay whose `UILongPressGestureRecognizer` powers
/// chart scrubbing without ever blocking the enclosing ScrollView.
///
/// Why UIKit: every SwiftUI gesture arrangement tried on the chart overlay
/// (`.gesture`, sequenced long-press → drag, `.simultaneousGesture`, drag
/// with `minimumDistance: 0`) claims touches that begin on the chart, which
/// makes the page unscrollable from a chart-origin swipe —
/// `ChartScrollUITests` reproduces this. `UILongPressGestureRecognizer` has
/// exactly the semantics scrubbing needs:
///
/// - A finger that moves before `minimumPressDuration` elapses fails the
///   recognizer, so flicks pan the ScrollView like anywhere else.
/// - Once the hold is recognized, `cancelsTouchesInView` cancels the scroll
///   view's touch tracking, so the subsequent drag scrubs without fighting
///   the scroll — and the recognizer keeps reporting locations through
///   `.changed` for the whole drag.
struct HoldToScrubOverlay: UIViewRepresentable {
    var onChange: (CGPoint) -> Void
    var onEnd: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:))
        )
        recognizer.minimumPressDuration = 0.25
        recognizer.allowableMovement = 12
        recognizer.cancelsTouchesInView = true
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onChange = onChange
        context.coordinator.onEnd = onEnd
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange, onEnd: onEnd)
    }

    final class Coordinator: NSObject {
        var onChange: (CGPoint) -> Void
        var onEnd: () -> Void

        init(onChange: @escaping (CGPoint) -> Void, onEnd: @escaping () -> Void) {
            self.onChange = onChange
            self.onEnd = onEnd
        }

        @objc func handle(_ recognizer: UILongPressGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                onChange(recognizer.location(in: recognizer.view))
            default:
                onEnd()
            }
        }
    }
}
