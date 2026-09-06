import STedCore
import XCTest

final class PerformanceProbeTests: XCTestCase {
    func testTrackerRowsScaleWithLongChordInput() {
        let short = makeChordTrack(count: 1_000)
        let long = makeChordTrack(count: 2_000)

        _ = short.eventRows(timeBase: 48, beatNumerator: 4, beatDenominator: 4)
        _ = long.eventRows(timeBase: 48, beatNumerator: 4, beatDenominator: 4)

        let shortTime = elapsed {
            _ = short.eventRows(timeBase: 48, beatNumerator: 4, beatDenominator: 4)
        }
        let longTime = elapsed {
            _ = long.eventRows(timeBase: 48, beatNumerator: 4, beatDenominator: 4)
        }
        let ratio = longTime / max(shortTime, 1e-9)

        XCTAssertLessThan(
            ratio,
            3.2,
            "Tracker row generation should not grow quadratically with a chord-heavy track"
        )
    }

    func testTrackStepCountScalesWithLongChordInput() {
        let short = makeChordTrack(count: 4_000)
        let long = makeChordTrack(count: 8_000)

        _ = short.stepCount
        _ = long.stepCount

        let shortTime = elapsed { _ = short.stepCount }
        let longTime = elapsed { _ = long.stepCount }
        let ratio = longTime / max(shortTime, 1e-9)

        XCTAssertLessThan(
            ratio,
            3.2,
            "Track list statistics should not grow quadratically with a chord-heavy track"
        )
    }

    private func makeChordTrack(count: Int) -> Track {
        var events = Array(
            repeating: TrackEvent(command: 60, delay: 0, param1: 36, param2: 100),
            count: count
        )
        events.append(TrackEvent(command: 60, delay: 1, param1: 1, param2: 100))
        events.append(TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0))
        return Track(id: 0, number: 1, events: events)
    }

    private func elapsed(_ work: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        work()
        let end = DispatchTime.now().uptimeNanoseconds
        return Double(end - start) / 1_000_000_000
    }
}
