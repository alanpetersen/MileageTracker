import SwiftUI

@main
struct MileageTrackerApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #else
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @State private var settings = AppSettings()
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(settings)
                .environment(\.managedObjectContext, persistence.viewContext)
                .task { await settings.refreshGasPrice() }
        }
        #if os(macOS)
        .defaultSize(width: 560, height: 760)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(settings)
                .macSheetSize()
        }
        #endif
    }
}
