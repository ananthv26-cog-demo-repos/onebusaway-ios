//
//  BikeshareDock.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import OBAKitCore

/// A Lyft-operated bikeshare system with a public GBFS 2.3 feed.
nonisolated struct BikeshareSystem: Equatable, Sendable {
    let name: String
    /// The directory holding `station_information.json` and `station_status.json`.
    let feedBaseURL: URL

    static let citiBike = BikeshareSystem(name: "Citi Bike", feedBaseURL: URL(string: "https://gbfs.lyft.com/gbfs/2.3/bkn/en/")!)

    /// The bikeshare system covering an OBA region, if there is one.
    static func system(forRegionIdentifier id: RegionIdentifier) -> BikeshareSystem? {
        switch id {
        case 2: return .citiBike // MTA New York
        default: return nil
        }
    }
}

/// A dock near a stop, with what a rider can take from it right now.
nonisolated struct BikeshareDock: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    let distanceMeters: CLLocationDistance
    let classicBikes: Int
    let eBikes: Int
    let openDocks: Int
    /// The operator's own unlock link, from the feed's `rental_uris.ios`.
    let rentalURL: URL?

    var availableBikes: Int { classicBikes + eBikes }

    /// Joins the two GBFS feeds and keeps the closest docks a rider can rent from.
    ///
    static func nearest(
        to coordinate: CLLocationCoordinate2D,
        stations: [GBFSStationInformation],
        statuses: [GBFSStationStatus],
        within radius: CLLocationDistance = 400,
        limit: Int = 2
    ) -> [BikeshareDock] {
        let statusByID = Dictionary(statuses.map { ($0.stationID, $0) }, uniquingKeysWith: { first, _ in first })
        let origin = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        let docks: [BikeshareDock] = stations.compactMap { station in
            guard let status = statusByID[station.stationID], status.isRenting else { return nil }
            let distance = origin.distance(from: CLLocation(latitude: station.lat, longitude: station.lon))
            guard distance <= radius else { return nil }

            let eBikes = status.numEbikesAvailable ?? 0
            let available = status.numBikesAvailable + (status.numBikesDisabled ?? 0)
            guard available > 0 else { return nil }

            return BikeshareDock(
                id: station.stationID,
                name: station.name,
                latitude: station.lat,
                longitude: station.lon,
                distanceMeters: distance,
                classicBikes: max(available - eBikes, 0),
                eBikes: eBikes,
                openDocks: status.numDocksAvailable,
                rentalURL: station.rentalURIs?.ios
            )
        }

        return Array(docks.sorted { $0.distanceMeters < $1.distanceMeters }.prefix(limit))
    }
}

// MARK: - GBFS 2.3 models

nonisolated struct GBFSResponse<Payload: Decodable & Sendable>: Decodable, Sendable {
    let data: Payload
}

nonisolated struct GBFSStations<Station: Decodable & Sendable>: Decodable, Sendable {
    let stations: [Station]
}

nonisolated struct GBFSStationInformation: Decodable, Sendable {
    struct RentalURIs: Decodable, Sendable {
        let ios: URL?
    }

    let stationID: String
    let name: String
    let lat: Double
    let lon: Double
    let rentalURIs: RentalURIs?

    enum CodingKeys: String, CodingKey {
        case stationID = "station_id", name, lat, lon, rentalURIs = "rental_uris"
    }
}

nonisolated struct GBFSStationStatus: Decodable, Sendable {
    let stationID: String
    let numBikesAvailable: Int
    let numEbikesAvailable: Int?
    let numBikesDisabled: Int?
    let numDocksAvailable: Int
    let isRenting: Bool

    enum CodingKeys: String, CodingKey {
        case stationID = "station_id"
        case numBikesAvailable = "num_bikes_available"
        case numEbikesAvailable = "num_ebikes_available"
        case numBikesDisabled = "num_bikes_disabled"
        case numDocksAvailable = "num_docks_available"
        case isRenting = "is_renting"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stationID = try c.decode(String.self, forKey: .stationID)
        numBikesAvailable = try c.decode(Int.self, forKey: .numBikesAvailable)
        numEbikesAvailable = try c.decodeIfPresent(Int.self, forKey: .numEbikesAvailable)
        numBikesDisabled = try c.decodeIfPresent(Int.self, forKey: .numBikesDisabled)
        numDocksAvailable = try c.decode(Int.self, forKey: .numDocksAvailable)
        // GBFS 2.3 says boolean; Lyft's feeds send 0/1.
        if let flag = try? c.decode(Bool.self, forKey: .isRenting) {
            isRenting = flag
        } else {
            isRenting = try c.decode(Int.self, forKey: .isRenting) != 0
        }
    }
}

// MARK: - Client

/// Fetches a system's station feeds and returns the docks nearest a coordinate.
nonisolated struct BikeshareClient: Sendable {
    let system: BikeshareSystem
    let dataLoader: any URLDataLoader

    func nearbyDocks(to coordinate: CLLocationCoordinate2D) async throws -> [BikeshareDock] {
        async let information: GBFSResponse<GBFSStations<GBFSStationInformation>> = fetch("station_information.json")
        async let status: GBFSResponse<GBFSStations<GBFSStationStatus>> = fetch("station_status.json")
        return try await BikeshareDock.nearest(to: coordinate, stations: information.data.stations, statuses: status.data.stations)
    }

    private func fetch<T: Decodable & Sendable>(_ file: String) async throws -> T {
        let url = system.feedBaseURL.appendingPathComponent(file)
        let (data, _) = try await dataLoader.data(for: URLRequest(url: url))
        return try JSONDecoder().decode(T.self, from: data)
    }
}
