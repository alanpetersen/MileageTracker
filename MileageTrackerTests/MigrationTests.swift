import XCTest
import CoreData
@testable import MileageTracker

final class MigrationTests: XCTestCase {
    /// A store written with the original model must open with the current one (lightweight migration),
    /// keeping its data and leaving the new stamp fields empty.
    func testStoreFromVersion1OpensWithCurrentModel() throws {
        let momd = Bundle(for: PersistenceController.self).url(forResource: "MileageTracker", withExtension: "momd")!
        let v1 = try XCTUnwrap(NSManagedObjectModel(contentsOf: momd.appending(path: "MileageTracker.mom")))
        let current = try XCTUnwrap(NSManagedObjectModel(contentsOf: momd.appending(path: "MileageTracker 2.mom")))
        XCTAssertNil(v1.entitiesByName["FuelEntry"]?.propertiesByName["gasPriceStamp"])
        XCTAssertNotNil(current.entitiesByName["FuelEntry"]?.propertiesByName["gasPriceStamp"])

        let url = FileManager.default.temporaryDirectory.appending(path: "migration-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }

        let oldCoordinator = NSPersistentStoreCoordinator(managedObjectModel: v1)
        try oldCoordinator.addPersistentStore(type: .sqlite, configuration: nil, at: url)
        let oldContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        oldContext.persistentStoreCoordinator = oldCoordinator
        let entry = NSEntityDescription.insertNewObject(forEntityName: "FuelEntry", into: oldContext)
        entry.setValue(1234.0, forKey: "odometer")
        try oldContext.save()
        for store in oldCoordinator.persistentStores { try oldCoordinator.remove(store) }

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: current)
        try coordinator.addPersistentStore(type: .sqlite, configuration: nil, at: url, options: [
            NSMigratePersistentStoresAutomaticallyOption: true, NSInferMappingModelAutomaticallyOption: true])
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let migrated = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "FuelEntry"))
        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated.first?.value(forKey: "odometer") as? Double, 1234)
        XCTAssertNil(migrated.first?.value(forKey: "gasPriceStamp"))
    }
}
