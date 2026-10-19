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
/// once per stop. Failures leave the card hidden: the departures are the page.
final class StopBikeshareLoader {
    private let onLoad: ([BikeshareDock]) -> Void

    /// The in-flight load; held for cancellation and so tests can await it.
    private(set) var task: Task<Void, Never>?
    private var requestedStopID: StopID?

    init(onLoad: @escaping ([BikeshareDock]) -> Void) {
        self.onLoad = onLoad
    }

    isolated deinit {
        task?.cancel()
    }

    func refresh(for stop: Stop, client: BikeshareClient?) {
        guard stop.id != requestedStopID else { return }
        task?.cancel()
        requestedStopID = stop.id

        guard let client else {
            onLoad([])
            return
        }

        let coordinate = stop.coordinate
        task = Task { [weak self] in
            let docks = (try? await client.nearbyDocks(to: coordinate)) ?? []
            guard !Task.isCancelled, let self else { return }
            self.onLoad(docks)
            if docks.isEmpty {
                self.requestedStopID = nil
            }
        }
    }

    func clear() {
        task?.cancel()
        task = nil
        requestedStopID = nil
        onLoad([])
    }
}
