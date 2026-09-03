import SwiftUI

/// Shown when nothing is being navigated: pick somewhere to walk to.
struct DestinationPickerView: View {
    @EnvironmentObject private var model: GuidanceModel

    var body: some View {
        List {
            if model.status == .routing {
                Label("경로 계산 중", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let failure = model.failureMessage {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if model.destinations.isEmpty {
                emptyState
            } else {
                ForEach(model.destinations) { destination in
                    Button {
                        model.beginNavigation(to: destination)
                    } label: {
                        row(for: destination)
                    }
                }
            }
        }
        .navigationTitle("어디로 갈까요")
        .onAppear { model.sync.requestSync() }
    }

    private func row(for destination: Destination) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(destination.name)
                .font(.body)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(destination.source.displayName)
                if let distance = straightLineDistance(to: destination) {
                    Text("·")
                    Text(DistanceFormatter.string(fromMetres: distance))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("저장된 목적지가 없습니다")
                .font(.caption)
            Text("아이폰 네이버지도에서 장소를 열고 공유 → WalkArrow를 누르면 여기에 나타납니다.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if !model.isPhoneReachable {
                Label("아이폰 연결 대기 중", systemImage: "iphone.slash")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    /// A rough "how far away is this" for the list, straight-line rather than
    /// along a route — computing routes for every row would be wasteful and slow.
    private func straightLineDistance(to destination: Destination) -> Double? {
        guard let origin = model.currentPoint else { return nil }
        return GeoMath.distance(from: origin, to: destination.point)
    }
}
