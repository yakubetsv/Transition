import ComposableArchitecture
import SwiftUI

/// One destination feature shared by every non-hero presentation style — the style is just
/// state, so all ten transitions are driven by the same reducer.
@Reducer
struct PresentationDemo {

    @ObservableState
    struct State {
        var style: PresentationStyle
    }

    enum Action {
        case dismissButtonTapped
    }

    /// The `animation:` argument matters: `Transmission` only animates when the binding is
    /// written inside a transaction that carries one.
    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .dismissButtonTapped:
                return .run { _ in await dismiss(animation: .default) }
            }
        }
    }
}

struct PresentationDemoView: View {
    let store: StoreOf<PresentationDemo>

    var body: some View {
        if store.style.prefersFullBleed {
            ZStack {
                Color(.systemBackground)
                    .ignoresSafeArea()

                content
            }
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: store.style.systemImage)
                .font(.largeTitle)
                .foregroundStyle(.tint)

            Text(store.style.name)
                .font(.title2.weight(.semibold))
                .monospaced()

            Text(store.style.summary)
                .foregroundStyle(.secondary)

            Button("Dismiss") {
                store.send(.dismissButtonTapped)
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(width: store.style.contentWidth)
    }
}
