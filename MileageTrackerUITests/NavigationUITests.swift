import XCTest

final class NavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Dashboard → Vehicles → (tap a vehicle) must show that vehicle's details, not the list again.
    func testVehicleListRowOpensVehicleDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["-UITestInMemory"]
        app.launch()

        let name = "Navtest \(Int.random(in: 1000...9999))"
        app.buttons["Add Vehicle"].firstMatch.tap()
        let nameField = app.textFields["Name (e.g. Daily Driver)"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        app.buttons["Save"].tap()

        let vehiclesTile = app.buttons["Vehicles"].firstMatch
        XCTAssertTrue(vehiclesTile.waitForExistence(timeout: 5))
        vehiclesTile.tap()

        let row = app.buttons[name].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "vehicle row missing from list")
        row.tap()

        // The detail screen has an Overview section and the vehicle's name as the title.
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 5),
                      "expected vehicle detail, got: \(app.navigationBars.allElementsBoundByIndex.map(\.identifier))")
        XCTAssertTrue(app.staticTexts["Overview"].exists)
    }
}
