import ComposableArchitecture
import SwiftUI
import Transmission
import UIKit

extension PresentationLinkTransition {
    /// A sheet — real detents, grabber and rubber-banding — with an arbitrary SwiftUI view
    /// filling the space *above* it, in the presentation's container view.
    static func canopySheet(
        fractions: [CGFloat] = [],
        isInteractive: Bool = true
    ) -> PresentationLinkTransition {
        .custom(
            options: .init(isInteractive: isInteractive),
            CanopySheetTransition(fractions: fractions)
        )
    }
}

extension UISheetPresentationController.Detent.Identifier {
    /// Derived from the value so every fraction gets its own identifier, which UIKit requires.
    static func fraction(_ fraction: CGFloat) -> Self {
        Self("fraction-\(fraction)")
    }
}

extension UISheetPresentationController.Detent {
    /// A detent at a fraction of the tallest height available to the sheet.
    ///
    /// The resolver's value is a height *within the sheet's safe area*, so this is a fraction of
    /// the usable space rather than of the screen.
    static func fraction(
        _ fraction: CGFloat,
        identifier: UISheetPresentationController.Detent.Identifier
    ) -> UISheetPresentationController.Detent {
        .custom(identifier: identifier) { context in
            context.maximumDetentValue * fraction
        }
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

    /// Detents are a plain property, so they can change while the sheet is on screen — see
    /// `updateUIPresentationController`.
    var fractions: [CGFloat] = []

    @MainActor
    private var detents: [UISheetPresentationController.Detent] {
        fractions.map { .fraction($0, identifier: .fraction($0)) } + [.medium(), .large()]
    }

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
        presentationController.detents = detents
        presentationController.selectedDetentIdentifier = .medium
        presentationController.prefersGrabberVisible = true
        // Naming the *largest* detent as undimmed switches the system dimming view off at every
        // detent, leaving the canopy as the only thing between the sheet and the screen behind.
        //
        // > Note: this is also what makes the sheet non-modal. Touches reach the content behind
        // > it, and tap-outside-to-dismiss goes away because that gesture lives on the dimming
        // > view that no longer exists.
        presentationController.largestUndimmedDetentIdentifier = .large
        return presentationController
    }

    /// `detents` is a settable property, so the set can change while the sheet is up. Wrapping it
    /// in `animateChanges` is what makes the sheet travel to its new resting place instead of
    /// jumping there.
    ///
    /// > Note: `invalidateDetents()` is the companion call, needed only when a custom detent's
    /// > resolver closes over something *outside* the context it is handed. These resolvers only
    /// > use `context.maximumDetentValue`, so replacing the array is enough.
    func updateUIPresentationController(
        presentationController: CanopySheetPresentationController,
        context: Context
    ) {
        let identifiers = detents.map(\.identifier)
        guard presentationController.detents.map(\.identifier) != identifiers else { return }

        presentationController.animateChanges {
            let selected = presentationController.selectedDetentIdentifier
            presentationController.detents = detents
            // Re-assert the selection: dropping the detent the sheet is resting on would otherwise
            // send it somewhere UIKit picks.
            if let selected, identifiers.contains(selected) {
                presentationController.selectedDetentIdentifier = selected
            }
        }
    }
}

/// Everything visual is SwiftUI — `SheetCanopy`. This class only hosts it and sizes it to the
/// gap between the top of the screen and the top of the sheet, resizing it every frame as the
/// sheet moves. So the canopy *is* that space: its own `GeometryReader` height is the distance
/// to the sheet's edge, and its bottom edge is the edge. Nothing else has to be passed in except
/// which detent it rests on.
final class CanopySheetPresentationController: UISheetPresentationController {

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
    }

    /// Assigning `rootView` is how a value-type view is updated from UIKit. Guarded, so SwiftUI
    /// is only invalidated when the detent actually flips — which, since it only flips once the
    /// sheet settles, is rare enough that polling it from the display link costs nothing.
    private func syncCanopyState() {
        if canopy.rootView.detent != selectedDetentIdentifier {
            canopy.rootView.detent = selectedDetentIdentifier
        }
        let identifiers = detents.map(\.identifier)
        if canopy.rootView.detents != identifiers {
            canopy.rootView.detents = identifiers
        }
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

    /// Every detent the sheet currently offers. Changes while the sheet is up, so it doubles as
    /// the readout for detents added at runtime.
    var detents: [UISheetPresentationController.Detent.Identifier] = []

    var body: some View {
        GeometryReader { proxy in
            // Sits on the bottom edge, which is the sheet's top edge, so it rides the sheet.
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 32, weight: .thin))
                .foregroundStyle(.white.opacity(0.9))
                .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
                .position(x: proxy.size.width / 2, y: proxy.size.height - 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(alignment: .top) {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("custom canopy")
                            .font(.footnote.weight(.semibold))

                        Text("\(Int(proxy.size.height))pt · \(detent?.rawValue ?? "–")")
                            .font(.caption)
                            .monospaced()

                        Text("\(detents.count) detents: \(detents.map(\.rawValue).joined(separator: ", "))")
                            .font(.system(size: 9))
                            .monospaced()
                            .multilineTextAlignment(.trailing)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(.white.opacity(0.9))
                }
        }
    }
}

@Reducer
struct CanopySheetDemo {

    @ObservableState
    struct State {
        /// Pushed down by whoever presents the sheet: the detent set is theirs, this is just the
        /// fact the button needs to render.
        var canAddDetent = true
        var message = ""
    }

    enum Action: BindableAction {
        case addDetentButtonTapped
        case binding(BindingAction<State>)
        case delegate(Delegate)
        case dismissButtonTapped

        @CasePathable
        enum Delegate {
            /// The detent set belongs to whoever presents the sheet, not to its contents, so this
            /// asks rather than does.
            case addDetentRequested
        }
    }

    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .addDetentButtonTapped:
                return .run { send in
                    await send(.delegate(.addDetentRequested), animation: .default)
                }

            case .binding, .delegate:
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

                Button("Add a 0.2 detent") {
                    store.send(.addDetentButtonTapped)
                }
                .buttonStyle(.bordered)
                .disabled(!store.canAddDetent)
                .frame(maxWidth: .infinity)

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
