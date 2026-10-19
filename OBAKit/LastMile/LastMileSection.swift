//
//  LastMileSection.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit
import OBAKitCore
import SwiftUI

/// The stop page's last-mile card: the bikeshare docks closest to the stop,
/// with live bike counts. Tapping a dock opens the operator's unlock link.
struct LastMileSection: View {
    let systemName: String
    let docks: [BikeshareDock]
    let onSelect: (BikeshareDock) -> Void

    static let lyftPink = Color(red: 1, green: 0, blue: 0.749)

    static func accessibilityIdentifier(for dock: BikeshareDock) -> String {
        "last_mile.dock.\(dock.id)"
    }

    /// "58 e-bikes · 7 classic · 11 open docks"
    static func availabilityText(for dock: BikeshareDock) -> String {
        let format = OBALoc("last_mile.availability_fmt", value: "%1$d e-bikes · %2$d classic · %3$d open docks", comment: "Bikeshare dock availability on the stop page's last-mile card. %1$d e-bikes, %2$d classic bikes, %3$d empty docks.")
        return String(format: format, dock.eBikes, dock.classicBikes, dock.openDocks)
    }

    static func distanceText(for dock: BikeshareDock) -> String {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter.string(fromDistance: dock.distanceMeters)
    }

    var body: some View {
        StopPageTintedCard(tint: Self.lyftPink) {
            StopPageCardHeader(
                systemImage: "bicycle",
                title: String(format: OBALoc("last_mile.title_fmt", value: "Last mile · %@", comment: "Header of the stop page's bikeshare card. %@ is the bikeshare system, e.g. Citi Bike."), systemName),
                tint: Self.lyftPink
            )
            .accessibilityAddTraits(.isHeader)
            ForEach(docks) { dock in
                StopPageCardDivider()
                StopPageCardRow {
                    onSelect(dock)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(dock.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(Self.distanceText(for: dock))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text(Self.availabilityText(for: dock))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint(OBALoc("last_mile.unlock_hint", value: "Opens Lyft to unlock a bike", comment: "VoiceOver hint on a dock row of the last-mile card."))
                .accessibilityIdentifier(Self.accessibilityIdentifier(for: dock))
            }
        }
    }
}
