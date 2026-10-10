import SwiftUI
import SwiftData

struct VehicleDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    let vehicle: Vehicle

    @State private var showingReading = false
    @State private var showingEntry = false

    private var segments: [Segment] {
        let fallback = vehicle.powerType == .ev ? settings.defaultElectricityRate : nil
        return MileageCalculator.segments(from: vehicle.fuelEntries.map(\.record), fallbackCostPerUnit: fallback)
    }

    var body: some View {
        let segments = segments
        List {
            Section("Overview") {
                VehicleOverviewRows(vehicle: vehicle)
            }

            Section("History") {
                let readings = vehicle.readings.map { HistoryItem.reading($0) }
                let entries = vehicle.fuelEntries.map { HistoryItem.entry($0) }
                let items = (readings + entries).sorted { $0.date > $1.date }
                if items.isEmpty {
                    Text("Nothing logged yet.").foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    HistoryRow(item: item, unit: vehicle.powerType.quantityUnit,
                               segment: segmentFor(item, in: segments))
                }
                .onDelete { offsets in
                    for index in offsets {
                        switch items[index] {
                        case .reading(let reading): context.delete(reading)
                        case .entry(let entry): context.delete(entry)
                        }
                    }
                }
            }
        }
        .navigationTitle(vehicle.name)
        .toolbar {
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
        .sheet(isPresented: $showingEntry) { AddFuelEntryView(vehicle: vehicle) }
    }

    private func segmentFor(_ item: HistoryItem, in segments: [Segment]) -> Segment? {
        guard case .entry(let entry) = item else { return nil }
        return segments.first { $0.id == entry.id }
    }
}

enum HistoryItem: Identifiable {
    case reading(OdometerReading)
    case entry(FuelEntry)

    var id: String {
        switch self {
        case .reading(let r): "r-\(r.persistentModelID.hashValue)"
        case .entry(let e): "e-\(e.id)"
        }
    }

    var date: Date {
        switch self {
        case .reading(let r): r.date
        case .entry(let e): e.date
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
                Text(reading.date, style: .date).font(.caption).foregroundStyle(.secondary)
            }
        case .entry(let entry):
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: entry.sourceRaw == ReadingSource.camera.rawValue ? "camera" : "pencil")
                        .foregroundStyle(.secondary)
                    Text("\(entry.odometer, format: .number.precision(.fractionLength(0))) mi").font(.headline)
                    Spacer()
                    Text("\(entry.quantity, format: .number.precision(.fractionLength(1))) \(unit)")
                }
                HStack {
                    Text(entry.date, style: .date)
                    Spacer()
                    if let segment {
                        Text("\(segment.milesPerUnit, format: .number.precision(.fractionLength(1))) mi/\(unit)")
                    }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
