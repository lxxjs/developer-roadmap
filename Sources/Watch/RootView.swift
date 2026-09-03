import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: GuidanceModel

    var body: some View {
        NavigationStack {
            if model.isNavigating {
                CompassView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                model.endNavigation()
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel("안내 종료")
                        }
                    }
            } else {
                DestinationPickerView()
            }
        }
    }
}
