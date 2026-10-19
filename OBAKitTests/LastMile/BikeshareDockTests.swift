//
//  BikeshareDockTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The Citi Bike fixtures are three real docks near Grand Central. Park Ave & E 42 St
/// is the closest; E 47 St & Park Ave is marked not renting.
@Suite
struct BikeshareDockTests {
    /// The M42 stop at E 42 St & Park Ave (MTA_403459).
    static let grandCentralStop = CLLocationCoordinate2D(latitude: 40.75201, longitude: -73.97733)
    static let parkAve42ID = "66dc8025-0aca-11e7-82f6-3863bb44ef7c"
    static let notRentingID = "66dbc982-0aca-11e7-82f6-3863bb44ef7c"

    static func fixtures() throws -> ([GBFSStationInformation], [GBFSStationStatus]) {
        let info = try JSONDecoder().decode(GBFSResponse<GBFSStations<GBFSStationInformation>>.self, from: Fixtures.loadData(file: "gbfs_citibike_station_information.json"))
        let status = try JSONDecoder().decode(GBFSResponse<GBFSStations<GBFSStationStatus>>.self, from: Fixtures.loadData(file: "gbfs_citibike_station_status.json"))
        return (info.data.stations, status.data.stations)
    }

    @Test func `Nearest dock comes first`() throws {
        let (stations, statuses) = try Self.fixtures()
        let docks = BikeshareDock.nearest(to: Self.grandCentralStop, stations: stations, statuses: statuses, within: 2_000, limit: 5)

        let first = try #require(docks.first)
        #expect(first.id == Self.parkAve42ID)
        #expect(first.name == "Park Ave & E 42 St")
        #expect(first.eBikes == 58)
        #expect(first.openDocks == 11)
        #expect(first.rentalURL == URL(string: "https://bkn.lft.to/lastmile_qr_scan"))
        #expect(docks.map(\.distanceMeters) == docks.map(\.distanceMeters).sorted())
    }

    @Test func `Docks that are not renting are skipped`() throws {
        let (stations, statuses) = try Self.fixtures()
        let docks = BikeshareDock.nearest(to: Self.grandCentralStop, stations: stations, statuses: statuses, within: 2_000, limit: 5)
        #expect(!docks.contains { $0.id == Self.notRentingID })
    }

    @Test func `Docks beyond the radius are skipped`() throws {
        let (stations, statuses) = try Self.fixtures()
        let docks = BikeshareDock.nearest(to: Self.grandCentralStop, stations: stations, statuses: statuses, within: 100, limit: 5)
        #expect(docks.map(\.id) == [Self.parkAve42ID])
    }

    @Test func `Client fetches both feeds and joins them`() async throws {
        let loader = MockDataLoader(testName: "BikeshareClient")
        loader.mock(data: Fixtures.loadData(file: "gbfs_citibike_station_information.json")) { $0.url?.lastPathComponent == "station_information.json" }
        loader.mock(data: Fixtures.loadData(file: "gbfs_citibike_station_status.json")) { $0.url?.lastPathComponent == "station_status.json" }

        let docks = try await BikeshareClient(system: .citiBike, dataLoader: loader).nearbyDocks(to: Self.grandCentralStop)
        #expect(docks.first?.id == Self.parkAve42ID)
        #expect(docks.first?.eBikes == 58)
    }

    @Test func `Only MTA New York maps to Citi Bike`() {
        #expect(BikeshareSystem.system(forRegionIdentifier: 2) == .citiBike)
        #expect(BikeshareSystem.system(forRegionIdentifier: 1) == nil)
    }
}

@MainActor
@Suite(.serialized)
final class StopBikeshareLoaderTests: OBATestCase {
    @Test func `Same stop reloads once the feed TTL has passed, not before`() async throws {
        let stop = try Fixtures.loadSomeStops().first!
        // Move the fixture docks onto the stop so the load returns docks: an
        // empty result is retried on the next refresh by design.
        var info = try #require(JSONSerialization.jsonObject(with: Fixtures.loadData(file: "gbfs_citibike_station_information.json")) as? [String: Any])
        var data = try #require(info["data"] as? [String: Any])
        data["stations"] = (data["stations"] as? [[String: Any]] ?? []).map { station in
            var station = station
            station["lat"] = stop.coordinate.latitude
            station["lon"] = stop.coordinate.longitude
            return station
        }
        info["data"] = data

        let loader = MockDataLoader(testName: "StopBikeshareLoader")
        loader.mock(data: try JSONSerialization.data(withJSONObject: info)) { $0.url?.lastPathComponent == "station_information.json" }
        loader.mock(data: Fixtures.loadData(file: "gbfs_citibike_station_status.json")) { $0.url?.lastPathComponent == "station_status.json" }
        let client = BikeshareClient(system: .citiBike, dataLoader: loader)

        var clock = Date(timeIntervalSince1970: 0)
        var loads = 0
        let subject = StopBikeshareLoader(now: { clock }) { _ in loads += 1 }

        subject.refresh(for: stop, client: client)
        await subject.task?.value
        subject.refresh(for: stop, client: client)
        await subject.task?.value
        clock.addTimeInterval(30)
        subject.refresh(for: stop, client: client)
        await subject.task?.value
        #expect(loads == 1)

        clock.addTimeInterval(31)
        subject.refresh(for: stop, client: client)
        await subject.task?.value
        #expect(loads == 2)
    }
}
