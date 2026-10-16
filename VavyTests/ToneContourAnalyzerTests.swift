import Foundation
import XCTest
@testable import Vavy

@MainActor
final class ToneContourAnalyzerTests: XCTestCase {
    private let analyzer = ToneContourAnalyzer()

    // MARK: - Mechanics on synthetic signals

    func testSilenceProducesNoToneAndZeroConfidence() {
        let result = analyzer.analyze(samples: TestAudio.silence(ms: 800))
        XCTAssertNil(result.detectedTone)
        XCTAssertEqual(result.confidence, 0)
        XCTAssertEqual(result.voicedFrameCount, 0)
        XCTAssertEqual(result.contour.count, 5)
    }

    func testClearRiseIsSac() {
        let result = analyzer.analyze(samples: TestAudio.glide(startHz: 180, endHz: 280, durationMs: 500))
        XCTAssertEqual(result.detectedTone, .sac)
    }

    func testClearFallIsHuyen() {
        let result = analyzer.analyze(samples: TestAudio.glide(startHz: 260, endHz: 170, durationMs: 500))
        XCTAssertEqual(result.detectedTone, .huyen)
    }

    func testLevelPitchIsNgang() {
        let result = analyzer.analyze(samples: TestAudio.glide(startHz: 220, endHz: 222, durationMs: 500))
        XCTAssertEqual(result.detectedTone, .ngang)
    }

    func testResultCarriesAnalyzerVersion() throws {
        let result = analyzer.analyze(samples: TestAudio.glide(startHz: 220, endHz: 222, durationMs: 500))
        XCTAssertEqual(result.analyzerVersion, ToneContourAnalyzer.version)

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(result.jsonString.utf8)) as? [String: Any])
        XCTAssertEqual(json["analyzer_version"] as? String, ToneContourAnalyzer.version)
    }

    func testDecodesStoredResultsFromBeforeVersioning() throws {
        let legacy = #"{"detected_tone":"sac","confidence":0.7,"contour":[0,1,2,3,4],"voiced_frame_count":40,"total_frame_count":50,"duration_ms":700}"#
        let result = try JSONDecoder().decode(ToneAnalysisResult.self, from: Data(legacy.utf8))
        XCTAssertEqual(result.detectedTone, .sac)
        XCTAssertNil(result.analyzerVersion)
    }

    // MARK: - Characterization on the bundled reference recordings
    //
    // These pin what the analyzer does today. They are NOT accuracy claims. The labels are the
    // tone names in the original `tones/*.mp3` filenames, which contradict the spelling in four
    // of six filenames and have not been verified by a native listener (audit finding C1).
    // Several pinned outputs are known to be wrong (C2, C3: octave errors in the pitch track).
    // When the analyzer changes, update these expectations deliberately and record why.

    private struct ReferenceExpectation {
        let fixture: String
        let tone: VietnameseTone?
        let confidence: Double
    }

    private let referenceExpectations: [ReferenceExpectation] = [
        .init(fixture: "ref-label-ngang", tone: .ngang, confidence: 0.5481),
        .init(fixture: "ref-label-huyen", tone: .huyen, confidence: 0.2039),
        .init(fixture: "ref-label-sac", tone: .hoi, confidence: 0.2388),
        .init(fixture: "ref-label-nga", tone: .sac, confidence: 0.7558),
        .init(fixture: "ref-label-hoi", tone: .nga, confidence: 0.8068),
        .init(fixture: "ref-label-nang", tone: .ngang, confidence: 0.1441),
    ]

    func testCharacterization_referenceRecordings() throws {
        for expectation in referenceExpectations {
            let result = analyzer.analyze(samples: try TestAudio.fixtureSamples(named: expectation.fixture))
            XCTAssertEqual(result.detectedTone, expectation.tone, expectation.fixture)
            XCTAssertEqual(result.confidence, expectation.confidence, accuracy: 0.001, expectation.fixture)
        }
    }

    /// C4: voicedRatio counts the whole recording, so tapping stop one second later changes
    /// the confidence (here across the backend's 0.5 threshold) and can change the tone.
    func testCharacterization_trailingSilenceChangesConfidenceAndTone() throws {
        let oneSecond = TestAudio.silence(ms: 1_000)

        let ngang = try TestAudio.fixtureSamples(named: "ref-label-ngang")
        XCTAssertEqual(analyzer.analyze(samples: ngang).confidence, 0.5481, accuracy: 0.001)
        XCTAssertEqual(analyzer.analyze(samples: ngang + oneSecond).confidence, 0.4419, accuracy: 0.001)

        let sac = try TestAudio.fixtureSamples(named: "ref-label-sac")
        XCTAssertEqual(analyzer.analyze(samples: sac).detectedTone, .hoi)
        XCTAssertEqual(analyzer.analyze(samples: sac + oneSecond).detectedTone, .nang)
    }

    /// C5: the absolute voicing gate makes a 12 dB quieter copy of the same recording unclassifiable.
    func testCharacterization_inputGainChangesResult() throws {
        let nga = try TestAudio.fixtureSamples(named: "ref-label-nga")
        XCTAssertEqual(analyzer.analyze(samples: nga).detectedTone, .sac)
        XCTAssertNil(analyzer.analyze(samples: TestAudio.scaled(nga, by: 0.25)).detectedTone)
    }
}
