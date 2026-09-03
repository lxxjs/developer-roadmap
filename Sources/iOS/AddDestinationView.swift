import CoreLocation
import SwiftUI

/// Manual entry, for a place typed by hand or a pair of coordinates pasted in.
///
/// This is the escape hatch that makes the app usable when a Naver share
/// cannot be parsed — the share formats are unofficial, so there has to be a
/// path that does not depend on them.
struct AddDestinationView: View {
    let onSave: (Destination) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var query = ""
    @State private var resolved: GeoPoint?
    @State private var resolvedAddress: String?
    @State private var isResolving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("이름") {
                    TextField("예: 회사", text: $name)
                }

                Section("주소 또는 좌표") {
                    TextField("예: 서울시청 또는 37.5665, 126.9780", text: $query)
                        .autocorrectionDisabled()
                    Button {
                        resolve()
                    } label: {
                        HStack {
                            Text("위치 확인")
                            if isResolving {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || isResolving)
                }

                if let resolved {
                    Section("확인된 위치") {
                        Text(String(format: "%.6f, %.6f", resolved.latitude, resolved.longitude))
                            .monospacedDigit()
                        if let resolvedAddress {
                            Text(resolvedAddress)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.orange)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("목적지 추가")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(resolved == nil)
                }
            }
        }
    }

    private func resolve() {
        let text = query.trimmingCharacters(in: .whitespaces)
        errorMessage = nil

        // A pasted coordinate pair should not need a network round trip.
        if let point = NaverShareParser.parse(text: text).point {
            resolved = point
            resolvedAddress = nil
            if name.isEmpty { name = text }
            return
        }

        isResolving = true
        // Pinned to the main actor: the closure writes `@State`, and a plain
        // `Task` here would inherit a non-isolated context.
        Task { @MainActor in
            defer { isResolving = false }
            do {
                let placemarks = try await CLGeocoder().geocodeAddressString(text)
                guard let placemark = placemarks.first, let location = placemark.location else {
                    errorMessage = "주소를 찾지 못했습니다."
                    return
                }
                resolved = GeoPoint(location.coordinate)
                resolvedAddress = placemark.formattedAddress
                if name.isEmpty { name = placemark.name ?? text }
            } catch {
                errorMessage = "주소를 찾지 못했습니다."
            }
        }
    }

    private func save() {
        guard let resolved, resolved.isValid else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        onSave(
            Destination(
                name: trimmed.isEmpty ? "목적지" : trimmed,
                point: resolved,
                address: resolvedAddress,
                source: .manual
            )
        )
        dismiss()
    }
}

extension CLPlacemark {
    /// A one-line address, in the order Korean addresses are written.
    var formattedAddress: String? {
        let parts = [administrativeArea, locality, subLocality, thoroughfare, subThoroughfare]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}
