import XCTest
@testable import FindPhoneKit

/// The advertisement parser and the kind labels built on it. Everything here
/// is pure: no radio, so it runs anywhere.
final class ContinuityTests: XCTestCase {
    /// 4c 00, then type-length-value records.
    private func apple(_ bytes: [UInt8]) -> Data { Data([0x4C, 0x00] + bytes) }

    func testSplitsRecordsInOrder() {
        // Handoff (4 bytes) followed by Nearby Info (2 bytes).
        let data = apple([0x0C, 0x04, 0x01, 0x02, 0x03, 0x04, 0x10, 0x02, 0xAA, 0xBB])
        let records = Continuity.records(data)

        XCTAssertEqual(Set(records.keys), [0x0C, 0x10])
        XCTAssertEqual([UInt8](records[0x0C]!), [0x01, 0x02, 0x03, 0x04])
        XCTAssertEqual([UInt8](records[0x10]!), [0xAA, 0xBB])
    }

    func testIgnoresOtherManufacturers() {
        // Same shape, Samsung's company identifier.
        XCTAssertTrue(Continuity.records(Data([0x75, 0x00, 0x0C, 0x02, 0x01, 0x02])).isEmpty)
        XCTAssertTrue(Continuity.records(Data([0x4C])).isEmpty)
    }

    /// A length that runs past the end of the packet is the shape a truncated
    /// advertisement takes, and it must not read off the end.
    func testToleratesTruncatedRecords() {
        let records = Continuity.records(apple([0x07, 0x40, 0x01, 0x0E, 0x20]))
        XCTAssertEqual([UInt8](records[0x07] ?? Data()), [0x01, 0x0E, 0x20])
    }

    func testNamesUnknownTypesRatherThanDroppingThem() {
        XCTAssertEqual(Continuity.name(for: 0x0C), "Handoff")
        XCTAssertEqual(Continuity.name(for: 0x77), "type-0x77")
    }

    func testProximityPairingReadsTheModel() {
        XCTAssertEqual(ProximityPairing.model(Data([0x01, 0x0E, 0x20])), "AirPods Pro")
        // An unrecognised model keeps its hex so the table can be extended
        // rather than guessed at.
        XCTAssertEqual(ProximityPairing.model(Data([0x01, 0xAB, 0xCD])),
                       "AirPods/Beats (model ABCD)")
        XCTAssertNil(ProximityPairing.model(Data([0x01])))
    }
}

final class DeviceKindTests: XCTestCase {
    private func kind(_ types: Set<UInt8>, findMy: Bool = false,
                      name: String? = nil) -> DeviceKind {
        DeviceKind.infer(types: types, hasFindMyService: findMy, name: name)
    }

    func testMessagesThatOnlyOneKindSends() {
        XCTAssertEqual(kind([0x07, 0x10]), .airPods)        // proximity pairing
        XCTAssertEqual(kind([0x0B, 0x10]), .watch)          // wrist state
        XCTAssertEqual(kind([0x0E, 0x10]), .phone)          // offers a hotspot
        XCTAssertEqual(kind([0x09, 0x06]), .tv)             // AirPlay target only
        XCTAssertEqual(kind([0x0D]), .computer)             // wants someone's hotspot
    }

    func testFindMyIsOnlyATagWhenItIsAllTheDeviceSays() {
        XCTAssertEqual(kind([0x12]), .findMy)
        XCTAssertEqual(kind([], findMy: true), .findMy)
        // An Apple device out of touch with its owner also advertises here,
        // so anything else alongside it means it is not a tag.
        XCTAssertEqual(kind([0x12, 0x10]), .apple)
    }

    func testNameWinsOverInference() {
        XCTAssertEqual(kind([0x10], name: "Justin's AirPods Pro"), .airPods)
        XCTAssertEqual(kind([0x0E], name: "Justin's MacBook Air"), .computer)
    }

    func testNothingAppleIsNotClaimedAsApple() {
        XCTAssertEqual(kind([]), .other)
    }
}

final class HapticRampTests: XCTestCase {
    func testStaysSilentUntilTheDeviceIsInTheRoom() {
        XCTAssertNil(HapticRamp.intensity(for: -90))
        XCTAssertNil(HapticRamp.intensity(for: HapticRamp.floor - 1))
        XCTAssertNotNil(HapticRamp.intensity(for: HapticRamp.floor))
    }

    func testStrengthensTowardsTheDeviceAndStaysInRange() {
        let near = HapticRamp.intensity(for: -50)!
        let far = HapticRamp.intensity(for: -70)!
        XCTAssertGreaterThan(near, far)
        for rssi in -72...(-20) {
            let value = HapticRamp.intensity(for: rssi)!
            XCTAssertGreaterThanOrEqual(value, 0.35)
            XCTAssertLessThanOrEqual(value, 1.0)
        }
    }

    func testTurnsSolidOnlyAtArmsReach() {
        XCTAssertFalse(HapticRamp.isSolid(-46))
        XCTAssertTrue(HapticRamp.isSolid(-45))
        XCTAssertTrue(HapticRamp.isSolid(-30))
    }

    /// The buzz thresholds and the words on screen are the same numbers, and
    /// this is what keeps them that way.
    func testThresholdsMatchTheBandsOnScreen() {
        XCTAssertEqual(Proximity.describe(HapticRamp.floor), "same room")
        XCTAssertEqual(Proximity.describe(HapticRamp.solid), "ARM'S REACH")
    }
}

final class ClickCadenceTests: XCTestCase {
    func testClicksSpeedUpAsTheSignalRisesAndThenStop() {
        XCTAssertGreaterThan(ClickCadence.interval(for: -90), ClickCadence.interval(for: -60))
        XCTAssertEqual(ClickCadence.interval(for: -40), ClickCadence.fastest, accuracy: 0.0001)
        XCTAssertEqual(ClickCadence.interval(for: -120), ClickCadence.slowest, accuracy: 0.0001)
    }
}
