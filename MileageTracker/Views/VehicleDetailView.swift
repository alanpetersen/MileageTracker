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
        let summary = MileageCalculator.summary(of: segments)
        List {
            Section("Overview") {
                if let odometer = vehicle.currentOdometer {
                    LabeledContent("Odometer", value: "\(odometer.formatted(.number.precision(.fractionLength(0)))) mi")
                }
                if let first = vehicle.firstOdometer, let current = vehicle.currentOdometer, current > first {
                    LabeledContent("Tracked", value: "\((current - first).formatted(.number.precision(.fractionLength(0)))) mi")
                }
                statsRows(summary)
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

    @ViewBuilder
    private func statsRows(_ summary: Summary) -> some View {
        switch vehicle.powerType {
        case .gas:
            if let mpg = summary.milesPerUnit {
                LabeledContent("Average MPG", value: mpg.formatted(.number.precision(.fractionLength(1))))
            }
            if let cpm = summary.costPerMile {
                LabeledContent("Cost per mile", value: cpm.formatted(.currency(code: "USD")))
            }
        case .ev:
            if let mikwh = summary.milesPerUnit {
                LabeledContent("Efficiency", value: "\((1 / mikwh * 1000).formatted(.number.precision(.fractionLength(0)))) Wh/mi  ·  \(mikwh.formatted(.number.precision(.fractionLength(2)))) mi/kWh")
            }
            if let cpm = summary.costPerMile {
                LabeledContent("Cost per mile", value: cpm.formatted(.currency(code: "USD")))
            }
            if let mpge = MileageCalculator.effectiveMPG(costPerMile: summary.costPerMile, gasPrice: settings.gasPrice) {
                LabeledContent("Effective MPG", value: mpge.formatted(.number.precision(.fractionLength(1))))
                    .font(.headline)
                Text("Miles per gallon a gas car would need to cost the same per mile at \(settings.gasPrice!.formatted(.currency(code: "USD")))/gal (\(settings.gasPriceDescription)).")
                    .font(.caption).foregroundStyle(.secondary)
            } else if summary.costPerMile != nil {
                Text("Set a gas price in Settings to see effective MPG.").font(.caption).foregroundStyle(.secondary)
            }
        }
        if summary.miles == 0 {
            Text("Log at least two \(vehicle.powerType.entryTitle.lowercased())s with odometer readings to see efficiency.")
                .font(.caption).foregroundStyle(.secondary)
        }
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
