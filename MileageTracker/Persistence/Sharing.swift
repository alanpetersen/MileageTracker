#if os(iOS)
import CloudKit
import CoreData
import UIKit

extension PersistenceController {
    /// Shows the system sharing sheet for a household, creating the CKShare first if needed.
    /// `onChange` runs after participants are updated or sharing stops.
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

        let controller = UICloudSharingController(share: share, container: cloudKitContainer)
        // Everyone in a household can log entries; invites go only to the people you pick.
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        ShareDelegate.current = ShareDelegate(title: household.displayName, onChange: onChange)
        controller.delegate = ShareDelegate.current
        UIApplication.shared.topViewController?.present(controller, animated: true)
    }
}

private final class ShareDelegate: NSObject, UICloudSharingControllerDelegate {
    /// UICloudSharingController holds its delegate weakly.
    static var current: ShareDelegate?

    let title: String
    let onChange: () -> Void

    init(title: String, onChange: @escaping () -> Void) {
        self.title = title
        self.onChange = onChange
    }

    func itemTitle(for csc: UICloudSharingController) -> String? { title }

    func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
        print("Saving share failed: \(error)")
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) { onChange() }
    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) { onChange() }
}

private extension UIApplication {
    var topViewController: UIViewController? {
        let scene = connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Routes accepted share invitations (tapped iCloud links) to Core Data.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Cold launch from an invitation link.
        if let metadata = connectionOptions.cloudKitShareMetadata {
            Task { await PersistenceController.shared.acceptShare(metadata) }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { await PersistenceController.shared.acceptShare(metadata) }
    }
}
#endif
