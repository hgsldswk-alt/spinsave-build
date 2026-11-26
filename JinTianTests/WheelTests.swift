import XCTest

final class WheelTests: XCTestCase {
    func testIntegerAndDecimalBounds() {
        var rng = SeededRandom(state: 73)
        for config in [WheelConfig(minimumCents: 0, maximumCents: 20000), WheelConfig(minimumCents: 123, maximumCents: 987, integersOnly: false)] {
            var sawFraction = false
            for _ in 0..<10000 {
                let amount = config.spin(using: &rng)
                XCTAssertTrue((config.minimumCents...config.maximumCents).contains(amount))
                if config.integersOnly { XCTAssertEqual(amount % 100, 0) }
                if amount % 100 != 0 { sawFraction = true }
            }
            if !config.integersOnly { XCTAssertTrue(sawFraction) }
        }
    }
    func testDegenerateRangeAndInvalidRange() {
        var rng = SeededRandom(state: 1)
        XCTAssertEqual(WheelConfig(minimumCents: 0, maximumCents: 0).spin(using: &rng), 0)
        XCTAssertEqual(WheelConfig(minimumCents: 321, maximumCents: 321, integersOnly: false).spin(using: &rng), 321)
        XCTAssertFalse(WheelConfig(minimumCents: 101, maximumCents: 200).isValid)
        XCTAssertFalse(WheelConfig(minimumCents: 200, maximumCents: 100).isValid)
        XCTAssertFalse(WheelConfig(minimumCents: -100).isValid)
    }
    func testLowPressureDistributionIsSmallerWithFixedSeed() {
        let uniform = WheelConfig(minimumCents: 0, maximumCents: 10000, lowPressure: false)
        var pressure = uniform; pressure.lowPressure = true
        var a = SeededRandom(state: 12345), b = SeededRandom(state: 12345)
        var sumUniform = 0, sumPressure = 0, small = 0
        for _ in 0..<20000 {
            sumUniform += uniform.spin(using: &a)
            let draw = pressure.spin(using: &b)
            sumPressure += draw
            if draw < 5000 { small += 1 }
        }
        XCTAssertTrue((4800...5200).contains(sumUniform / 20000))
        XCTAssertTrue((3100...3500).contains(sumPressure / 20000))
        XCTAssertGreaterThan(small, 14000)
    }
    func testBothEndpointsRemainReachable() {
        var rng = SeededRandom(state: 9)
        let config = WheelConfig(minimumCents: 100, maximumCents: 200, lowPressure: true)
        let draws = Set((0..<1000).map { _ in config.spin(using: &rng) })
        XCTAssertEqual(draws, [100, 200])
    }
    func testInjectedSeedIsRepeatable() {
        var a = SeededRandom(state: 42), b = SeededRandom(state: 42)
        let config = WheelConfig()
        XCTAssertEqual((0..<100).map { _ in config.spin(using: &a) }, (0..<100).map { _ in config.spin(using: &b) })
    }
    func testEveryResultStopsInItsSector() {
        let config = WheelConfig(minimumCents: 100, maximumCents: 3000)
        for cents in stride(from: 100, through: 3000, by: 100) {
            let sector = config.sector(for: cents)
            XCTAssertTrue((0..<10).contains(sector))
            let center = -90.0 + Double(sector) * 36 + 18
            let stop = 1800.0 - Double(sector) * 36 - 18
            XCTAssertEqual((center + stop + 90).truncatingRemainder(dividingBy: 360), 0, accuracy: 0.001)
        }
    }

    func testSectorLabelsMatchLandingSectors() {
        let configs = [WheelConfig(), WheelConfig(minimumCents: 100, maximumCents: 1100),
                       WheelConfig(minimumCents: 0, maximumCents: 500), WheelConfig(minimumCents: 2000, maximumCents: 8000),
                       WheelConfig(minimumCents: 41, maximumCents: 782, integersOnly: false)]
        for config in configs {
            var seen = Set<Int>()
            for sector in 0..<10 {
                guard let b = config.bounds(sector) else { continue }
                var cents = b.low
                while cents <= b.high {
                    XCTAssertEqual(config.sector(for: cents), sector, "\(config) \(cents)")
                    seen.insert(cents); cents += config.step
                }
            }
            XCTAssertEqual(seen.count, (config.maximumCents - config.minimumCents) / config.step + 1)
        }
        XCTAssertEqual(WheelConfig().label(0), "+1~3")
        XCTAssertEqual(WheelConfig(minimumCents: 100, maximumCents: 1000).label(4), "+5")
    }

    func testCenteredRangeKeepsExpectationWhenCapped() throws {
        let wheel = try XCTUnwrap(SaveCore.centeredRange(remainingCents: Money.limit, days: 1))
        XCTAssertGreaterThanOrEqual(SaveCore.expectedDailyCents(wheel), Double(Money.limit))
    }
}
