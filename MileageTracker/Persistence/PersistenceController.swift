import CoreData
import CloudKit

/// Core Data stack mirrored to CloudKit. Two stores share one model:
/// - private: your own households, synced across your devices
/// - shared: households other people have shared with you
final class PersistenceController {
    static let shared = PersistenceController()
    static let cloudKitContainerID = "iCloud.com.jthought.MileageTracker"

    /// Loaded once: each NSManagedObjectModel instance claims the entity classes, and two instances
    /// in one process make `Household(context:)` ambiguous.
    private static let model: NSManagedObjectModel = {
        let url = Bundle(for: PersistenceController.self).url(forResource: "MileageTracker", withExtension: "momd")!
        return NSManagedObjectModel(contentsOf: url)!
    }()

    let container: NSPersistentCloudKitContainer
    private(set) var privateStore: NSPersistentStore?
    private(set) var sharedStore: NSPersistentStore?
    private var remoteChangeObserver: NSObjectProtocol?

    var viewContext: NSManagedObjectContext { container.viewContext }
    var cloudKitContainer: CKContainer { CKContainer(identifier: Self.cloudKitContainerID) }

    /// Unit tests, and UI tests launched with `-UITestInMemory`, run against an in-memory store with no CloudKit.
    init(inMemory: Bool = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
                || ProcessInfo.processInfo.arguments.contains("-UITestInMemory")) {
        container = NSPersistentCloudKitContainer(name: "MileageTracker", managedObjectModel: Self.model)
        if inMemory {
            container.persistentStoreDescriptions = [NSPersistentStoreDescription(url: URL(fileURLWithPath: "/dev/null"))]
        } else {
            let directory = NSPersistentContainer.defaultDirectoryURL()
            container.persistentStoreDescriptions = [
                Self.storeDescription(url: directory.appending(path: "private.sqlite"), scope: .private),
                Self.storeDescription(url: directory.appending(path: "shared.sqlite"), scope: .shared),
            ]
        }

        container.loadPersistentStores { description, error in
            if let error { fatalError("Failed to load \(description.url?.lastPathComponent ?? "store"): \(error)") }
            let store = description.url.flatMap { self.container.persistentStoreCoordinator.persistentStore(for: $0) }
            if description.cloudKitContainerOptions?.databaseScope == .shared {
                self.sharedStore = store
            } else {
                self.privateStore = store
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        remoteChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange, object: container.persistentStoreCoordinator, queue: .main
        ) { [weak self] _ in
            self?.mergeDuplicateHouseholds()
        }
    }

    private static func storeDescription(url: URL, scope: CKDatabase.Scope) -> NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: url)
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerID)
        options.databaseScope = scope
        description.cloudKitContainerOptions = options
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        return description
    }

    func isSharedWithMe(_ household: Household) -> Bool {
        sharedStore != nil && household.objectID.persistentStore == sharedStore
    }

    func share(for household: Household) -> CKShare? {
        (try? container.fetchShares(matching: [household.objectID]))?[household.objectID]
    }

    /// Creates your own household. Called lazily when you add your first vehicle.
    func makeHousehold() -> Household {
        let household = Household(context: viewContext)
        if let privateStore { viewContext.assign(household, to: privateStore) }
        household.name = "My Household"
        viewContext.saveOrLog()
        return household
    }

    /// Two of your devices can each create a household before iCloud syncs. Fold unshared duplicates
    /// into the oldest one. Every device picks the same survivor, so they converge.
    private func mergeDuplicateHouseholds() {
        guard let privateStore else { return }
        let request = NSFetchRequest<Household>(entityName: "Household")
        request.affectedStores = [privateStore]
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Household.createdAt, ascending: true),
                                   NSSortDescriptor(keyPath: \Household.uuid, ascending: true)]
        let unshared = ((try? viewContext.fetch(request)) ?? []).filter { share(for: $0) == nil }
        guard let keeper = unshared.first, unshared.count > 1 else { return }
        for duplicate in unshared.dropFirst() {
            for vehicle in duplicate.vehicles ?? [] { vehicle.household = keeper }
            viewContext.delete(duplicate)
        }
        viewContext.saveOrLog()
    }

    func acceptShare(_ metadata: CKShare.Metadata) async {
        guard let sharedStore else { return }
        do {
            _ = try await container.acceptShareInvitations(from: [metadata], into: sharedStore)
            // Clearing the selection makes the dashboard switch to the newly shared household.
            await MainActor.run { UserDefaults.standard.removeObject(forKey: "activeHouseholdID") }
        } catch {
            print("Accepting share failed: \(error)")
        }
    }
}
