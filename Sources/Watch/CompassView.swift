import SwiftUI

/// The screen the whole app exists for: which way to walk, and how far is left.
struct CompassView: View {
    @EnvironmentObject private var model: GuidanceModel
    /// True while the wrist is down and the display is in Always On mode.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(spacing: 4) {
            header
            arrow
            footer
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Pieces

    private var header: some View {
        Text(model.route.map { DisplayText.compactPlaceName($0.destination.name) } ?? "목적지")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private var arrow: some View {
        ZStack {
            if !isLuminanceReduced {
                CompassDial()
            }

            if let guidance = model.guidance, guidance.hasArrived {
                arrivedBadge
            } else if model.isArrowResolved {
                ArrowShape()
                    .fill(arrowColor)
                    .frame(width: 62, height: 76)
                    .rotationEffect(.degrees(model.arrowRotation))
                    // Always On freezes updates anyway; animating there just
                    // burns the frame budget the system allows.
                    .animation(
                        isLuminanceReduced ? nil : .interpolatingSpring(stiffness: 120, damping: 14),
                        value: model.arrowRotation
                    )
            } else {
                acquiringBadge
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96)
    }

    private var arrivedBadge: some View {
        VStack(spacing: 2) {
            Image(systemName: "flag.checkered")
                .font(.system(size: 30, weight: .semibold))
            Text("도착")
                .font(.headline)
        }
        .foregroundStyle(.green)
    }

    private var acquiringBadge: some View {
        VStack(spacing: 4) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text(acquiringMessage)
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            if let guidance = model.guidance, !guidance.hasArrived {
                Text(DistanceFormatter.string(fromMetres: guidance.distanceRemainingAlongRoute))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()

                if !isLuminanceReduced {
                    subtitle(for: guidance)
                }
            } else if model.guidance?.hasArrived == true {
                Text(model.route?.destination.address ?? "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func subtitle(for guidance: RouteGuidance) -> some View {
        if guidance.isOffRoute {
            Label("경로 이탈 · 재탐색", systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if let turn = guidance.upcomingTurnDistance {
            Text("\(DistanceFormatter.string(fromMetres: turn)) 앞 회전")
                .font(.caption2)
                .foregroundStyle(.orange)
                .lineLimit(1)
        } else if model.headingSource == .course {
            Text("걸으면 방향이 잡혀요")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if let instruction = DisplayText.compactInstruction(guidance.instruction) {
            Text(instruction)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    // MARK: - Derived

    /// Orange while off route, so the colour alone says the arrow is now a
    /// straight line to the destination rather than the walking route.
    private var arrowColor: Color {
        guard let guidance = model.guidance else { return .accentColor }
        if guidance.isOffRoute { return .orange }
        return isLuminanceReduced ? .secondary : .accentColor
    }

    private var acquiringMessage: String {
        if model.needsCompassCalibration {
            return "손목을 8자로 흔들어 주세요"
        }
        switch model.locationAuthorization {
        case .denied, .restricted:
            return "설정에서 위치 권한을 켜주세요"
        case .notDetermined:
            return "위치 권한을 확인 중"
        default:
            return model.hasHeading ? "위치 확인 중" : "방향 확인 중"
        }
    }
}
