import SwiftUI
import UIKit

/// Attaches the selection marquee to the underlying `UIScrollView` instead of
/// a SwiftUI `DragGesture` on every tile.
///
/// A child `DragGesture` competes with the scroll view's pan recognizer and
/// blocks vertical dragging while selection mode is on. A pan recognizer that
/// only begins on horizontal movement, and that recognizes simultaneously
/// with the scroll view, leaves vertical scrolling untouched. It also gives
/// the marquee an edge auto-scroll, which the web gets from its pointer band.
struct TimelineMarqueeBridge: UIViewRepresentable {
    /// Only installed while the grid is in selection mode.
    var isActive: Bool
    /// The finger went down and moved horizontally: capture the base set.
    var begin: (CGPoint) -> Void
    /// A new finger position, including every auto-scroll tick.
    var update: (CGPoint) -> Void
    /// The gesture ended, was cancelled, or selection mode was left.
    var end: () -> Void
    /// The enclosing scroll view, so the filter dropdown can stop momentum
    /// when it opens over a scrolling grid.
    var onScrollView: (UIScrollView?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> BridgeView {
        let view = BridgeView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: BridgeView, context: Context) {
        context.coordinator.parent = self
        view.coordinator = context.coordinator
        context.coordinator.attach(from: view)
        context.coordinator.syncActive()
    }

    static func dismantleUIView(_ view: BridgeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class BridgeView: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.coordinator?.attach(from: self)
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: TimelineMarqueeBridge

        private weak var scrollView: UIScrollView?
        private var pan: UIPanGestureRecognizer?
        private var link: CADisplayLink?
        private var attachRetries = 0
        private var isPanning = false
        private var lastPoint: CGPoint = .zero

        /// How far inside the viewport the finger must be before the grid
        /// starts scrolling on its own while selecting.
        private let autoScrollEdge: CGFloat = 84
        /// The speed at the very edge, in points per frame (~720 pt/s).
        private let autoScrollMax: CGFloat = 12

        init(_ parent: TimelineMarqueeBridge) {
            self.parent = parent
        }

        // MARK: - Attaching

        func attach(from view: UIView) {
            guard view.window != nil else { return }
            guard let scrollView = view.enclosingScrollView else {
                guard attachRetries < 30 else { return }
                attachRetries += 1
                DispatchQueue.main.async { [weak self, weak view] in
                    guard let self, let view else { return }
                    self.attach(from: view)
                }
                return
            }
            if self.scrollView === scrollView {
                attachRetries = 0
                return
            }

            detach()
            self.scrollView = scrollView
            let pan = UIPanGestureRecognizer(
                target: self,
                action: #selector(handlePan(_:))
            )
            pan.delegate = self
            pan.maximumNumberOfTouches = 1
            pan.cancelsTouchesInView = false
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            scrollView.addGestureRecognizer(pan)
            self.pan = pan

            DispatchQueue.main.async { [weak self] in
                self?.parent.onScrollView(scrollView)
            }
            syncActive()
        }

        func detach() {
            stopAutoScroll()
            scrollView?.isScrollEnabled = true
            if isPanning {
                isPanning = false
                DispatchQueue.main.async { [weak self] in
                    self?.parent.end()
                }
            }
            if let pan {
                scrollView?.removeGestureRecognizer(pan)
            }
            pan = nil
            if let scrollView {
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onScrollView(nil)
                }
            }
            scrollView = nil
            attachRetries = 0
        }

        func syncActive() {
            pan?.isEnabled = parent.isActive
            if !parent.isActive {
                // Called from `updateUIView`; never write SwiftUI state in the
                // middle of that pass.
                DispatchQueue.main.async { [weak self] in
                    self?.finishIfNeeded()
                }
            }
        }

        // MARK: - Gesture

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === pan,
                  parent.isActive,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let scrollView
            else { return false }
            // Only a horizontal start belongs to the marquee. A vertical
            // start falls through to the scroll view, which is the whole
            // point of installing the recognizer here. The translation check
            // catches a slow deliberate drag, the velocity check a flick.
            let translation = pan.translation(in: scrollView)
            let velocity = pan.velocity(in: scrollView)
            let horizontal = abs(translation.x) > abs(translation.y) * 1.5
            let flick = abs(velocity.x) > 70
                && abs(velocity.x) > abs(velocity.y) * 1.2
            return horizontal || flick
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
            // Window coordinates match SwiftUI's `.global` tile frames.
            let point = pan.location(in: nil)

            switch pan.state {
            case .began:
                lastPoint = point
                isPanning = true
                // The marquee owns the gesture now: the scroll view must not
                // drift vertically under a mostly horizontal drag.
                scrollView?.isScrollEnabled = false
                parent.begin(point)
                updateAutoScroll()
            case .changed:
                lastPoint = point
                parent.update(point)
                updateAutoScroll()
            case .ended, .cancelled, .failed:
                lastPoint = point
                finishIfNeeded()
            default:
                break
            }
        }

        private func finishIfNeeded() {
            guard isPanning else { return }
            isPanning = false
            stopAutoScroll()
            scrollView?.isScrollEnabled = true
            parent.end()
        }

        // MARK: - Auto-scroll

        /// The part of the scroll view that the person can actually see: it
        /// shrinks by the top header and the bottom dock, which SwiftUI
        /// reports as content insets. Without them the edge band would sit
        /// under the header, out of reach of a finger selecting a photo.
        private func visibleFrame(of scrollView: UIScrollView) -> CGRect {
            let visible = scrollView.bounds.inset(by: scrollView.adjustedContentInset)
            return scrollView.convert(visible, to: nil)
        }

        private func updateAutoScroll() {
            guard isPanning, let scrollView else {
                stopAutoScroll()
                return
            }
            let frame = visibleFrame(of: scrollView)
            let top = frame.minY + autoScrollEdge
            let bottom = frame.maxY - autoScrollEdge
            if lastPoint.y < top || lastPoint.y > bottom {
                startAutoScroll()
            } else {
                stopAutoScroll()
            }
        }

        private func startAutoScroll() {
            guard link == nil else { return }
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        private func stopAutoScroll() {
            link?.invalidate()
            link = nil
        }

        @objc private func tick() {
            guard isPanning, let scrollView else {
                stopAutoScroll()
                return
            }
            let frame = visibleFrame(of: scrollView)
            let top = frame.minY + autoScrollEdge
            let bottom = frame.maxY - autoScrollEdge

            var step: CGFloat = 0
            if lastPoint.y < top {
                let progress = min(1, (top - lastPoint.y) / autoScrollEdge)
                step = -(3 + autoScrollMax * progress)
            } else if lastPoint.y > bottom {
                let progress = min(1, (lastPoint.y - bottom) / autoScrollEdge)
                step = 3 + autoScrollMax * progress
            } else {
                stopAutoScroll()
                return
            }

            let minOffset = -scrollView.adjustedContentInset.top
            let maxOffset = max(
                minOffset,
                scrollView.contentSize.height
                    + scrollView.adjustedContentInset.bottom
                    - scrollView.bounds.height
            )
            let next = min(maxOffset, max(minOffset, scrollView.contentOffset.y + step))
            guard abs(next - scrollView.contentOffset.y) > 0.01 else { return }
            scrollView.setContentOffset(
                CGPoint(x: scrollView.contentOffset.x, y: next),
                animated: false
            )
            // The finger has not moved, but the content under it has, so the
            // hit rectangle has to be applied again on every frame.
            parent.update(lastPoint)
        }
    }
}

private extension UIView {
    /// The nearest `UIScrollView` in the responder chain, which is what
    /// SwiftUI's `ScrollView` is backed by.
    var enclosingScrollView: UIScrollView? {
        var view = superview
        while let current = view {
            if let scrollView = current as? UIScrollView {
                return scrollView
            }
            view = current.superview
        }
        return nil
    }
}
