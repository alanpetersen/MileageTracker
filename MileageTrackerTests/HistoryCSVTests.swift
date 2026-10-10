import XCTest
import CoreData
@testable import MileageTracker

final class HistoryCSVTests: XCTestCase {
    func testQuotedFieldsRoundTrip() {
        let rows = [["a,b", "say \"hi\"", "line1\nline2", "plain"]]
        XCTAssertEqual(CSV.parse(CSV.encode(rows)), rows)
    }

    func testParseHandlesCRLFBOMAndBlankLines() {
        let parsed = CSV.parse("\u{FEFF}x,y\r\n1,2\r\n\r\n3,4")
        XCTAssertEqual(parsed, [["x", "y"], ["1", "2"], ["3", "4"]])
    }

    func testDecodeMinimalSpreadsheet() {
        let csv = "Vehicle,Date,Odometer,Gallons,Cost\nCivic,2026-01-05,1000,10,35.50\nCivic,1/12/2026,1300,,\n"
        let result = HistoryCSV.decode(csv)
        XCTAssertTrue(result.problems.isEmpty, "\(result.problems)")
        XCTAssertEqual(result.records.map(\.kind), [.fuel, .odometer])
        XCTAssertEqual(result.records[0].quantity, 10)
        XCTAssertEqual(result.records[0].totalCost, 35.5)
    }

    func testDecodeReportsBadRowsAndKeepsGoodOnes() {
        let csv = "vehicle,date,odometer,quantity\nCivic,not a date,100,5\nCivic,2026-01-01,abc,5\nCivic,2026-01-01,100,5\n,2026-01-01,100,5\nCivic,2026-01-01,100,0\n"
        let result = HistoryCSV.decode(csv)
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.problems.count, 4)
        XCTAssertTrue(result.problems[0].hasPrefix("Line 2"))
    }

    func testMissingRequiredColumns() {
        let result = HistoryCSV.decode("vehicle,quantity\nCivic,5\n")
        XCTAssertTrue(result.records.isEmpty)
        XCTAssertEqual(result.problems.count, 1)
    }

    func testExportDecodeRoundTripKeepsStampedPrices() {
        let record = HistoryRecord(kind: .fuel, vehicle: "Bolt, \"EV\"", powerType: .ev,
                                   date: Date(timeIntervalSince1970: 1_800_000_000), odometer: 12345.5, quantity: 40,
                                   totalCost: 7.25, gasPrice: 3.899, electricityRate: 0.1813, source: .camera,
                                   loggedBy: "Sam", id: UUID())
        let decoded = HistoryCSV.decode(HistoryCSV.encode([record]))
        XCTAssertTrue(decoded.problems.isEmpty)
        XCTAssertEqual(decoded.records, [record])
    }

    // MARK: Stamped prices

    func testEffectiveMPGUsesEachEntrysOwnGasPrice() {
        func charge(_ odo: Double, gas: Double?) -> EnergyRecord {
            EnergyRecord(id: UUID(), date: Date(timeIntervalSince1970: odo), odometer: odo, quantity: 50,
                         totalCost: 10, gasPrice: gas)
        }
        // Two 100-mile segments at $0.10/mi. Gas was $2 then $4 -> 20 and 40 mpg-equivalent.
        let segments = MileageCalculator.segments(from: [charge(0, gas: 3), charge(100, gas: 2), charge(200, gas: 4)],
                                                  fallbackCostPerUnit: nil, fallbackGasPrice: 99)
        let mpg = MileageCalculator.summary(of: segments).effectiveMPG!
        XCTAssertEqual(mpg, 200 / (10 / 2 + 10 / 4), accuracy: 0.0001)
    }

    func testUnstampedEntriesUseFallbackGasPrice() {
        let records = [EnergyRecord(id: UUID(), date: .now, odometer: 0, quantity: 1, totalCost: nil),
                       EnergyRecord(id: UUID(), date: .now, odometer: 100, quantity: 50, totalCost: 10)]
        let summary = MileageCalculator.summary(of: MileageCalculator.segments(from: records, fallbackCostPerUnit: nil, fallbackGasPrice: 4))
        XCTAssertEqual(summary.effectiveMPG!, 100 / (10 / 4), accuracy: 0.0001)
    }

    func testStampedElectricityRateBeatsCurrentDefault() {
        let records = [EnergyRecord(id: UUID(), date: .now, odometer: 0, quantity: 1, totalCost: nil),
                       EnergyRecord(id: UUID(), date: .now, odometer: 100, quantity: 10, totalCost: nil, electricityRate: 0.10)]
        let segments = MileageCalculator.segments(from: records, fallbackCostPerUnit: 0.50)
        XCTAssertEqual(segments.first?.cost ?? 0, 1.0, accuracy: 0.0001)
    }

    // MARK: Core Data import

    private func makeContext() -> (NSManagedObjectContext, Household) {
        let controller = PersistenceController(inMemory: true)
        let context = controller.viewContext
        let household = Household(context: context)
        return (context, household)
    }

    func testImportCreatesVehicleAndSkipsDuplicatesOnReimport() {
        let (context, household) = makeContext()
        let csv = "vehicle,date,odometer,quantity,gas_price\nCivic,2026-01-05,1000,10,3.5\nCivic,2026-01-12,1300,,\n"
        let records = HistoryCSV.decode(csv).records

        let first = HistoryTransfer.importRecords(records, into: household, context: context)
        XCTAssertEqual(first, .init(added: 2, duplicates: 0, vehiclesCreated: 1))
        let again = HistoryTransfer.importRecords(records, into: household, context: context)
        XCTAssertEqual(again, .init(added: 0, duplicates: 2, vehiclesCreated: 0))

        let vehicle = household.vehicles!.first!
        XCTAssertEqual(vehicle.entryList.first?.gasPrice, 3.5)
        XCTAssertEqual(vehicle.readingList.count, 1)
    }

    func testExportThenImportIntoFreshHouseholdRestoresEverything() {
        let (context, source) = makeContext()
        let csv = "vehicle,vehicle_type,date,odometer,quantity,total_cost,gas_price\nBolt,ev,2026-01-05,1000,40,8,3.9\n"
        HistoryTransfer.importRecords(HistoryCSV.decode(csv).records, into: source, context: context)
        let exported = HistoryCSV.encode(HistoryTransfer.records(for: Array(source.vehicles!)))

        let (context2, target) = makeContext()
        HistoryTransfer.importRecords(HistoryCSV.decode(exported).records, into: target, context: context2)
        let vehicle = target.vehicles!.first!
        XCTAssertEqual(vehicle.powerType, .ev)
        XCTAssertEqual(vehicle.entryList.first?.cost, 8)
        XCTAssertEqual(vehicle.entryList.first?.gasPrice, 3.9)
    }
}
