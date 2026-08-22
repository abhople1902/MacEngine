//
//  ChartWindowTests.swift
//  MacEngineTests
//
//  The history chart's axis is a fixed-width window, so the two things worth
//  pinning down are that it does not move while the trace is still filling it,
//  and that it does move once the trace has run out of room.
//

import Foundation
import Testing
@testable import MacEngine

@Suite("Chart window")
struct ChartWindowTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("Stands still while the first window is filling")
    func anchorsToTheFirstSample() {
        let domain = ChartWindow.domain(first: start, last: start.addingTimeInterval(20))

        #expect(domain == start...start.addingTimeInterval(ChartWindow.length))
    }

    @Test("Slides once the window is full")
    func slidesAfterTheWindowFills() {
        let last = start.addingTimeInterval(95)
        let domain = ChartWindow.domain(first: start, last: last)

        #expect(domain == last.addingTimeInterval(-ChartWindow.length)...last)
    }

    @Test("Is always exactly one window wide")
    func keepsAConstantWidth() {
        let widths = [0.0, 30.0, 60.0, 61.0, 600.0].map { elapsed in
            let domain = ChartWindow.domain(first: start, last: start.addingTimeInterval(elapsed))
            return domain.upperBound.timeIntervalSince(domain.lowerBound)
        }

        #expect(widths.allSatisfy { $0 == ChartWindow.length })
    }

    @Test("Opens a full window before the first sample arrives")
    func handlesAnEmptyHistory() {
        let domain = ChartWindow.domain(first: nil, last: nil, now: start)

        #expect(domain == start...start.addingTimeInterval(ChartWindow.length))
    }
}
