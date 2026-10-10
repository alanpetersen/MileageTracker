import CoreData

enum PowerType: String, Codable, CaseIterable, Identifiable {
    case gas
    case ev

    var id: String { rawValue }
    var label: String { self == .gas ? "Gas" : "Electric (EV)" }
    var quantityUnit: String { self == .gas ? "gal" : "kWh" }
    var entryTitle: String { self == .gas ? "Fill-up" : "Charge" }
}

enum ReadingSource: String, Codable {
    case manual
    case camera
}

// Attributes are optional because CloudKit-backed Core Data models require it.

/// The unit of sharing: everyone invited to a household sees all of its vehicles.
@objc(Household)
class Household: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var vehicles: Set<Vehicle>?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        setPrimitiveValue(UUID(), forKey: "uuid")
        setPrimitiveValue(Date.now, forKey: "createdAt")
    }

    var displayName: String { (name ?? "").isEmpty ? "Household" : name! }
}

@objc(Vehicle)
class Vehicle: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var name: String?
    @NSManaged var make: String?
    @NSManaged var model: String?
    @NSManaged var year: NSNumber?
    @NSManaged var powerTypeRaw: String?
    @NSManaged var createdAt: Date?
    @NSManaged var household: Household?
    @NSManaged var readings: Set<OdometerReading>?
    @NSManaged var fuelEntries: Set<FuelEntry>?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        setPrimitiveValue(UUID(), forKey: "uuid")
        setPrimitiveValue(Date.now, forKey: "createdAt")
    }

    var displayName: String { name ?? "Vehicle" }

    var powerType: PowerType {
        get { PowerType(rawValue: powerTypeRaw ?? "") ?? .gas }
        set { powerTypeRaw = newValue.rawValue }
    }

    var subtitle: String {
        [year.map { String($0.intValue) }, make, model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    var readingList: [OdometerReading] { Array(readings ?? []) }
    var entryList: [FuelEntry] { Array(fuelEntries ?? []) }

    /// Highest odometer value across plain readings and fuel/charge entries.
    var currentOdometer: Double? {
        (readingList.map(\.miles) + entryList.map(\.odometer)).max()
    }

    var firstOdometer: Double? {
        (readingList.map(\.miles) + entryList.map(\.odometer)).min()
    }
}

@objc(OdometerReading)
class OdometerReading: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var date: Date?
    @NSManaged var miles: Double
    @NSManaged var sourceRaw: String?
    @NSManaged var photoData: Data?
    @NSManaged var loggedBy: String?
    @NSManaged var vehicle: Vehicle?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        setPrimitiveValue(UUID(), forKey: "uuid")
        setPrimitiveValue(Date.now, forKey: "date")
    }

    var source: ReadingSource {
        get { ReadingSource(rawValue: sourceRaw ?? "") ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}

/// A gas fill-up (quantity in gallons) or EV charge (quantity in kWh).
@objc(FuelEntry)
class FuelEntry: NSManagedObject {
    @NSManaged var uuid: UUID?
    @NSManaged var date: Date?
    @NSManaged var odometer: Double
    @NSManaged var quantity: Double
    /// Total amount paid. Optional; EVs fall back to the default electricity rate.
    @NSManaged var totalCost: NSNumber?
    /// Gas price ($/gal) in effect when the entry was logged, so later price swings don't rewrite history.
    @NSManaged var gasPriceStamp: NSNumber?
    /// For EVs: the $/kWh rate assumed when no cost was entered, stamped for the same reason.
    @NSManaged var electricityRateStamp: NSNumber?
    @NSManaged var sourceRaw: String?
    @NSManaged var photoData: Data?
    @NSManaged var loggedBy: String?
    @NSManaged var vehicle: Vehicle?

    override func awakeFromInsert() {
        super.awakeFromInsert()
        setPrimitiveValue(UUID(), forKey: "uuid")
        setPrimitiveValue(Date.now, forKey: "date")
    }

    var cost: Double? {
        get { totalCost?.doubleValue }
        set { totalCost = newValue.map { NSNumber(value: $0) } }
    }

    var gasPrice: Double? {
        get { gasPriceStamp?.doubleValue }
        set { gasPriceStamp = newValue.map { NSNumber(value: $0) } }
    }

    var electricityRate: Double? {
        get { electricityRateStamp?.doubleValue }
        set { electricityRateStamp = newValue.map { NSNumber(value: $0) } }
    }

    var source: ReadingSource {
        get { ReadingSource(rawValue: sourceRaw ?? "") ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var record: EnergyRecord {
        EnergyRecord(id: uuid ?? UUID(), date: date ?? .distantPast, odometer: odometer, quantity: quantity,
                     totalCost: cost, gasPrice: gasPrice, electricityRate: electricityRate)
    }
}

extension Household: Identifiable {}
extension Vehicle: Identifiable {}

extension NSManagedObjectContext {
    /// Objects can only relate to objects in the same store, so new rows must follow their parent:
    /// the private store for your own households, the shared store for households shared with you.
    func place(_ object: NSManagedObject, alongside parent: NSManagedObject) {
        if let store = parent.objectID.persistentStore { assign(object, to: store) }
    }

    func saveOrLog() {
        guard hasChanges else { return }
        do {
            try save()
        } catch {
            print("Save failed: \(error)")
            rollback()
        }
    }
}

extension Double {
    /// Locale-independent text for editable fields and CSV: "52000", "12.5".
    var plainString: String { self == rounded() && abs(self) < 1e15 ? String(Int(self)) : String(self) }
}
