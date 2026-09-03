import SwiftUI

/// Confirms what was parsed before it is saved.
///
/// This screen is not a formality. The share URL formats are unofficial and
/// change, so the user is shown the name and the coordinates that were
/// extracted and can rename or reject them — a silent save would quietly store
/// the wrong place.
struct ShareConfirmView: View {
    /// Named `Outcome` rather than `State` so it does not shadow SwiftUI's
    /// `@State` property wrapper inside this type.
    enum Outcome {
        case loading
        case parsed(Destination)
        case failed(String)
    }

    let state: Outcome
    let onSave: (Destination) -> Void
    let onCancel: () -> Void

    @State private var editedName = ""

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView("장소를 읽는 중")
                case .parsed(let destination):
                    parsedBody(destination)
                case .failed(let message):
                    failedBody(message)
                }
            }
            .navigationTitle("WalkArrow에 저장")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { onCancel() }
                }
                if case .parsed(let destination) = state {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장") { save(destination) }
                    }
                }
            }
        }
    }

    private func parsedBody(_ destination: Destination) -> some View {
        Form {
            Section("이름") {
                TextField("장소 이름", text: $editedName)
                    .onAppear {
                        if editedName.isEmpty { editedName = destination.name }
                    }
            }
            Section("좌표") {
                Text(String(format: "%.6f, %.6f", destination.point.latitude, destination.point.longitude))
                    .monospacedDigit()
                if let address = destination.address {
                    Text(address)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text("저장하면 애플워치의 목적지 목록에 나타납니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func failedBody(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .font(.callout)
            Text("WalkArrow 앱에서 주소나 좌표를 직접 입력할 수 있습니다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func save(_ destination: Destination) {
        var edited = destination
        let trimmed = editedName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { edited.name = trimmed }
        onSave(edited)
    }
}
