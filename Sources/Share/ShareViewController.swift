import CoreLocation
import Social
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Receives a place from the iOS share sheet — the way a Naver Map destination
/// gets into this app.
///
/// Naver Map offers no plug-in surface, so the share sheet is the only
/// supported hand-off. What arrives is a share link and usually a place name;
/// the link formats are unofficial, so the extension always shows what it
/// parsed and lets the user correct it before saving.
final class ShareViewController: UIViewController {
    private let store = DestinationStore()

    override func viewDidLoad() {
        super.viewDidLoad()
        Task { await load() }
    }

    private func load() async {
        let shared = await extractSharedText()

        guard let shared, !shared.isEmpty else {
            present(state: .failed("공유된 내용을 읽지 못했습니다."))
            return
        }

        var parsed = await NaverShortlinkResolver().parse(text: shared)

        // No coordinate in the link: fall back to geocoding whatever name or
        // address we did get. Naver's newer place links often carry only an id.
        if parsed.point == nil, let query = parsed.name ?? parsed.address {
            parsed.point = await geocode(query)
        }

        guard let point = parsed.point, point.isValid else {
            present(state: .failed("좌표를 찾지 못했습니다. 앱에서 직접 입력해 주세요."))
            return
        }

        present(
            state: .parsed(
                Destination(
                    name: parsed.name ?? parsed.address ?? "공유된 장소",
                    point: point,
                    address: parsed.address,
                    source: .naverShare
                )
            )
        )
    }

    // MARK: - Input

    /// Pulls the first URL or plain-text item out of the share.
    ///
    /// Both are collected because Naver's share carries the place name as text
    /// and the coordinates in the URL, and neither alone is enough.
    private func extractSharedText() async -> String? {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else { return nil }

        var pieces: [String] = []
        for item in items {
            for provider in item.attachments ?? [] {
                if let url = await loadURL(from: provider) {
                    pieces.append(url.absoluteString)
                } else if let text = await loadText(from: provider) {
                    pieces.append(text)
                }
            }
            if let attributed = item.attributedContentText?.string, !attributed.isEmpty {
                pieces.append(attributed)
            }
        }
        return pieces.isEmpty ? nil : pieces.joined(separator: "\n")
    }

    private func loadURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                continuation.resume(returning: item as? URL)
            }
        }
    }

    private func loadText(from provider: NSItemProvider) async -> String? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                continuation.resume(returning: item as? String)
            }
        }
    }

    private func geocode(_ query: String) async -> GeoPoint? {
        do {
            let placemarks = try await CLGeocoder().geocodeAddressString(query)
            guard let location = placemarks.first?.location else { return nil }
            return GeoPoint(location.coordinate)
        } catch {
            return nil
        }
    }

    // MARK: - Presentation

    private func present(state: ShareConfirmView.Outcome) {
        let view = ShareConfirmView(
            state: state,
            onSave: { [weak self] destination in
                self?.save(destination)
            },
            onCancel: { [weak self] in
                self?.extensionContext?.completeRequest(returningItems: nil)
            }
        )

        let host = UIHostingController(rootView: view)
        addChild(host)
        host.view.frame = self.view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        self.view.addSubview(host.view)
        host.didMove(toParent: self)
    }

    private func save(_ destination: Destination) {
        let stored = store.add(destination)
        // Marked pending so the app and the watch can offer it first.
        store.pendingDestinationID = stored.id
        extensionContext?.completeRequest(returningItems: nil)
    }
}
