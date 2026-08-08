import ComposableArchitecture
import SwiftUI

@Reducer
struct PushedDetail {

    @ObservableState
    struct State {}

    enum Action {
        case popButtonTapped
    }

    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .popButtonTapped:
                return .run { _ in await dismiss(animation: .default) }
            }
        }
    }
}

struct PushedDetailView: View {
    let store: StoreOf<PushedDetail>

    var body: some View {
        List {
            Section {
                Text("This screen was pushed by DestinationLink using a slide animator instead of the system push.")
                    .foregroundStyle(.secondary)

                Text("Interactive pan-to-pop still works — `prefersPanGesturePop` defaults to true — and popping that way writes `nil` back through the same binding.")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button("Pop") {
                    store.send(.popButtonTapped)
                }
            }
        }
        .navigationTitle("Slide")
        .navigationBarTitleDisplayMode(.inline)
    }
}
