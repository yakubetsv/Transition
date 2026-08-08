import ComposableArchitecture
import SwiftUI
import Transmission
import UIKit

extension PresentationLinkTransition {
    /// A sheet — real detents, grabber and rubber-banding — with an arbitrary SwiftUI view
    /// filling the space *above* it, in the presentation's container view.
    static func canopySheet(
        recedesPresentingView: Bool = false,
        isInteractive: Bool = true
    ) -> PresentationLinkTransition {
        .custom(
            options: .init(isInteractive: isInteractive),
            CanopySheetTransition(recedesPresentingView: recedesPresentingView)
        )
    }
}

/// The sheet is a `UISheetPresentationController` subclass, the same class the library's `.sheet`
/// is built on, so the sheet UI is the system one. No animators are vended, so UIKit drives the
/// normal sheet transition; the only addition is the canopy.
///
/// > Important: do *not* subclass `Transmission.SheetPresentationController` to do this. Its
/// > private API forwarding uses `class_getSuperclass(Self.self)`, so from a subclass the lookup
/// > resolves back to that same implementation and recurses until the stack overflows
/// > (`SheetPresentationController.swift:531`, `_shouldDismissByDragging`).
struct CanopySheetTransition: PresentationLinkTransitionRepresentable {

    /// Before iOS 26, a sheet scales the screen behind it back into a rounded, inset card. There
    /// is no system switch for it, so `false` undoes it frame by frame. A no-op from iOS 26 on,
    /// where the effect no longer exists.
    var recedesPresentingView = false

    func makeUIPresentationController(
        presented: UIViewController,
        presenting: UIViewController?,
        source: UIViewController,
        context: Context
    ) -> CanopySheetPresentationController {
        let presentationController = CanopySheetPresentationController(
            presentedViewController: presented,
            presenting: presenting
        )
        presentationController.detents = [.medium(), .large()]
        presentationController.selectedDetentIdentifier = .medium
        presentationController.prefersGrabberVisible = true
        // Naming the *largest* detent as undimmed switches the system dimming view off at every
        // detent, leaving the canopy as the only thing between the sheet and the screen behind.
        //
        // > Note: this is also what makes the sheet non-modal. Touches reach the content behind
        // > it, and tap-outside-to-dismiss goes away because that gesture lives on the dimming
        // > view that no longer exists.
        presentationController.largestUndimmedDetentIdentifier = .large
        presentationController.recedesPresentingView = recedesPresentingView
        return presentationController
    }

    func updateUIPresentationController(
        presentationController: CanopySheetPresentationController,
        context: Context
    ) {}
}

/// Everything visual is SwiftUI — `SheetCanopy`. This class only hosts it and sizes it to the
/// gap between the top of the screen and the top of the sheet, resizing it every frame as the
/// sheet moves. So the canopy *is* that space: its own `GeometryReader` height is the distance
/// to the sheet's edge, and its bottom edge is the edge. Nothing else has to be passed in except
/// which detent it rests on.
final class CanopySheetPresentationController: UISheetPresentationController {

    /// See `CanopySheetTransition.recedesPresentingView`.
    var recedesPresentingView = false

    private var displayLink: CADisplayLink?

    private lazy var canopy: UIHostingController<SheetCanopy> = {
        let controller = UIHostingController(rootView: SheetCanopy())
        controller.view.backgroundColor = .clear
        // Decorative only — taps must still reach whatever is behind.
        controller.view.isUserInteractionEnabled = false
        // The view is exactly the space above the sheet, so nothing should spill past it.
        controller.view.clipsToBounds = true
        return controller
    }()

    /// The gap between the top of the container and the top of the sheet.
    private var canopyFrame: CGRect {
        guard let containerView else { return .zero }
        return CGRect(
            x: containerView.bounds.minX,
            y: containerView.bounds.minY,
            width: containerView.bounds.width,
            height: max(sheetTop - containerView.bounds.minY, 0)
        )
    }

    override func presentationTransitionWillBegin() {
        super.presentationTransitionWillBegin()

        guard let containerView else { return }

        canopy.view.frame = canopyFrame
        canopy.view.alpha = 0

        // Not parented to a view controller on purpose: `containerView` belongs to the
        // presentation, not to the presenting controller, so `addChild` there trips UIKit's
        // `UIViewControllerHierarchyInconsistency` check. Inserted directly below the sheet, so it
        // sits above the stock dimming view.
        if let presentedView {
            containerView.insertSubview(canopy.view, belowSubview: presentedView)
        } else {
            containerView.addSubview(canopy.view)
        }

        startTrackingSheet()

        // Registered before the transition runs so the fade happens alongside it rather than
        // snapping on at the end.
        presentedViewController.transitionCoordinator?.animate { _ in
            self.canopy.view.alpha = 1
        }
    }

    override func dismissalTransitionWillBegin() {
        super.dismissalTransitionWillBegin()
        presentedViewController.transitionCoordinator?.animate { _ in
            self.canopy.view.alpha = 0
        }
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        super.dismissalTransitionDidEnd(completed)
        guard completed else { return }
        stopTrackingSheet()
        canopy.view.removeFromSuperview()
    }

    override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()
        resizeCanopy()
        syncCanopyState()
    }

    /// The canopy's height once the sheet is resting on the medium detent — the point the artwork
    /// stops at. Read from the *model* layer, which already holds the destination while the sheet
    /// animates, so a layout pass mid-animation cannot record a half-way value.
    private var settledCanopyHeight: CGFloat {
        guard let presentedView, let containerView else { return 0 }
        let top = containerView.layer.convert(presentedView.layer.bounds, from: presentedView.layer).minY
        return max(top - containerView.bounds.minY, 0)
    }

    /// The sheet moves without a layout pass on the container while it is being dragged, so
    /// following the edge means reading the presentation layer every frame.
    ///
    /// This is also the only accurate source for the *visible* top edge. Measured on iPhone 17
    /// Pro at the medium detent: this returns 415pt, which is where the white card actually
    /// starts, while `frameOfPresentedViewInContainerView` reports 404pt — the sheet is inset
    /// inside its nominal frame, so that value sits 11pt too high.
    private var sheetTop: CGFloat {
        guard let presentedView, let containerView
        else { return frameOfPresentedViewInContainerView.minY }
        // Through the layers rather than the views: only the presentation layer knows where the
        // sheet is mid-animation.
        let layer = presentedView.layer.presentation() ?? presentedView.layer
        return containerView.layer.convert(layer.bounds, from: layer).minY
    }

    private func startTrackingSheet() {
        let displayLink = CADisplayLink(target: self, selector: #selector(followSheet))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    private func stopTrackingSheet() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc
    private func followSheet() {
        resizeCanopy()
        // Polled rather than taken from `UISheetPresentationControllerDelegate`: the adapter owns
        // that delegate, and the write is guarded, so this only reaches SwiftUI when the detent
        // actually flips.
        syncCanopyState()
        holdPresentingViewStill()
    }

    /// Assigning `rootView` is how a value-type view is updated from UIKit. Guarded, so SwiftUI
    /// is only invalidated when one of these actually changes — not on every frame.
    private func syncCanopyState() {
        if canopy.rootView.detent != selectedDetentIdentifier {
            canopy.rootView.detent = selectedDetentIdentifier
        }
        // Re-measured rather than captured once, so a rotation cannot leave a stale value behind.
        if selectedDetentIdentifier == .medium, canopy.rootView.mediumHeight != settledCanopyHeight {
            canopy.rootView.mediumHeight = settledCanopyHeight
        }
    }

    /// UIKit does not transform the presenting controller's own view — it wraps it in a
    /// `UIDropShadowView` and transforms that. Measured on iOS 18.6 at the large detent: scale
    /// 0.9204, ty 27.2, corner radius 10. Undoing it on that wrapper each frame is the only way
    /// out; there is no property for it. On iOS 26 the wrapper is already identity, so the guard
    /// makes this free.
    private func holdPresentingViewStill() {
        guard !recedesPresentingView,
              let wrapper = presentingViewController.view.superview,
              wrapper.transform != .identity || wrapper.layer.cornerRadius != 0
        else { return }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wrapper.transform = .identity
        wrapper.layer.cornerRadius = 0
        CATransaction.commit()
    }

    /// Resizing the host is the whole mechanism: SwiftUI re-lays out into the new height, so the
    /// canopy always ends exactly at the sheet's edge. Nothing is written into the model per
    /// frame, which is what kept this out of a re-entrant layout loop.
    private func resizeCanopy() {
        let frame = canopyFrame
        guard frame != canopy.view.frame else { return }
        // The sheet is mid-animation; an implicit layer animation here would lag a frame behind.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canopy.view.frame = frame
        CATransaction.commit()
    }
}

/// The canopy — plain SwiftUI, and it *is* the space above the sheet: the view's own height is
/// the distance to the sheet's top edge, and its bottom edge is that edge. So "follow the sheet"
/// is just `.bottom` alignment, and no live geometry has to be threaded in.
struct SheetCanopy: View {
    /// The one thing the canopy cannot work out from its own geometry — the discrete state beside
    /// its own height. The system identifier rather than a local enum, so custom detents come
    /// through unchanged.
    var detent: UISheetPresentationController.Detent.Identifier?

    /// The canopy's height with the sheet resting on medium. The freeze needs a place to freeze
    /// at, and that is the one number the canopy cannot measure for itself — the detent only says
    /// *whether* the sheet is expanded, never *how far* medium was.
    var mediumHeight: CGFloat?

    /// How far past the medium detent the sheet has travelled, 0...1. Continuous, so it tracks
    /// the drag itself rather than waiting for the sheet to settle.
    private func expansion(in height: CGFloat) -> Double {
        guard let mediumHeight, mediumHeight > 0 else { return 0 }
        return min(max((mediumHeight - height) / mediumHeight, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let expansion = expansion(in: proxy.size.height)
            // Rides the bottom edge — the sheet's edge — until the canopy is shorter than it was
            // at medium. `max` is the freeze: past that point the anchor stops moving.
            let y = max(proxy.size.height, mediumHeight ?? proxy.size.height) - 24

            Image(systemName: "mountain.2.fill")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                .opacity(1 - expansion)
                .position(x: proxy.size.width / 2, y: y)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("custom canopy")
                            .font(.footnote.weight(.semibold))

                        Text("\(Int(proxy.size.height))pt · \(detent?.rawValue ?? "–") · art \(Int((1 - expansion) * 100))%")
                            .font(.caption)
                            .monospaced()

                        Spacer()
                    }
                    .foregroundStyle(.white.opacity(0.9))
                }
//            ZStack(alignment: .bottom) {
//                LinearGradient(
//                    colors: [
//                        .black.opacity(0.2 + 0.35 * expansion),
//                        .indigo.opacity(0.3 + 0.45 * expansion),
//                    ],
//                    startPoint: .top,
//                    endPoint: .bottom
//                )
//
//                // Sits on the bottom edge, which is the sheet's edge — no coordinates needed.
//                Circle()
//                    .fill(.indigo)
//                    .frame(width: proxy.size.width * 1.4, height: proxy.size.width * 1.4)
//                    .blur(radius: 70)
//                    .opacity(0.55)
//                    .offset(y: proxy.size.width * 0.7)
//
//                Image(systemName: "mountain.2.fill")
//                    .font(.system(size: 16, weight: .thin))
//                    .foregroundStyle(.white.opacity(0.9))
//                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
////                    .opacity(1 - expansion)
////                    .position(x: proxy.size.width / 2, y: artworkY(in: height))
//
//                VStack(spacing: 6) {
//                    Text("custom canopy")
//                        .font(.footnote.weight(.semibold))
//
//                    Text("\(Int(height))pt to the sheet · art \(Int((1 - expansion) * 100))%")
//                        .font(.caption)
//                        .monospaced()
//                }
//                .foregroundStyle(.white.opacity(0.9))
//                .padding(.top, 70)
//                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
//            }
        }
//        .ignoresSafeArea()
    }
}

@Reducer
struct CanopySheetDemo {

    @ObservableState
    struct State {
        var message = ""
    }

    enum Action: BindableAction {
        case binding(BindingAction<State>)
        case dismissButtonTapped
    }

    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .binding:
                return .none

            case .dismissButtonTapped:
                return .run { _ in await dismiss(animation: .default) }
            }
        }
    }
}

struct CanopySheetDemoView: View {
    @Bindable var store: StoreOf<CanopySheetDemo>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Backdrop behind the sheet")
                    .font(.title2.weight(.semibold))

                Text("The space above this sheet is one SwiftUI view in the presentation's container, resized every frame so its bottom edge is the sheet's top edge. Drag it up: the artwork rides that edge until the medium detent, then holds position and fades out instead.")
                    .foregroundStyle(.secondary)

                TextField("Type something", text: $store.message)
                    .textFieldStyle(.roundedBorder)

                Button("Dismiss") {
                    store.send(.dismissButtonTapped)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                // Enough rows to scroll. At the medium detent the sheet expands to `.large`
                // first and only then the content scrolls — that hand-off is
                // `prefersScrollingExpandsWhenScrolledToEdge`, on by default.
                LazyVStack(spacing: 0) {
                    ForEach(1...24, id: \.self) { index in
                        HStack(spacing: 12) {
                            Text("\(index)")
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)

                            Text("Scrollable row")

                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)

                        Divider()
                    }
                }
            }
            .padding(24)
        }
    }
}
