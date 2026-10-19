//
//  StopBikeshareLoader.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import OBAKitCore

/// Loads the bikeshare docks near a stop for the stop page's last-mile card,
/// at most once a minute per stop (Lyft's feed TTL is 60 s). Failures leave the
/// card hidden: the departures are the page.
final class StopBikeshareLoader {
    private let onLoad: ([BikeshareDock]) -> Void

    /// The in-flight load; held for cancellation and so tests can await it.
    private(set) var task: Task<Void, Never>?
    private var requestedStopID: StopID?
    private var lastLoadedAt: Date?
    private let minimumReloadInterval: TimeInterval
    private let now: () -> Date

    init(minimumReloadInterval: TimeInterval = 60, now: @escaping () -> Date = Date.init, onLoad: @escaping ([BikeshareDock]) -> Void) {
        self.minimumReloadInterval = minimumReloadInterval
        self.now = now
        self.onLoad = onLoad
    }

    isolated deinit {
        task?.cancel()
    }

    func refresh(for stop: Stop, client: BikeshareClient?) {
        if stop.id == requestedStopID {
            if lastLoadedAt == nil { return } // first load still in flight
            if let lastLoadedAt, now().timeIntervalSince(lastLoadedAt) < minimumReloadInterval { return }
        }
        task?.cancel()
        requestedStopID = stop.id
        lastLoadedAt = nil

        guard let client else {
            onLoad([])
            return
        }

        let coordinate = stop.coordinate
        task = Task { [weak self] in
            let docks = (try? await client.nearbyDocks(to: coordinate)) ?? []
            guard !Task.isCancelled, let self else { return }
            self.onLoad(docks)
            self.lastLoadedAt = self.now()
            if docks.isEmpty {
                self.requestedStopID = nil
            }
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        requestedStopID = nil
        lastLoadedAt = nil
        onLoad([])
    }
}
