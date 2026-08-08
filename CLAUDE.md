# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`Transition` is an iOS-only SwiftUI app built on the Composable Architecture (TCA), currently a gallery of `Transmission` presentation styles. The app target is a shell: it renders `AppModules.AppView` and nothing else. All features live in the `AppModules` local Swift package.

## Layout and how the pieces connect

Three units, wired together by the workspace:

- **`Transition.xcworkspace`** — the entry point. It references `Transition.xcodeproj` *and* the local `AppModules` package as siblings. Always open/build the **workspace**; the `.xcodeproj` alone cannot resolve `AppModules`.
- **`Transition.xcodeproj`** — a single app target (`Transition`, bundle id `yakubets-v.Transition`). Its only job is the `@main` entry point, `Assets.xcassets`, and linking `AppModules`.
- **`AppModules/`** — local SPM package holding the app's code. The `AppModules` library product is linked into the app target via `packageProductDependencies` + the Frameworks build phase in `project.pbxproj`.

Because they are wired through the workspace (not an `XCLocalSwiftPackageReference`), there is **no `Package.resolved` inside the `.xcodeproj`** — SPM resolution is driven by `AppModules/Package.swift`.

### Adding code

- **New files under `Transition/`**: just create them. The app target uses `fileSystemSynchronizedGroups` (Xcode 16+ folder sync), so files on disk are picked up automatically — never hand-edit `project.pbxproj` to register a source file.
- **New feature modules**: add a `.target` (and matching `Sources/<Name>/` directory) in `AppModules/Package.swift`. Prefer adding it as a dependency of the existing `AppModules` target so the app picks it up transitively; a brand-new `.library` product would also need a manual `project.pbxproj` link edit.

## Feature architecture

Tree-based TCA navigation drives every presentation. `TransmissionGallery` owns a single
`@Presents var destination: Destination.State?`, where `Destination` is a `@Reducer enum` of the
three detail features. The view scopes that one optional into each `Transmission` modifier:

```swift
.presentation($store.scope(state: \.destination?.card, action: \.destination.card),
             transition: .card(…)) { $cardStore in CardDetailView(store: cardStore) }
```

This composes because `Transmission`'s `presentation(_:transition:destination:)` and
`destination(_:transition:destination:)` take a `Binding<T?>` — the exact shape
`$store.scope(state:action:)` produces. No adapter is needed.

Source-view-anchored styles (`.popover`, `.zoom`, both matched-geometry ones) animate from the
view their modifier is attached to, so those modifiers go **per row**. The shared `destination`
binding is then narrowed to one row (`presentedDemo(_:)` / `presentedSwatch(id:style:)` in
`TransmissionGallery.swift`).

Children never dismiss themselves directly — they `await dismiss(animation:)`, the parent nils
`destination`, and `Transmission` reacts to the binding.

### Custom transitions

`CornerPopupTransition.swift` is the worked example. A transition is a `Sendable` value conforming
to `PresentationLinkTransitionRepresentable` that vends three things:

| Piece | Base class to subclass | Responsibility |
|---|---|---|
| `makeUIPresentationController` | `InteractivePresentationController` | frame, dimming, shadow, drag-to-dismiss |
| `animationController(forPresented:…)` | `PresentationControllerTransition` | the appear animation |
| `animationController(forDismissed:…)` | same | the disappear animation |

Wrap it with `PresentationLinkTransition.custom(options:_:)` and it is usable anywhere a built-in
transition is. Two details that are easy to miss:

- `presentationController.attach(to: transition)` in the *dismissing* animator is what wires the
  pan gesture to the animator's progress. Without it the drag does not scrub.
- `context.sourceView` is the view the modifier is attached to — the same hook `.popover` and
  `.zoom` use. `CornerPopupTransition.Anchor.sourceView` uses it to grow the popup out of the
  button that opened it.

### Putting SwiftUI behind a presentation

`BackdropSheetTransition.swift` puts a SwiftUI view in the presentation's `containerView`, below
the sheet. The presentation controller only hosts it and feeds it geometry SwiftUI cannot measure
from behind a presentation (container size, the sheet's live top edge, the medium detent); all the
visuals stay in `SheetBackdrop`, an ordinary SwiftUI view.

Three things that bite:

- **`Transmission.SheetPresentationController` cannot be subclassed.** It forwards to private UIKit
  methods via `class_getSuperclass(Self.self)`, so in a subclass the lookup resolves back to that
  same implementation and recurses until the stack overflows — it surfaces as endless
  `_shouldDismissByDragging` calls. Subclass `UISheetPresentationController` directly; that is the
  class the library's `.sheet` is built on anyway, so the sheet UI is identical.
- **The hosting controller must not be `addChild`ed to the presenting controller.** `containerView`
  is not in that controller's view hierarchy, so UIKit raises
  `UIViewControllerHierarchyInconsistency`. Hold it as a property and add only its view.
- **Guard every write into the `@Observable` model.** It notifies on every assignment, equal or
  not, so an unguarded write from inside a layout pass re-invalidates the SwiftUI view, which lays
  out again. With guards, driving it from a `CADisplayLink` at 60 fps is fine.

A sheet moves without laying the container out, so following its edge through a drag means reading
`presentedView.layer.presentation()` each frame — `frameOfPresentedViewInContainerView` only tells
you where it settled, and it is *not* the visible edge either: measured on iPhone 17 Pro at the
medium detent it reports 404pt where the card actually starts at 415pt, because the sheet is inset
inside its nominal frame.

**Detents are discrete, geometry is continuous.** `selectedDetentIdentifier` only flips once the
sheet *settles*, never mid-drag, so it cannot drive anything that has to track a gesture. Split the
two: the canopy's own height carries the continuous position, and the detent drives step changes
(swap content, fade something) with an explicit `.animation(_:value:)` so the step does not read as
a glitch.

**The pre-iOS-26 receding background.** Before iOS 26 a sheet scales the screen behind it into a
rounded inset card, and there is no property to turn it off. It is not applied to the presenting
controller's view — UIKit wraps that view in a `UIDropShadowView` and transforms *that* (measured
on iOS 18.6 at `.large`: scale 0.9204, ty 27.2, corner radius 10). `CanopySheetTransition`'s
`recedesPresentingView: false` undoes it on that wrapper each frame. From iOS 26 the effect is gone
and the wrapper is already identity, so the same code is a no-op — which is why this has to be
checked on an older runtime (`iOS18Test` simulator) rather than the default one.

### Putting a view behind a presentation

`BackdropSheetTransition.swift` inserts SwiftUI into the presentation's `containerView`, below
the presented view, so it sits between the presenting screen and the sheet. Three constraints
found the hard way:

- **Never subclass `Transmission.SheetPresentationController`.** Its private-API forwarding calls
  `class_getSuperclass(Self.self)` (`SheetPresentationController.swift:531`), which in a subclass
  resolves back to that same implementation and recurses until the stack overflows. Subclass plain
  `UISheetPresentationController` instead — that is the class the library's `.sheet` is built on,
  so the sheet UI is identical.
- **Do not `addChild` the hosting controller.** `containerView` belongs to the presentation, not
  to the presenting controller, so parenting there trips `UIViewControllerHierarchyInconsistency`.
  Hold the hosting controller in a property and add only its view.
- **Anything that has to move every frame must be UIKit, not SwiftUI.** Writing the sheet's live
  frame into an `@Observable` from a `CADisplayLink` re-invalidates the SwiftUI backdrop from
  inside the container's own layout pass. `@Observable` also notifies on assignments of *equal*
  values, so guard every write. The glow that follows the sheet is a `CAGradientLayer` whose
  centre is set with implicit animations disabled; the SwiftUI half only updates on layout.
- Read the sheet's in-flight position through `CALayer.convert(_:from:)` on
  `presentedView.layer.presentation()`. The `UIView` conversion returns a zeroed origin here.

## Dependencies

Declared only in `AppModules/Package.swift`:

- [Transmission](https://github.com/nathantannar4/Transmission) (`from: "2.14.4"`) — SwiftUI presentation/transition primitives (`PresentationLink`, `DestinationLink`, custom transitions). Pulls in `nathantannar4/Engine` transitively.
- [swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture) (`from: "1.26.1"`) — state management and navigation.

## Commands

```sh
# Build the app (simulator)
xcodebuild -workspace Transition.xcworkspace -scheme Transition \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipMacroValidation build

# Build just the package (fast feedback while working in AppModules)
xcodebuild -workspace Transition.xcworkspace -scheme AppModules \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -skipMacroValidation build

# Resolve / update dependencies
cd AppModules && swift package resolve
cd AppModules && swift package update
```

Schemes: `Transition` (app) and `AppModules` (package).

`swift build` / `swift test` from the CLI will **not** work — the package declares `.iOS(.v26)` only, so it cannot build for the macOS host. Everything goes through `xcodebuild` with a simulator destination.

There are currently no test targets.

## Gotchas

- **TCA state changes need an explicit animation.** `Transmission`'s modifiers only animate when the binding is written inside a transaction carrying an animation. A bare `store.send(.foo)` mutates state outside any transaction, so the presentation snaps in with no transition. Always use `store.send(.foo, animation: .default)` to present and `await dismiss(animation: .default)` to dismiss. (`PresentationLink`/`DestinationLink` *buttons* wrap their own state change, which is why this only bites the modifier form.)
- **Never put a `Transmission` presentation modifier inside a lazy container.** A `LazyVStack`/`LazyVGrid` row that has not scrolled into view does not exist yet, so its `presentation` modifier is not observing the binding: `destination` can be non-nil with nothing on screen. `TransmissionGalleryView` uses a plain `VStack` for this reason.
- **A custom `UIPresentationController` must apply its chrome before the transition starts.** `layoutPresentedView(frame:)` is not called while the presentation is in flight — `shouldAutoLayoutPresentedView` is false for as long as `isBeingPresented` is true — so anything set only there (corner radius, masks) appears one frame *after* the animation ends. Set it in `presentationTransitionWillBegin()` too; see `CornerPopupPresentationController.applyCornerRadius()`.
- **Never put a `Transmission` presentation modifier inside a `List` row.** Inside a `List`, SwiftUI commits the row's update in a transaction that does not carry the animation down to the adapter, so the presented view slides in but the presentation controller's dimming snaps to full opacity at the *end* of the transition instead of fading alongside it. Measured: background stayed at `(242,242,247)` for the whole transition inside a `List`, versus a smooth `242 → 232 → 213` ramp in a `ScrollView`. This is why `TransmissionGalleryView` is a `ScrollView` + `LazyVStack` — the same structure the library's own example app uses. It has nothing to do with TCA: a plain `@State` binding reproduces it identically.
- **`-skipMacroValidation` is required for CLI builds.** TCA's macro plugins must be trust-approved; without the flag `xcodebuild` fails with "Macro … must be enabled before it can be used". In Xcode.app you get a one-time "Trust & Enable" prompt instead.
- **Two different Swift language modes.** `AppModules` is `swiftLanguageModes: [.v6]` (strict concurrency enforced), while the app target still has `SWIFT_VERSION = 5.0`. Code that compiles in the app target may fail when moved into the package.
- **Deployment target is iOS 17.0** in both the app target (`IPHONEOS_DEPLOYMENT_TARGET`) and the package (`.iOS(.v17)`); universal iPhone + iPad (`TARGETED_DEVICE_FAMILY = "1,2"`). Keep the two in step when changing it. iOS 17 is the floor because the code leans on `@Observable`/`@Bindable` and the iOS 17 shape and scroll shorthands (`.rect(cornerRadius:)`, `.defaultScrollAnchor`, `.scrollClipDisabled`).
- **`.zoom` is iOS 18+.** Use `PresentationLinkTransition.zoomIfAvailable`, which degrades to the default transition below that, rather than `@available`-fencing call sites.
