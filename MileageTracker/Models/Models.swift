import Foundation
import SwiftData

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

@Model
final class Vehicle {
    /// Stable identifier so the dashboard can remember the selected vehicle across launches.
    var uuid: UUID = UUID()
    var name: String
    var make: String
    var model: String
    var year: Int?
    var powerTypeRaw: String
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \OdometerReading.vehicle)
    var readings: [OdometerReading] = []
    @Relationship(deleteRule: .cascade, inverse: \FuelEntry.vehicle)
    var fuelEntries: [FuelEntry] = []

    init(name: String, make: String = "", model: String = "", year: Int? = nil, powerType: PowerType) {
        self.name = name
        self.make = make
        self.model = model
        self.year = year
        self.powerTypeRaw = powerType.rawValue
        self.createdAt = .now
    }

    var powerType: PowerType {
        get { PowerType(rawValue: powerTypeRaw) ?? .gas }
        set { powerTypeRaw = newValue.rawValue }
    }

    var subtitle: String {
        [year.map(String.init), make, model].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    var sortedEntries: [FuelEntry] {
        fuelEntries.sorted { ($0.odometer, $0.date) < ($1.odometer, $1.date) }
    }

    /// Highest odometer value across plain readings and fuel/charge entries.
    var currentOdometer: Double? {
        (readings.map(\.miles) + fuelEntries.map(\.odometer)).max()
    }

    var firstOdometer: Double? {
        (readings.map(\.miles) + fuelEntries.map(\.odometer)).min()
    }
}

@Model
final class OdometerReading {
    var date: Date
    var miles: Double
    var sourceRaw: String
    @Attribute(.externalStorage) var photoData: Data?
    var vehicle: Vehicle?

    init(date: Date = .now, miles: Double, source: ReadingSource, photoData: Data? = nil) {
        self.date = date
        self.miles = miles
        self.sourceRaw = source.rawValue
        self.photoData = photoData
    }

    var source: ReadingSource { ReadingSource(rawValue: sourceRaw) ?? .manual }
}

/// A gas fill-up (quantity in gallons) or EV charge (quantity in kWh).
@Model
final class FuelEntry {
    var id: UUID
    var date: Date
    var odometer: Double
    var quantity: Double
    /// Total amount paid. Optional; EVs fall back to the default electricity rate.
    var totalCost: Double?
    var sourceRaw: String
    @Attribute(.externalStorage) var photoData: Data?
    var vehicle: Vehicle?

    init(date: Date = .now, odometer: Double, quantity: Double, totalCost: Double? = nil,
         source: ReadingSource, photoData: Data? = nil) {
        self.id = UUID()
        self.date = date
        self.odometer = odometer
        self.quantity = quantity
        self.totalCost = totalCost
        self.sourceRaw = source.rawValue
        self.photoData = photoData
    }

    var record: EnergyRecord {
        EnergyRecord(id: id, date: date, odometer: odometer, quantity: quantity, totalCost: totalCost)
    }
}
