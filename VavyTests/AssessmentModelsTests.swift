import Foundation
import XCTest
@testable import Vavy

@MainActor
final class AssessmentModelsTests: XCTestCase {
    private func decode(status: String, errorType: String? = nil) throws -> AssessmentResult {
        let mainError = errorType.map { #"{"type":"\#($0)","expected":null,"heard_like":null,"severity":"low","message":"m"}"# } ?? "null"
        let json = """
        {"attempt_id":"att_1","status":"\(status)","passed":false,"expected_text":"mã","recognized_text":null,
         "overall_score":null,"strict_score":null,
         "scores":{"accuracy":null,"fluency":null,"completeness":null,"pronunciation":null},
         "main_error":\(mainError),
         "feedback":{"title":"t","body":"b","fix":null,"drill":[]},"debug":null}
        """
        return try JSONDecoder().decode(AssessmentResult.self, from: Data(json.utf8))
    }

    func testDecodesEveryBackendStatus() throws {
        XCTAssertEqual(try decode(status: "passed").status, .passed)
        XCTAssertEqual(try decode(status: "not_passed").status, .notPassed)
        XCTAssertEqual(try decode(status: "uncertain").status, .uncertain)
        XCTAssertEqual(try decode(status: "retry_audio_quality").status, .retryAudioQuality)
        XCTAssertEqual(try decode(status: "backend_error").status, .backendError)
    }

    func testUnknownStatusDegradesToBackendErrorRatherThanAVerdict() throws {
        XCTAssertEqual(try decode(status: "some_future_status").status, .backendError)
    }

    func testDecodesAbstentionErrorTypes() throws {
        XCTAssertEqual(try decode(status: "retry_audio_quality", errorType: "no_speech").mainError?.type, .noSpeech)
        XCTAssertEqual(try decode(status: "uncertain", errorType: "tone_uncertain").mainError?.type, .toneUncertain)
        XCTAssertEqual(try decode(status: "uncertain", errorType: "something_new").mainError?.type, .unknown)
    }

    func testOnlyVerdictsCountTowardProgress() {
        XCTAssertTrue(AssessmentStatus.passed.isVerdict)
        XCTAssertTrue(AssessmentStatus.notPassed.isVerdict)
        XCTAssertFalse(AssessmentStatus.uncertain.isVerdict)
        XCTAssertFalse(AssessmentStatus.retryAudioQuality.isVerdict)
        XCTAssertFalse(AssessmentStatus.backendError.isVerdict)
    }

    func testUncertainIsNotPresentedAsAFailure() {
        XCTAssertFalse(AssessmentStatus.uncertain.displayTitle.contains("Not passed"))
    }
}
