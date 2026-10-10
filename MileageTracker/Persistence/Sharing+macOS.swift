#if os(macOS)
import AppKit
import CloudKit
import CoreData

extension PersistenceController {
    /// Shows the system sharing popover for a household, creating the CKShare first if needed.
    /// `onChange` runs after the share is created or its participants change.
    @MainActor
    func presentSharing(for household: Household, onChange: @escaping () -> Void) async throws {
        let share: CKShare
        if let existing = self.share(for: household) {
            share = existing
        } else {
            guard let privateStore, !isSharedWithMe(household) else { return }
            let (_, newShare, _) = try await container.share([household], to: nil)
            newShare[CKShare.SystemFieldKey.title] = household.displayName
            share = try await container.persistUpdatedShare(newShare, in: privateStore)
            onChange()
        }

        let provider = NSItemProvider()
        provider.registerCloudKitShare(share, container: cloudKitContainer)
        guard let service = NSSharingService(named: .cloudSharing) else { return }
        let delegate = ShareDelegate(onChange: onChange)
        ShareDelegate.current = delegate
        service.delegate = delegate
        service.perform(withItems: [provider])
    }
}

private final class ShareDelegate: NSObject, NSCloudSharingServiceDelegate {
    /// NSSharingService holds its delegate weakly.
    static var current: ShareDelegate?

    let onChange: () -> Void
    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    func sharingService(_ sharingService: NSSharingService, sourceWindowForShareItems items: [Any],
                        sharingContentScope: UnsafeMutablePointer<NSSharingService.SharingContentScope>) -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }

    func sharingService(_ sharingService: NSSharingService, didSave share: CKShare) { onChange() }
    func sharingService(_ sharingService: NSSharingService, didStopSharing share: CKShare) { onChange() }
    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        print("Sharing failed: \(error)")
    }
}

/// Routes accepted share invitations (clicked iCloud links) to Core Data.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { await PersistenceController.shared.acceptShare(metadata) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Silent pushes tell the app when iCloud data changed on another device.
        NSApplication.shared.registerForRemoteNotifications()
    }
}
#endif
