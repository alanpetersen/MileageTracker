import XCTest
@testable import MileageTracker

final class MileageCalculatorTests: XCTestCase {
    private func record(_ odometer: Double, _ quantity: Double, cost: Double? = nil) -> EnergyRecord {
        EnergyRecord(id: UUID(), date: Date(timeIntervalSince1970: odometer), odometer: odometer,
                     quantity: quantity, totalCost: cost)
    }

    func testGasMPGIgnoresFirstEntryAndSortsByOdometer() {
        let records = [record(1300, 10), record(1000, 12), record(1150, 5)]
        let segments = MileageCalculator.segments(from: records, fallbackCostPerUnit: nil)
        XCTAssertEqual(segments.map(\.miles), [150, 150])
        let summary = MileageCalculator.summary(of: segments)
        XCTAssertEqual(summary.milesPerUnit!, 300 / 15, accuracy: 0.0001)
    }

    func testEVEffectiveMPGUsesGasPrice() {
        // 200 miles on 50 kWh at $0.20/kWh = $10 -> $0.05/mile. At $4/gal that's 80 effective MPG.
        let records = [record(0, 1), record(200, 50)]
        let segments = MileageCalculator.segments(from: records, fallbackCostPerUnit: 0.20)
        let summary = MileageCalculator.summary(of: segments)
        XCTAssertEqual(summary.costPerMile!, 0.05, accuracy: 0.0001)
        XCTAssertEqual(MileageCalculator.effectiveMPG(costPerMile: summary.costPerMile, gasPrice: 4.0)!, 80, accuracy: 0.0001)
    }

    func testEnteredCostBeatsFallbackRate() {
        let records = [record(0, 1), record(100, 25, cost: 5)]
        let segments = MileageCalculator.segments(from: records, fallbackCostPerUnit: 1.0)
        XCTAssertEqual(segments.first?.cost, 5)
    }

    func testNoCostMeansNoEffectiveMPG() {
        let segments = MileageCalculator.segments(from: [record(0, 1), record(100, 25)], fallbackCostPerUnit: nil)
        XCTAssertNil(MileageCalculator.summary(of: segments).costPerMile)
        XCTAssertNil(MileageCalculator.effectiveMPG(costPerMile: nil, gasPrice: 4))
    }

    func testNonIncreasingOdometerSkipped() {
        let segments = MileageCalculator.segments(from: [record(100, 5), record(100, 5)], fallbackCostPerUnit: nil)
        XCTAssertTrue(segments.isEmpty)
    }
}
