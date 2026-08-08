import SwiftUI
import Transmission
import UIKit

extension PresentationLinkTransition {
    /// A content-sized popup that grows out of an anchor — either a corner of the screen or the
    /// view the modifier is attached to.
    ///
    /// Nothing built in does this: `.popover` anchors an arrow to a source view and `.toast`
    /// spans the full width at an edge.
    static func cornerPopup(
        anchor: CornerPopupTransition.Anchor = .corner(.bottomTrailing),
        inset: CGFloat = 16,
        cornerRadius: CGFloat = 24,
        isInteractive: Bool = true
    ) -> PresentationLinkTransition {
        .custom(
            options: .init(isInteractive: isInteractive),
            CornerPopupTransition(anchor: anchor, inset: inset, cornerRadius: cornerRadius)
        )
    }
}

/// A custom transition is a value that vends the three UIKit pieces of a presentation:
/// the presentation controller (layout and chrome), and an animator for each direction.
struct CornerPopupTransition: PresentationLinkTransitionRepresentable {

    enum Corner: Equatable, Sendable {
        case bottomLeading
        case bottomTrailing
        case topLeading
        case topTrailing

        /// The edge a drag has to travel toward to dismiss.
        var dismissEdge: Edge {
            switch self {
            case .bottomLeading, .bottomTrailing: .bottom
            case .topLeading, .topTrailing: .top
            }
        }
    }

    enum Anchor: Equatable, Sendable {
        /// Pinned to a corner of the safe area.
        case corner(Corner)
        /// Pinned to the view the modifier is attached to, which `Transmission` hands over as
        /// `context.sourceView`. This is the same mechanism `.popover` and `.zoom` use.
        case sourceView
    }

    var anchor: Anchor
    var inset: CGFloat
    var cornerRadius: CGFloat

    func makeUIPresentationController(
        presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController,
        context: Context
    ) -> CornerPopupPresentationController {
        CornerPopupPresentationController(
            anchor: anchor,
            presentedViewController: presented,
            presenting: presenting
        )
    }

    func updateUIPresentationController(
        presentationController: CornerPopupPresentationController,
        context: Context
    ) {
        presentationController.anchor = anchor
        presentationController.cornerRadius = cornerRadius
        presentationController.inset = inset
        presentationController.sourceView = context.sourceView
    }

    /// Makes the hosting controller report its SwiftUI content size as `preferredContentSize`,
    /// which is what lets the popup size itself to its content.
    func updateHostingController<Content: View>(
        presenting: PresentationHostingController<Content>,
        context: Context
    ) {
        presenting.tracksContentSize = true
    }

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        presentationController: UIPresentationController,
        context: Context
    ) -> CornerPopupTransitionAnimator? {
        let transition = CornerPopupTransitionAnimator(
            anchor: anchor,
            sourceView: context.sourceView,
            isPresenting: true,
            animation: context.transaction.animation
        )
        transition.wantsInteractiveStart = false
        return transition
    }

    func animationController(
        forDismissed dismissed: UIViewController,
        presentationController: UIPresentationController,
        context: Context
    ) -> CornerPopupTransitionAnimator? {
        let transition = CornerPopupTransitionAnimator(
            anchor: anchor,
            sourceView: context.sourceView,
            isPresenting: false,
            animation: context.transaction.animation
        )
        // Handing the presentation controller the transition is what wires the pan gesture to
        // the animator's progress — without it the drag would not scrub the animation.
        if let presentationController = presentationController as? PercentDrivenInteractivePresentationController {
            presentationController.attach(to: transition)
        } else {
            transition.wantsInteractiveStart = false
        }
        return transition
    }
}

/// Owns where the popup sits and what chrome surrounds it. `InteractivePresentationController`
/// contributes the dimming view and the drag-to-dismiss gesture.
final class CornerPopupPresentationController: InteractivePresentationController {

    /// The gap between the popup and its source view.
    private static let sourceSpacing: CGFloat = 8

    var anchor: CornerPopupTransition.Anchor {
        didSet {
            guard anchor != oldValue else { return }
            edges = Edge.Set(anchor.dismissEdge)
            containerView?.setNeedsLayout()
        }
    }

    var cornerRadius: CGFloat = 24 {
        didSet {
            guard cornerRadius != oldValue else { return }
            applyCornerRadius()
            containerView?.setNeedsLayout()
        }
    }

    var inset: CGFloat = 16 {
        didSet {
            guard inset != oldValue else { return }
            containerView?.setNeedsLayout()
        }
    }

    weak var sourceView: UIView?

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let containerView else { return .zero }

        let available = containerView.bounds
            .inset(by: containerView.safeAreaInsets)
            .insetBy(dx: inset, dy: inset)

        var size = presentedViewController.preferredContentSize
        if size == .zero {
            size = presentedViewController.view.systemLayoutSizeFitting(
                CGSize(width: available.width, height: UIView.layoutFittingCompressedSize.height),
                withHorizontalFittingPriority: .fittingSizeLevel,
                verticalFittingPriority: .fittingSizeLevel
            )
        }
        size.width = min(max(size.width, 1), available.width)
        size.height = min(max(size.height, 1), available.height)

        var origin: CGPoint
        switch anchor {
        case .corner(let corner):
            origin = available.origin
            switch corner {
            case .bottomLeading:
                origin.y = available.maxY - size.height
            case .bottomTrailing:
                origin.x = available.maxX - size.width
                origin.y = available.maxY - size.height
            case .topLeading:
                break
            case .topTrailing:
                origin.x = available.maxX - size.width
            }

        case .sourceView:
            let source = sourceFrame(in: containerView) ?? available
            // Sits above the source and trailing-aligned with it, like a menu opening from a
            // toolbar button.
            origin = CGPoint(
                x: source.maxX - size.width,
                y: source.minY - Self.sourceSpacing - size.height
            )
            origin.x = min(max(origin.x, available.minX), max(available.maxX - size.width, available.minX))
            origin.y = min(max(origin.y, available.minY), max(available.maxY - size.height, available.minY))
        }
        return CGRect(origin: origin, size: size)
    }

    init(
        anchor: CornerPopupTransition.Anchor,
        presentedViewController: UIViewController,
        presenting presentingViewController: UIViewController?
    ) {
        self.anchor = anchor
        super.init(
            presentedViewController: presentedViewController,
            presenting: presentingViewController
        )
        edges = Edge.Set(anchor.dismissEdge)
        dimmingView.isHidden = false
        presentedViewShadow = .minimal
    }

    /// `layoutPresentedView` is not called while the presentation is in flight —
    /// `shouldAutoLayoutPresentedView` is false for as long as `isBeingPresented` is true — so
    /// the radius has to be applied up front or the popup animates in with square corners.
    override func presentationTransitionWillBegin() {
        super.presentationTransitionWillBegin()
        applyCornerRadius()
    }

    override func layoutPresentedView(frame: CGRect) {
        super.layoutPresentedView(frame: frame)
        applyCornerRadius()
    }

    private func applyCornerRadius() {
        guard let presentedView else { return }
        presentedView.layer.cornerRadius = cornerRadius
        presentedView.layer.cornerCurve = .continuous
        presentedView.layer.masksToBounds = true
    }

    private func sourceFrame(in containerView: UIView) -> CGRect? {
        guard let sourceView, sourceView.window != nil else { return nil }
        return sourceView.convert(sourceView.bounds, to: containerView)
    }
}

extension CornerPopupTransition.Anchor {
    var dismissEdge: Edge {
        switch self {
        case .corner(let corner): corner.dismissEdge
        case .sourceView: .bottom
        }
    }
}

/// Owns the motion. A `UIView` transform scales about the view's centre, so the scale is paired
/// with a translation that lands the shrunken popup on its anchor.
final class CornerPopupTransitionAnimator: PresentationControllerTransition {

    private static let collapsedScale: CGFloat = 0.2

    let anchor: CornerPopupTransition.Anchor
    weak var sourceView: UIView?

    init(
        anchor: CornerPopupTransition.Anchor,
        sourceView: UIView?,
        isPresenting: Bool,
        animation: Animation?
    ) {
        self.anchor = anchor
        self.sourceView = sourceView
        super.init(isPresenting: isPresenting, animation: animation)
    }

    override func configureTransitionAnimator(
        using transitionContext: UIViewControllerContextTransitioning,
        animator: UIViewPropertyAnimator
    ) {
        guard
            let presented = transitionContext.viewController(forKey: isPresenting ? .to : .from),
            let presentedView = transitionContext.view(forKey: isPresenting ? .to : .from) ?? presented.view
        else {
            transitionContext.completeTransition(false)
            return
        }

        let containerView = transitionContext.containerView

        if isPresenting {
            var presentedFrame = transitionContext.finalFrame(for: presented)
            if presentedView.superview == nil {
                containerView.addSubview(presentedView)
            }
            presentedView.frame = presentedFrame
            presentedView.layoutIfNeeded()
            presentedFrame = presentedView.frame

            // Lets a `TransitionReader` in the presented view observe this transition's progress.
            configureTransitionReaderCoordinator(
                presented: presented,
                presentedView: presentedView,
                presentedFrame: &presentedFrame
            )

            presentedView.transform = collapsedTransform(for: presentedFrame, in: containerView)
            presentedView.alpha = 0

            animator.addAnimations {
                presentedView.transform = .identity
                presentedView.alpha = 1
            }
        } else {
            let frame = transitionContext.initialFrame(for: presented)
            presentedView.layoutIfNeeded()

            animator.addAnimations {
                presentedView.transform = self.collapsedTransform(for: frame, in: containerView)
                presentedView.alpha = 0
            }
        }

        animator.addCompletion { animatingPosition in
            switch animatingPosition {
            case .end:
                transitionContext.completeTransition(true)
            default:
                transitionContext.completeTransition(false)
            }
        }
    }

    private func collapsedTransform(for frame: CGRect, in containerView: UIView) -> CGAffineTransform {
        let scale = Self.collapsedScale

        let translation: CGPoint
        switch anchor {
        case .corner(let corner):
            // A centre-anchored scale moves every corner inward by half the size it loses;
            // translating back by that amount leaves the anchored corner where it was.
            let dx = frame.width * (1 - scale) / 2
            let dy = frame.height * (1 - scale) / 2
            translation = switch corner {
            case .bottomLeading: CGPoint(x: -dx, y: dy)
            case .bottomTrailing: CGPoint(x: dx, y: dy)
            case .topLeading: CGPoint(x: -dx, y: -dy)
            case .topTrailing: CGPoint(x: dx, y: -dy)
            }

        case .sourceView:
            // Collapse onto the source view's centre so it reads as growing out of it.
            guard let sourceView, sourceView.window != nil else { return .identity }
            let source = sourceView.convert(sourceView.bounds, to: containerView)
            translation = CGPoint(
                x: source.midX - frame.midX,
                y: source.midY - frame.midY
            )
        }

        return CGAffineTransform(translationX: translation.x, y: translation.y)
            .scaledBy(x: scale, y: scale)
    }
}
