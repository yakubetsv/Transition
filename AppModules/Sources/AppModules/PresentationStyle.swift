import SwiftUI
import Transmission

/// Every presentation style `Transmission` ships with, except the two matched-geometry ones —
/// those animate out of a source view, so they live on the swatch tiles instead.
enum PresentationStyle: String, CaseIterable, Identifiable {
    case card
    case crossDissolve
    case currentContext
    case `default`
    case fullscreen
    case popover
    case sheet
    case slide
    case toast
    case zoom

    var id: Self { self }

    var name: String { ".\(rawValue)" }

    var summary: String {
        switch self {
        case .card: "Inset and content-sized, flick it away"
        case .crossDissolve: "Fades in over the presenting screen"
        case .currentContext: "Covers only the presenting controller"
        case .default: "Transmission's interactive take on a sheet"
        case .fullscreen: "Full-screen cover, presenter is removed"
        case .popover: "Anchored, with an arrow back to the row"
        case .sheet: "UISheetPresentationController, .ideal detent"
        case .slide: "Slides in from an edge, scaling the presenter"
        case .toast: "Content-sized banner at the top edge"
        case .zoom: "Morphs out of the row it was opened from"
        }
    }

    var systemImage: String {
        switch self {
        case .card: "rectangle.portrait.center.inset.filled"
        case .crossDissolve: "circle.lefthalf.filled"
        case .currentContext: "rectangle.inset.filled"
        case .default: "rectangle.bottomhalf.filled"
        case .fullscreen: "rectangle.fill"
        case .popover: "bubble.left.fill"
        case .sheet: "rectangle.portrait.bottomhalf.filled"
        case .slide: "arrow.up.to.line"
        case .toast: "bell.badge.fill"
        case .zoom: "arrow.up.left.and.arrow.down.right"
        }
    }

    var transition: PresentationLinkTransition {
        switch self {
        case .card:
            .card(
                preferredEdgeInset: 12,
                preferredCornerRadius: .rounded(cornerRadius: 28),
                preferredAspectRatio: nil
            )
        case .crossDissolve: .crossDissolve
        case .currentContext: .currentContext
        case .default: .default
        case .fullscreen: .fullscreen
        case .popover: .popover
        case .sheet: .sheet(detents: [.ideal, .medium, .large], prefersGrabberVisible: true)
        case .slide: .slide
        case .toast: .toast(edge: .top)
        case .zoom: .zoomIfAvailable
        }
    }

    /// The styles that cover the screen read better with the content centred; the compact ones
    /// size themselves to it.
    var prefersFullBleed: Bool {
        switch self {
        case .card, .popover, .sheet, .toast: false
        case .crossDissolve, .currentContext, .default, .fullscreen, .slide, .zoom: true
        }
    }

    /// A popover has no width to fill, so it needs one.
    var contentWidth: CGFloat? {
        self == .popover ? 280 : nil
    }
}

/// The two hero styles, split out because they need the tapped tile as their source view.
enum MatchedGeometryStyle: String, CaseIterable, Identifiable {
    case matchedGeometry
    case matchedGeometryZoom

    var id: Self { self }

    var name: String { ".\(rawValue)" }

    var summary: String {
        switch self {
        case .matchedGeometry: "Tile grows into the detail, drag to send it back"
        case .matchedGeometryZoom: "Same, preset to scale and zoom the presenter"
        }
    }

    var transition: PresentationLinkTransition {
        switch self {
        case .matchedGeometry:
            .matchedGeometry(
                preferredFromCornerRadius: .rounded(cornerRadius: Swatch.cornerRadius),
                prefersScaleEffect: true,
                prefersZoomEffect: true,
                initialOpacity: 0
            )
        case .matchedGeometryZoom:
            .matchedGeometryZoom(
                preferredFromCornerRadius: .rounded(cornerRadius: Swatch.cornerRadius)
            )
        }
    }
}
