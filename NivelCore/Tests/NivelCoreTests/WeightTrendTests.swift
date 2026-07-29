import XCTest
@testable import NivelCore

final class WeightTrendTests: XCTestCase {
    func testSmoothExactValues() {
        // Moyenne mobile exponentielle α = 0,25 :
        // trend[0] = 80 ; 80 + 0.25×(82−80) = 80.5 ; 80.5 + 0.25×(79−80.5) = 80.125
        XCTAssertEqual(WeightTrend.smooth([80, 82, 79]), [80, 80.5, 80.125])
    }

    func testSmoothEmpty() {
        XCTAssertEqual(WeightTrend.smooth([]), [])
    }
}
