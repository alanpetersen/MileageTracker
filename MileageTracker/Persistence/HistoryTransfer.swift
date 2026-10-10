import CoreData

/// Moves history between Core Data and `HistoryRecord`s (the CSV layer's model).
enum HistoryTransfer {
    struct ImportSummary: Equatable {
        var added = 0
        var duplicates = 0
        var vehiclesCreated = 0
    }

    // MARK: Export

    static func records(for vehicles: [Vehicle]) -> [HistoryRecord] {
        vehicles.flatMap { vehicle -> [HistoryRecord] in
            let name = vehicle.displayName
            let fuel = vehicle.entryList.map { e in
                HistoryRecord(kind: .fuel, vehicle: name, powerType: vehicle.powerType, date: e.date ?? .distantPast,
                              odometer: e.odometer, quantity: e.quantity, totalCost: e.cost, gasPrice: e.gasPrice,
                              electricityRate: e.electricityRate, source: e.source, loggedBy: e.loggedBy, id: e.uuid)
            }
            let readings = vehicle.readingList.map { r in
                HistoryRecord(kind: .odometer, vehicle: name, powerType: vehicle.powerType, date: r.date ?? .distantPast,
                              odometer: r.miles, source: r.source, loggedBy: r.loggedBy, id: r.uuid)
            }
            return fuel + readings
        }
        .sorted { ($0.vehicle, $0.date) < ($1.vehicle, $1.date) }
    }

    // MARK: Import

    /// Adds the records to `household`, matching vehicles by name (case-insensitive) and creating any that
    /// don't exist yet. Rows already present are skipped, so importing the same file twice is harmless.
    /// A row counts as present when its id matches, or when vehicle, date, odometer and quantity all match.
    @discardableResult
    static func importRecords(_ records: [HistoryRecord], into household: Household,
                              context: NSManagedObjectContext, loggedByFallback: String? = nil) -> ImportSummary {
        var summary = ImportSummary()
        var vehicles = Array(household.vehicles ?? [])

        for record in records {
            let vehicle: Vehicle
            if let existing = vehicles.first(where: { $0.displayName.caseInsensitiveCompare(record.vehicle) == .orderedSame }) {
                vehicle = existing
            } else {
                vehicle = Vehicle(context: context)
                context.place(vehicle, alongside: household)
                vehicle.name = record.vehicle
                vehicle.powerType = record.powerType
                vehicle.household = household
                vehicles.append(vehicle)
                summary.vehiclesCreated += 1
            }

            switch record.kind {
            case .fuel:
                let exists = vehicle.entryList.contains { e in
                    if let id = record.id, e.uuid == id { return true }
                    return e.date.map { abs($0.timeIntervalSince(record.date)) < 1 } == true
                        && e.odometer == record.odometer && e.quantity == record.quantity
                }
                if exists { summary.duplicates += 1; continue }
                let entry = FuelEntry(context: context)
                context.place(entry, alongside: vehicle)
                if let id = record.id { entry.uuid = id }
                entry.date = record.date
                entry.odometer = record.odometer
                entry.quantity = record.quantity
                entry.cost = record.totalCost
                entry.gasPrice = record.gasPrice
                entry.electricityRate = record.electricityRate
                entry.source = record.source
                entry.loggedBy = record.loggedBy ?? loggedByFallback
                entry.vehicle = vehicle
            case .odometer:
                let exists = vehicle.readingList.contains { r in
                    if let id = record.id, r.uuid == id { return true }
                    return r.date.map { abs($0.timeIntervalSince(record.date)) < 1 } == true && r.miles == record.odometer
                }
                if exists { summary.duplicates += 1; continue }
                let reading = OdometerReading(context: context)
                context.place(reading, alongside: vehicle)
                if let id = record.id { reading.uuid = id }
                reading.date = record.date
                reading.miles = record.odometer
                reading.source = record.source
                reading.loggedBy = record.loggedBy ?? loggedByFallback
                reading.vehicle = vehicle
            }
            summary.added += 1
        }
        return summary
    }
}
