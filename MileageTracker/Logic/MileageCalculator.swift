import Foundation

struct EnergyRecord: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let odometer: Double
    let quantity: Double
    let totalCost: Double?
    /// Gas price ($/gal) stamped when the entry was logged. Nil for entries from before stamping existed.
    var gasPrice: Double? = nil
    /// $/kWh stamped for EV entries logged without a cost.
    var electricityRate: Double? = nil
}

/// Miles driven between the previous entry and this one, and the energy added at this one.
/// Assumes each fill-up/charge tops the vehicle back up to the same level (fill-to-full).
struct Segment: Identifiable, Equatable {
    let record: EnergyRecord
    let miles: Double
    /// Actual cost, or quantity * fallback rate when none was entered.
    let cost: Double?
    /// Gas price to compare against: the stamp, else the fallback for unstamped entries.
    var gasPrice: Double? = nil

    var id: UUID { record.id }
    var milesPerUnit: Double { miles / record.quantity }
    var costPerMile: Double? { cost.map { $0 / miles } }
}

struct Summary: Equatable {
    var miles: Double = 0
    var quantity: Double = 0
    var costedMiles: Double = 0
    var cost: Double = 0
    /// Gallons a gas car would have burned to spend `cost`, each segment priced at its own stamped gas price.
    var gasEquivalentGallons: Double = 0
    var gasEquivalentMiles: Double = 0

    /// Effective MPG using each entry's stamped gas price, not today's.
    var effectiveMPG: Double? { gasEquivalentGallons > 0 ? gasEquivalentMiles / gasEquivalentGallons : nil }

    var milesPerUnit: Double? { quantity > 0 ? miles / quantity : nil }
    var costPerMile: Double? { costedMiles > 0 ? cost / costedMiles : nil }
}

enum MileageCalculator {
    /// `fallbackCostPerUnit` and `fallbackGasPrice` only apply to entries with no stamp of their own.
    static func segments(from records: [EnergyRecord], fallbackCostPerUnit: Double?,
                         fallbackGasPrice: Double? = nil) -> [Segment] {
        let sorted = records.sorted { ($0.odometer, $0.date) < ($1.odometer, $1.date) }
        var result: [Segment] = []
        for (previous, current) in zip(sorted, sorted.dropFirst()) {
            let miles = current.odometer - previous.odometer
            guard miles > 0, current.quantity > 0 else { continue }
            let rate = current.electricityRate ?? fallbackCostPerUnit
            let cost = current.totalCost ?? rate.map { $0 * current.quantity }
            result.append(Segment(record: current, miles: miles, cost: cost,
                                  gasPrice: current.gasPrice ?? fallbackGasPrice))
        }
        return result
    }

    static func summary(of segments: [Segment]) -> Summary {
        segments.reduce(into: Summary()) { total, segment in
            total.miles += segment.miles
            total.quantity += segment.record.quantity
            if let cost = segment.cost {
                total.cost += cost
                total.costedMiles += segment.miles
                if cost > 0, let price = segment.gasPrice, price > 0 {
                    total.gasEquivalentGallons += cost / price
                    total.gasEquivalentMiles += segment.miles
                }
            }
        }
    }

    /// The MPG a gasoline car would need to match this cost per mile at `gasPrice` dollars/gallon.
    static func effectiveMPG(costPerMile: Double?, gasPrice: Double?) -> Double? {
        guard let costPerMile, costPerMile > 0, let gasPrice, gasPrice > 0 else { return nil }
        return gasPrice / costPerMile
    }
}
