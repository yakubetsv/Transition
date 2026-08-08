import ComposableArchitecture
import SwiftUI

@Reducer
struct SwatchDetail {

    @ObservableState
    struct State {
        var style: MatchedGeometryStyle
        var swatch: Swatch
    }

    enum Action {
        case closeButtonTapped
    }

    @Dependency(\.dismiss) var dismiss

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .closeButtonTapped:
                return .run { _ in await dismiss(animation: .default) }
            }
        }
    }
}

struct SwatchDetailView: View {
    let store: StoreOf<SwatchDetail>

    var body: some View {
        ZStack(alignment: .topTrailing) {
            store.swatch.color
                .ignoresSafeArea()

            Button {
                store.send(.closeButtonTapped)
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .padding(12)
                    .background(.ultraThinMaterial, in: .circle)
            }
            .padding(20)

            VStack(alignment: .leading, spacing: 8) {
                Spacer()

                Text(store.swatch.name)
                    .font(.largeTitle.weight(.bold))

                Text(store.style.name)
                    .font(.headline)
                    .monospaced()
                    .opacity(0.8)

                Text("Dragging anywhere shrinks this back into the tile it came from, and the interactive dismissal writes `nil` back into `destination`.")
                    .opacity(0.8)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
    }
}

struct SwatchTile: View {
    var swatch: Swatch

    var body: some View {
        VStack(alignment: .leading) {
            Spacer(minLength: 0)

            Text(swatch.name)
                .font(.headline)
                .foregroundStyle(.white)
        }
        .frame(width: 120, height: 120, alignment: .leading)
        .padding(12)
        .background(swatch.color, in: .rect(cornerRadius: Swatch.cornerRadius, style: .continuous))
    }
}

struct Swatch: Equatable, Identifiable {
    var id: String { name }
    var color: Color
    var name: String

    static let cornerRadius: CGFloat = 20

    static let all: [Swatch] = [
        Swatch(color: .indigo, name: "Indigo"),
        Swatch(color: .teal, name: "Teal"),
        Swatch(color: .orange, name: "Orange"),
        Swatch(color: .pink, name: "Pink"),
    ]
}
