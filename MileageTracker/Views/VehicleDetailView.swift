import SwiftUI
import CoreData

struct VehicleDetailView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(AppSettings.self) private var settings
    @ObservedObject var vehicle: Vehicle

    @State private var showingReading = false
    @State private var showingEntry = false
    @State private var editingItem: HistoryItem?
    @AppStorage("defaultVehicleID") private var defaultVehicleID = ""

    private var isDefault: Bool { vehicle.uuid?.uuidString == defaultVehicleID }

    private var segments: [Segment] {
        let fallback = vehicle.powerType == .ev ? settings.defaultElectricityRate : nil
        return MileageCalculator.segments(from: vehicle.entryList.map(\.record), fallbackCostPerUnit: fallback,
                                          fallbackGasPrice: settings.gasPrice)
    }

    var body: some View {
        let segments = segments
        List {
            Section("Overview") {
                VehicleOverviewRows(vehicle: vehicle)
            }

            Section("History") {
                let readings = vehicle.readingList.map { HistoryItem.reading($0) }
                let entries = vehicle.entryList.map { HistoryItem.entry($0) }
                let items = (readings + entries).sorted { $0.date > $1.date }
                if items.isEmpty {
                    Text("Nothing logged yet.").foregroundStyle(.secondary)
                } else {
                    Text("Tap an entry to edit or delete it.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    Button {
                        editingItem = item
                    } label: {
                        HistoryRow(item: item, unit: vehicle.powerType.quantityUnit,
                                   segment: segmentFor(item, in: segments))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets {
                        switch items[index] {
                        case .reading(let reading): context.delete(reading)
                        case .entry(let entry): context.delete(entry)
                        }
                    }
                    context.saveOrLog()
                }
            }
        }
        .navigationTitle(vehicle.displayName)
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button(isDefault ? "Default Vehicle" : "Set as Default",
                       systemImage: isDefault ? "star.fill" : "star") {
                    defaultVehicleID = isDefault ? "" : (vehicle.uuid?.uuidString ?? "")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("Add", systemImage: "plus") {
                    Button("Log \(vehicle.powerType.entryTitle)", systemImage: vehicle.powerType == .ev ? "bolt" : "fuelpump") {
                        showingEntry = true
                    }
                    Button("Log Odometer Only", systemImage: "gauge") { showingReading = true }
                }
            }
        }
        .sheet(isPresented: $showingReading) { AddReadingView(vehicle: vehicle) }
        .sheet(isPresented: $showingEntry) { AddFuelEntryView(vehicle: vehicle, currentGasPrice: settings.gasPrice) }
        .sheet(item: $editingItem) { item in
            switch item {
            case .reading(let reading): AddReadingView(vehicle: vehicle, editing: reading)
            case .entry(let entry): AddFuelEntryView(vehicle: vehicle, editing: entry)
            }
        }
    }

    private func segmentFor(_ item: HistoryItem, in segments: [Segment]) -> Segment? {
        guard case .entry(let entry) = item else { return nil }
        return segments.first { $0.id == entry.uuid }
    }
}

enum HistoryItem: Identifiable {
    case reading(OdometerReading)
    case entry(FuelEntry)

    var id: NSManagedObjectID {
        switch self {
        case .reading(let r): r.objectID
        case .entry(let e): e.objectID
        }
    }

    var date: Date {
        switch self {
        case .reading(let r): r.date ?? .distantPast
        case .entry(let e): e.date ?? .distantPast
        }
    }
}

private struct HistoryRow: View {
    let item: HistoryItem
    let unit: String
    let segment: Segment?

    var body: some View {
        switch item {
        case .reading(let reading):
            VStack(alignment: .leading) {
                HStack {
                    Image(systemName: reading.source == .camera ? "camera" : "pencil").foregroundStyle(.secondary)
                    Text("\(reading.miles, format: .number.precision(.fractionLength(0))) mi").font(.headline)
                }
                caption(date: reading.date, loggedBy: reading.loggedBy)
            }
        case .entry(let entry):
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: entry.source == .camera ? "camera" : "pencil").foregroundStyle(.secondary)
                    Text("\(entry.odometer, format: .number.precision(.fractionLength(0))) mi").font(.headline)
                    Spacer()
                    Text("\(entry.quantity, format: .number.precision(.fractionLength(1))) \(unit)")
                }
                HStack {
                    caption(date: entry.date, loggedBy: entry.loggedBy)
                    Spacer()
                    if let segment {
                        Text("\(segment.milesPerUnit, format: .number.precision(.fractionLength(1))) mi/\(unit)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let prices = priceCaption(for: entry) {
                    Text(prices).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The prices stamped on the entry when it was logged.
    private func priceCaption(for entry: FuelEntry) -> String? {
        var parts: [String] = []
        if let cost = entry.cost { parts.append(cost.formatted(.currency(code: "USD"))) }
        if let gas = entry.gasPrice { parts.append("gas \(gas.formatted(.currency(code: "USD")))/gal") }
        if entry.cost == nil, let rate = entry.electricityRate { parts.append("\(rate.formatted(.currency(code: "USD")))/kWh") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func caption(date: Date?, loggedBy: String?) -> some View {
        HStack(spacing: 4) {
            if let date { Text(date, style: .date) }
            if let loggedBy, !loggedBy.isEmpty { Text("· \(loggedBy)") }
        }
        .font(.caption).foregroundStyle(.secondary)
    }
}
