import SwiftUI
import SwiftData

@main
struct MileageTrackerApp: App {
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            VehicleListView()
                .environment(settings)
                .task { await settings.refreshGasPrice() }
        }
        .modelContainer(for: [Vehicle.self, OdometerReading.self, FuelEntry.self])
    }
}
