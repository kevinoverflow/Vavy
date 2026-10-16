import Foundation
import XCTest
@testable import Vavy

@MainActor
final class PitchEstimatorTests: XCTestCase {
    func testEstimatesSteadyToneWhenSubharmonicIsOutOfRange() throws {
        // At 110 Hz the subharmonic (55 Hz) is below minFrequency, so it cannot be chosen.
        let estimate = try XCTUnwrap(PitchEstimator.estimate(frame: TestAudio.frame(hz: 110), sampleRate: TestAudio.sampleRate, previousHz: nil))
        XCTAssertEqual(estimate, 110, accuracy: 1.1)
    }

    func testFollowsPreviousPitchWhenSeeded() throws {
        for hz in [200.0, 320.0] {
            let estimate = try XCTUnwrap(PitchEstimator.estimate(frame: TestAudio.frame(hz: hz), sampleRate: TestAudio.sampleRate, previousHz: hz))
            XCTAssertEqual(estimate, hz, accuracy: hz * 0.01, "seeded estimate for \(hz) Hz")
        }
    }

    /// Characterization of a known bug (audit finding C3). Without a previous pitch, the
    /// estimator picks the deepest CMNDF dip instead of YIN's first dip below threshold, so a
    /// clean steady tone is reported one octave low whenever its subharmonic is still in range.
    /// The continuity constraint then keeps following frames in the wrong octave. When the
    /// estimator is fixed, these should become `hz`, not `hz / 2`.
    func testCharacterization_unseededEstimateIsAnOctaveLow() throws {
        for hz in [200.0, 320.0] {
            let estimate = try XCTUnwrap(PitchEstimator.estimate(frame: TestAudio.frame(hz: hz), sampleRate: TestAudio.sampleRate, previousHz: nil))
            XCTAssertEqual(estimate, hz / 2, accuracy: hz * 0.01, "unseeded estimate for \(hz) Hz")
        }
    }

    func testSilenceIsUnvoiced() {
        let frame = [Float](repeating: 0, count: Int(TestAudio.sampleRate * 0.040))
        XCTAssertNil(PitchEstimator.estimate(frame: frame, sampleRate: TestAudio.sampleRate, previousHz: nil))
    }

    func testMedian() {
        XCTAssertNil(PitchEstimator.median([]))
        XCTAssertEqual(PitchEstimator.median([3, 1, 2]), 2)
        XCTAssertEqual(PitchEstimator.median([4, 1, 3, 2]), 2.5)
    }

    /// Characterization of known behavior (audit finding C5). The voicing gate is an absolute
    /// level, so a clearly periodic but quiet frame (peak about -40 dBFS) is treated as
    /// silence. Update this test deliberately when the gate becomes relative to the utterance.
    func testCharacterization_quietPeriodicFrameIsTreatedAsSilence() {
        let quiet = TestAudio.frame(hz: 200, amplitude: 0.01)
        XCTAssertNil(PitchEstimator.estimate(frame: quiet, sampleRate: TestAudio.sampleRate, previousHz: nil))
    }
}
