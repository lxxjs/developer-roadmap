import SwiftUI

/// The iPhone app is a manager, not the product — the watch is where walking
/// happens. This screen exists to show what was shared, to add a place by hand,
/// and to make the pairing state visible when something is not working.
struct ContentView: View {
    @EnvironmentObject private var coordinator: PhoneCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @State private var isAddingDestination = false

    var body: some View {
        NavigationStack {
            List {
                watchSection
                if let route = coordinator.activeRoute {
                    routeSection(route)
                }
                destinationsSection
                helpSection
            }
            .navigationTitle("WalkArrow")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingDestination = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("목적지 추가")
                }
            }
            .sheet(isPresented: $isAddingDestination) {
                AddDestinationView { destination in
                    coordinator.add(destination)
                }
            }
            .refreshable { coordinator.reloadDestinations() }
        }
        // The share extension writes into the app group from another process,
        // so returning to the foreground is when we look again.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { coordinator.reloadDestinations() }
        }
    }

    // MARK: - Sections

    private var watchSection: some View {
        Section("애플워치") {
            if !coordinator.isWatchAppInstalled {
                Label("워치에 앱이 설치되지 않았습니다", systemImage: "applewatch.slash")
                    .foregroundStyle(.orange)
            } else if coordinator.isWatchReachable {
                Label("연결됨", systemImage: "applewatch.radiowaves.left.and.right")
                    .foregroundStyle(.green)
            } else {
                Label("연결 대기 중", systemImage: "applewatch")
                    .foregroundStyle(.secondary)
            }

            if let failure = coordinator.failureMessage {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.footnote)
            }
        }
    }

    private func routeSection(_ route: WalkRoute) -> some View {
        Section("안내 중") {
            VStack(alignment: .leading, spacing: 4) {
                Text(route.destination.name).font(.headline)
                Text("\(DistanceFormatter.string(fromMetres: route.totalDistance)) · 약 \(DistanceFormatter.durationString(route.expectedTravelTime))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("경로 지점 \(route.points.count)개")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Button("안내 종료", role: .destructive) {
                coordinator.stopNavigation()
            }
        }
    }

    private var destinationsSection: some View {
        Section("저장된 목적지") {
            if coordinator.destinations.isEmpty {
                Text("네이버지도에서 장소를 열고 공유 → WalkArrow를 눌러 목적지를 추가하세요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            ForEach(coordinator.destinations) { destination in
                Button {
                    coordinator.route(to: destination)
                } label: {
                    destinationRow(destination)
                }
                .swipeActions {
                    Button("삭제", role: .destructive) {
                        coordinator.remove(destination)
                    }
                }
            }
        }
    }

    private func destinationRow(_ destination: Destination) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(destination.name)
                .foregroundStyle(.primary)
            HStack(spacing: 4) {
                Text(destination.source.displayName)
                if let address = destination.address {
                    Text("·")
                    Text(address).lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var helpSection: some View {
        Section("사용법") {
            Label("네이버지도에서 장소 → 공유 → WalkArrow", systemImage: "square.and.arrow.up")
            Label("애플워치에서 목적지를 골라 안내 시작", systemImage: "applewatch")
            Label("경로 계산은 아이폰이 맡습니다. 워치가 요청하면 이 앱이 백그라운드에서 깨어납니다.", systemImage: "arrow.triangle.2.circlepath")
        }
        .font(.footnote)
    }
}
