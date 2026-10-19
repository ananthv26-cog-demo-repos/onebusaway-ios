//
//  LastMileSectionHammerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Hammer
import SwiftUI
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// Drives the last-mile card with real synthesized touches (lyft/Hammer), so the
/// test goes through hit-testing and the SwiftUI button exactly as a finger does.
@MainActor
@Suite(.serialized)
struct LastMileSectionHammerTests {

    private func parkAve42() throws -> BikeshareDock {
        let (stations, statuses) = try BikeshareDockTests.fixtures()
        return try #require(BikeshareDock.nearest(to: BikeshareDockTests.grandCentralStop, stations: stations, statuses: statuses).first)
    }

    /// SwiftUI rows are accessibility elements, not views, so Hammer's identifier
    /// lookup can't see them; find the element's on-screen frame instead.
    private func accessibilityFrame(of identifier: String, in root: NSObject) -> CGRect? {
        if (root.value(forKey: "accessibilityIdentifier") as? String) == identifier {
            return root.accessibilityFrame
        }
        var children: [NSObject] = (root.accessibilityElements as? [NSObject]) ?? []
        if children.isEmpty {
            let count = root.accessibilityElementCount()
            if count > 0, count != NSNotFound {
                children = (0..<count).compactMap { root.accessibilityElement(at: $0) as? NSObject }
            }
        }
        if let view = root as? UIView {
            children += view.subviews
        }
        for child in children {
            if let frame = accessibilityFrame(of: identifier, in: child) { return frame }
        }
        return nil
    }

    @Test func `Card shows the dock's rentable bikes, not the disabled ones`() throws {
        let dock = try parkAve42()
        #expect(LastMileSection.availabilityText(for: dock) == "58 e-bikes · 7 classic · 11 open docks")
    }

    @Test func `Tapping a dock opens Lyft's unlock link for that dock`() async throws {
        let dock = try parkAve42()
        var opened: BikeshareDock?
        let host = UIHostingController(rootView:
            List {
                LastMileSection(systemName: "Citi Bike", docks: [dock], onSelect: { opened = $0 })
            }
            .listStyle(.plain)
        )

        let eventGenerator = try await EventGenerator(viewController: host)
        let identifier = LastMileSection.accessibilityIdentifier(for: dock)
        try await eventGenerator.waitUntil(self.accessibilityFrame(of: identifier, in: host.view) != nil, timeout: 3)

        let frame = try #require(accessibilityFrame(of: identifier, in: host.view))
        try await eventGenerator.fingerTap(at: CGPoint(x: frame.midX, y: frame.midY))
        try await eventGenerator.wait(0.3)
        try await eventGenerator.finish()

        #expect(opened?.id == dock.id)
        #expect(opened?.rentalURL == URL(string: "https://bkn.lft.to/lastmile_qr_scan"))
    }
}
