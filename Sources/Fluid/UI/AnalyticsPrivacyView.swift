import SwiftUI

struct AnalyticsPrivacyView: View {
    var body: some View {
        ContentUnavailableView("Telemetry disabled", systemImage: "lock.shield",
            description: Text("This fork does not collect or upload analytics. Existing telemetry queues are removed at launch."))
    }
}
