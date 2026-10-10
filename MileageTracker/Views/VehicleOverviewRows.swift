import SwiftUI

/// Odometer and efficiency stats for one vehicle. Shared by the dashboard and the vehicle detail screen.
struct VehicleOverviewRows: View {
    @Environment(AppSettings.self) private var settings
    let vehicle: Vehicle

    private var summary: Summary {
        let fallback = vehicle.powerType == .ev ? settings.defaultElectricityRate : nil
        let segments = MileageCalculator.segments(from: vehicle.fuelEntries.map(\.record), fallbackCostPerUnit: fallback)
        return MileageCalculator.summary(of: segments)
    }

    var body: some View {
        let summary = summary
        if let odometer = vehicle.currentOdometer {
            LabeledContent("Odometer", value: "\(odometer.formatted(.number.precision(.fractionLength(0)))) mi")
        }
        if let first = vehicle.firstOdometer, let current = vehicle.currentOdometer, current > first {
            LabeledContent("Tracked", value: "\((current - first).formatted(.number.precision(.fractionLength(0)))) mi")
        }
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
