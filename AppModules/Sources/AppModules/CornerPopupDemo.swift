import ComposableArchitecture
import SwiftUI

@Reducer
struct CornerPopupDemo {

    @ObservableState
    struct State {}

    enum Action {
        case delegate(Delegate)
        case dismissButtonTapped
        case itemTapped(PopupItem)

        @CasePathable
        enum Delegate {
            case selected(PopupItem)
        }
    }

    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .delegate:
                return .none

            case .dismissButtonTapped:
                return .run { _ in await dismiss(animation: .default) }

            case .itemTapped(let item):
                // The parent swaps `destination` when this lands. `animation:` on `send` is what
                // wraps that mutation in a transaction — without it the replacement presentation
                // would appear with no transition.
                return .run { send in
                    await send(.delegate(.selected(item)), animation: .default)
                }
            }
        }
    }
}

struct CornerPopupDemoView: View {
    let store: StoreOf<CornerPopupDemo>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(PopupItem.allCases) { item in
                Button {
                    store.send(.itemTapped(item))
                } label: {
                    Label(item.title, systemImage: item.systemImage)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 52)
            }

            Button {
                store.send(.dismissButtonTapped)
            } label: {
                Label("Close", systemImage: "xmark")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .frame(width: 220)
        .background(Color(.secondarySystemBackground))
    }
}

/// Each item swaps the presentation for a different one, which is what exercises
/// `Transmission` tearing down one presentation controller and standing up another.
enum PopupItem: String, CaseIterable, Identifiable, Sendable {
    case attach
    case compose
    case photo

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .attach: "paperclip"
        case .compose: "square.and.pencil"
        case .photo: "photo"
        }
    }

    var title: String {
        switch self {
        case .attach: "Attach → .toast"
        case .compose: "Compose → .sheet"
        case .photo: "Photo → corner popup"
        }
    }
}
