import ComposableArchitecture
import SwiftUI

/// The module's entry point. The app target only has to render this — the store and every
/// feature behind it stay internal to `AppModules`.
public struct AppView: View {
    @State private var store = Store(initialState: TransmissionGallery.State()) {
        TransmissionGallery()
    }

    public init() {}

    public var body: some View {
        TransmissionGalleryView(store: store)
    }
}
