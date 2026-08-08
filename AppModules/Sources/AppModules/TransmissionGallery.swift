import ComposableArchitecture
import SwiftUI
import Transmission

/// A gallery of every presentation `Transmission` ships with, each one driven by TCA state
/// rather than by view-local `@State`.
///
/// `Transmission`'s `presentation`/`destination` modifiers take a `Binding<T?>`, which is
/// exactly the shape `$store.scope(state:action:)` produces — so tree-based TCA navigation
/// composes with them without any adapter.
@Reducer
struct TransmissionGallery {

    @Reducer
    enum Destination {
        case anchoredPopup(CornerPopupDemo)
        case canopySheet(CanopySheetDemo)
        case cornerPopup(CornerPopupDemo)
        case presentation(PresentationDemo)
        case push(PushedDetail)
        case swatch(SwatchDetail)
    }

    @ObservableState
    struct State { 
        /// Detents configure the presentation, so they live with whoever presents it. Starts as
        /// the system pair; the sheet can ask for more at runtime.
        var canopyFractions: [CGFloat] = []
        @Presents var destination: Destination.State?
        var swatches: IdentifiedArrayOf<Swatch> = IdentifiedArray(uniqueElements: Swatch.all)
    }

    enum Action {
        case attachButtonTapped
        case canopySheetButtonTapped
        case cornerPopupButtonTapped
        case destination(PresentationAction<Destination.Action>)
        case presentationButtonTapped(PresentationStyle)
        case pushButtonTapped
        case swatchTapped(id: Swatch.ID, style: MatchedGeometryStyle)
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .attachButtonTapped:
                state.destination = .anchoredPopup(CornerPopupDemo.State())
                return .none

            case .canopySheetButtonTapped:
                state.destination = .canopySheet(
                    CanopySheetDemo.State(canAddDetent: !state.canopyFractions.contains(0.2))
                )
                return .none

            case .cornerPopupButtonTapped:
                state.destination = .cornerPopup(CornerPopupDemo.State())
                return .none

            // Swapping `destination` while something is already presented is the interesting
            // path: Transmission has to dismiss one presentation controller and stand up
            // another, in one state mutation.
            case .destination(.presented(.canopySheet(.delegate(.addDetentRequested)))):
                guard !state.canopyFractions.contains(0.2) else { return .none }
                state.canopyFractions.append(0.2)
                // Case paths are read-only here — `enum.case = value` is not writable, so the
                // child's state is taken out, changed and put back.
                if case .canopySheet(var demo)? = state.destination {
                    demo.canAddDetent = false
                    state.destination = .canopySheet(demo)
                }
                return .none

            case .destination(.presented(.anchoredPopup(.delegate(.selected(let item))))),
                 .destination(.presented(.cornerPopup(.delegate(.selected(let item))))):
                switch item {
                case .attach:
                    state.destination = .presentation(PresentationDemo.State(style: .toast))
                case .compose:
                    state.destination = .presentation(PresentationDemo.State(style: .sheet))
                case .photo:
                    state.destination = .cornerPopup(CornerPopupDemo.State())
                }
                return .none

            case .destination:
                return .none

            case .presentationButtonTapped(let style):
                state.destination = .presentation(PresentationDemo.State(style: style))
                return .none

            case .pushButtonTapped:
                state.destination = .push(PushedDetail.State())
                return .none

            case .swatchTapped(let id, let style):
                guard let swatch = state.swatches[id: id]
                else { return .none }
                state.destination = .swatch(SwatchDetail.State(style: style, swatch: swatch))
                return .none
            }
        }
        .ifLet(\.$destination, action: \.destination)
    }
}

/// Deliberately a `ScrollView` and not a `List`: inside a `List` row, SwiftUI commits the row's
/// update in a transaction that does not carry the animation down to `Transmission`'s adapter,
/// so the presentation controller's dimming snaps in at the end instead of fading alongside the
/// transition. This is also the structure the library's own example app uses.
struct TransmissionGalleryView: View {
    @Bindable var store: StoreOf<TransmissionGallery>

    var body: some View {
        NavigationStack {
            ScrollView {
                // A plain `VStack`, not `LazyVStack`: a lazy row that has not scrolled into view
                // yet does not exist, so its `presentation` modifier is not observing anything —
                // `destination` could say "presented" with nothing on screen.
                VStack(alignment: .leading, spacing: 28) {
                    GallerySection(
                        title: "Custom transition",
                        footer: "`CornerPopupTransition` in this module: its own `UIPresentationController` for layout and dimming, plus an animator that collapses onto an anchor. The first row anchors to a screen corner; the paperclip anchors to itself via `context.sourceView`."
                    ) {
                        Button {
                            store.send(.cornerPopupButtonTapped, animation: .default)
                        } label: {
                            ExampleRow(
                                title: ".cornerPopup",
                                subtitle: "Content-sized, grows out of the corner",
                                systemImage: "arrow.up.left.and.arrow.down.right.circle"
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(16)
                        .background(.background, in: .rect(cornerRadius: 14, style: .continuous))
                        .presentation(
                            $store.scope(state: \.destination?.cornerPopup, action: \.destination.cornerPopup),
                            transition: .cornerPopup(anchor: .corner(.bottomTrailing))
                        ) { $popupStore in
                            CornerPopupDemoView(store: popupStore)
                        }

                        Button {
                            store.send(.canopySheetButtonTapped, animation: .default)
                        } label: {
                            ExampleRow(
                                title: ".canopySheet",
                                subtitle: "Package's sheet, SwiftUI canopy above it",
                                systemImage: "square.3.layers.3d.top.filled"
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(16)
                        .background(.background, in: .rect(cornerRadius: 14, style: .continuous))
                        .presentation(
                            $store.scope(state: \.destination?.canopySheet, action: \.destination.canopySheet),
                            transition: .canopySheet(fractions: store.canopyFractions)
                        ) { $sheetStore in
                            CanopySheetDemoView(store: sheetStore)
                        }

                        composer
                    }

                    GallerySection(
                        title: "PresentationLink",
                        footer: "`state.destination = .presentation(…)` is what presents them — the style is state, so all ten share one reducer."
                    ) {
                        ForEach(PresentationStyle.allCases) { style in
                            Button {
                                store.send(.presentationButtonTapped(style), animation: .default)
                            } label: {
                                ExampleRow(
                                    title: style.name,
                                    subtitle: style.summary,
                                    systemImage: style.systemImage
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(16)
                            .background(.background, in: .rect(cornerRadius: 14, style: .continuous))
                            // Per row, not on the container: the source-view-anchored styles
                            // (`.popover`, `.zoom`) animate from the view the modifier sits on.
                            .presentation(presentedDemo(style), transition: style.transition) { $demoStore in
                                PresentationDemoView(store: demoStore)
                            }
                        }
                    }

                    GallerySection(
                        title: "PresentationLink · matched geometry",
                        footer: "These two animate out of the tapped tile, so the shared `destination` binding is narrowed down to a single row."
                    ) {
                        ForEach(MatchedGeometryStyle.allCases) { style in
                            swatchStrip(style: style)
                        }
                    }

                    GallerySection(
                        title: "DestinationLink",
                        footer: "A push is a different protocol — it hands an animator to the UINavigationController behind this stack — but the same optional state drives it."
                    ) {
                        Button {
                            store.send(.pushButtonTapped, animation: .default)
                        } label: {
                            ExampleRow(
                                title: ".slide",
                                subtitle: "Custom push animator, pan-to-pop intact",
                                systemImage: "arrow.right.to.line"
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(16)
                        .background(.background, in: .rect(cornerRadius: 14, style: .continuous))
                    }
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Transmission")
            .destination(
                $store.scope(state: \.destination?.push, action: \.destination.push),
                transition: .slide(initialOpacity: 0)
            ) { $pushStore in
                PushedDetailView(store: pushStore)
            }
        }
    }

    /// The same popup, but anchored to the paperclip instead of a screen corner. The modifier
    /// sits on the button, so `Transmission` hands that button over as `context.sourceView` and
    /// the menu grows out of it.
    private var composer: some View {
        HStack(spacing: 12) {
            Text("Message")
                .foregroundStyle(.tertiary)

            Spacer(minLength: 0)

            Button {
                store.send(.attachButtonTapped, animation: .default)
            } label: {
                Image(systemName: "paperclip")
                    .font(.title3)
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemFill), in: .circle)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .presentation(
                $store.scope(state: \.destination?.anchoredPopup, action: \.destination.anchoredPopup),
                transition: .cornerPopup(anchor: .sourceView)
            ) { $popupStore in
                CornerPopupDemoView(store: popupStore)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.background, in: .rect(cornerRadius: 14, style: .continuous))
    }

    private func swatchStrip(style: MatchedGeometryStyle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(style.name)
                    .font(.subheadline.weight(.semibold))
                    .monospaced()

                Text(style.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(store.swatches) { swatch in
                        Button {
                            store.send(.swatchTapped(id: swatch.id, style: style), animation: .default)
                        } label: {
                            SwatchTile(swatch: swatch)
                        }
                        .buttonStyle(.plain)
                        .presentation(
                            presentedSwatch(id: swatch.id, style: style),
                            transition: style.transition
                        ) { $swatchStore in
                            SwatchDetailView(store: swatchStore)
                        }
                    }
                }
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.leading)
            .scrollClipDisabled()
        }
    }

    /// Narrows the shared `destination` binding down to one style, so only the tapped row
    /// presents. Writing `nil` back still goes through `destination`, which is what lets the
    /// child's `@Dependency(\.dismiss)` and the interactive drag drive the dismissal.
    private func presentedDemo(_ style: PresentationStyle) -> Binding<StoreOf<PresentationDemo>?> {
        let destination = $store.scope(state: \.destination?.presentation, action: \.destination.presentation)
        return Binding(
            get: { destination.wrappedValue?.style == style ? destination.wrappedValue : nil },
            set: { if $0 == nil { destination.wrappedValue = nil } }
        )
    }

    private func presentedSwatch(id: Swatch.ID, style: MatchedGeometryStyle) -> Binding<StoreOf<SwatchDetail>?> {
        let destination = $store.scope(state: \.destination?.swatch, action: \.destination.swatch)
        return Binding(
            get: {
                guard let store = destination.wrappedValue,
                      store.swatch.id == id,
                      store.style == style
                else { return nil }
                return store
            },
            set: { if $0 == nil { destination.wrappedValue = nil } }
        )
    }
}

struct GallerySection<Content: View>: View {
    var title: String
    var footer: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            content

            Text(.init(footer))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// The label shared by the row-style examples.
struct ExampleRow: View {
    var title: String
    var subtitle: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .monospaced()
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.primary)
        .contentShape(.rect)
    }
}

#Preview {
    TransmissionGalleryView(
        store: Store(initialState: TransmissionGallery.State()) {
            TransmissionGallery()
        }
    )
}
