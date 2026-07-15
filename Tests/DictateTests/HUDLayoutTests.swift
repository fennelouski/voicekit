//
//  HUDLayoutTests.swift
//  DictateTests
//
//  Where the pill lands: the 3×3 anchor grid, and the panel geometry that has to keep it
//  on screen no matter the anchor or the type size.
//

import AppKit
import Testing
@testable import Dictate

@Suite struct HUDLayoutTests {
    /// A 1440×900 screen with the menu bar already excluded, like `visibleFrame` gives you.
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)

    @Test func everyGridSlotRoundTrips() {
        for position in HUDPosition.allCases {
            #expect(HUDPosition.at(row: position.row, column: position.column) == position)
        }
        #expect(HUDPosition.allCases.count == 9)
    }

    /// The whole point of the feature: an edge-anchored pill must stay on screen.
    @Test func panelStaysOnScreenAtEveryAnchor() {
        let size = HUDAppearance().panelSize
        for position in HUDPosition.allCases {
            let origin = HUDController.origin(for: position, in: screen, panel: size)
            #expect(origin.x >= screen.minX, "\(position) ran off the left")
            #expect(origin.x + size.width <= screen.maxX, "\(position) ran off the right")
            #expect(origin.y >= screen.minY, "\(position) ran off the bottom")
            #expect(origin.y + size.height <= screen.maxY, "\(position) ran off the top")
        }
    }

    @Test func anchorsLandOnTheSideTheyName() {
        let size = HUDAppearance().panelSize
        let left = HUDController.origin(for: .bottomLeft, in: screen, panel: size)
        let centre = HUDController.origin(for: .bottomCenter, in: screen, panel: size)
        let right = HUDController.origin(for: .bottomRight, in: screen, panel: size)
        #expect(left.x < centre.x)
        #expect(centre.x < right.x)

        let top = HUDController.origin(for: .topCenter, in: screen, panel: size)
        let middle = HUDController.origin(for: .center, in: screen, panel: size)
        #expect(centre.y < middle.y)
        #expect(middle.y < top.y)
    }

    /// Edge-anchored pills grow toward the centre, so they hug the edge they're anchored to.
    @Test func pillHugsItsEdgeAndGrowsInward() {
        #expect(HUDAppearance(position: .bottomLeft).pillAlignment == .leading)
        #expect(HUDAppearance(position: .topRight).pillAlignment == .trailing)
        #expect(HUDAppearance(position: .bottomCenter).pillAlignment == .center)
        // The middle column has no edge to hug, so it stays symmetric.
        #expect(HUDAppearance(position: .center).pillAlignment == .center)
    }

    /// The preview stands in for a whole screen, so it has to move the pill in *both* axes —
    /// `pillAlignment` deliberately drops the vertical, which is the panel's job.
    @Test func screenAlignmentMovesVerticallyWherePillAlignmentDoesNot() {
        #expect(HUDAppearance(position: .topCenter).screenAlignment == .top)
        #expect(HUDAppearance(position: .bottomCenter).screenAlignment == .bottom)
        #expect(HUDAppearance(position: .topLeft).screenAlignment == .topLeading)
        #expect(HUDAppearance(position: .bottomRight).screenAlignment == .bottomTrailing)
        #expect(HUDAppearance(position: .center).screenAlignment == .center)

        // Every row must land somewhere different, or the preview looks frozen — which is
        // exactly the bug this replaced.
        let top = HUDAppearance(position: .topCenter).screenAlignment.vertical
        let middle = HUDAppearance(position: .center).screenAlignment.vertical
        let bottom = HUDAppearance(position: .bottomCenter).screenAlignment.vertical
        #expect(top != middle)
        #expect(middle != bottom)
        #expect(top != bottom)
    }

    /// Bigger type needs a taller panel, or the pill gets clipped.
    @Test func panelGrowsWithTextSize() {
        let small = HUDAppearance(textSize: .small).panelSize.height
        let medium = HUDAppearance(textSize: .medium).panelSize.height
        let huge = HUDAppearance(textSize: .extraLarge).panelSize.height
        #expect(small < medium)
        #expect(medium < huge)
        // Room for the glow to bloom past the pill on both sides.
        #expect(HUDAppearance().panelSize.height > HUDAppearance().pillHeight)
        #expect(HUDAppearance().panelSize.width > HUDAppearance().pillMaxWidth)
    }

    /// `.instant` has to mean no animation at all, not a very short one — HUDView keys off zero.
    @Test func instantIsTheOnlyZeroSpeed() {
        #expect(HUDSpeed.instant.seconds == 0)
        for speed in HUDSpeed.allCases where speed != .instant {
            #expect(speed.seconds > 0)
        }
        // The default transition sits in the 200–350ms band that reads as motion, not a flash.
        #expect(HUDSpeed.normal.seconds >= 0.2 && HUDSpeed.normal.seconds <= 0.35)
        #expect(HUDSpeed.slowMo.seconds > HUDSpeed.slow.seconds)
    }
}
