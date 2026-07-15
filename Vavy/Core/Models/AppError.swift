import Foundation

enum AppError: LocalizedError, Equatable {
    case invalidServerURL
    case networkUnavailable
    case invalidResponse
    case serverError(statusCode: Int, message: String?)
    case decodingFailed(String?)
    case microphonePermissionDenied
    case recordingFailed(String)
    case audioFileMissing
    case audioFileEmpty
    case backendError(String)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "The backend URL is invalid."
        case .networkUnavailable:
            return "The backend could not be reached. Check that the server is running and your device can reach it."
        case .invalidResponse:
            return "The backend returned an unexpected response."
        case .serverError(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Backend error \(statusCode): \(message)"
            }
            return "Backend error \(statusCode)."
        case .decodingFailed(let detail):
            if let detail, !detail.isEmpty {
                return "The backend response could not be decoded. \(detail)"
            }
            return "The backend response could not be decoded."
        case .microphonePermissionDenied:
            return "Microphone access is required so you can practice Vietnamese pronunciation."
        case .recordingFailed(let message):
            return message
        case .audioFileMissing:
            return "The recording file could not be found."
        case .audioFileEmpty:
            return "The recording was empty. Try again and speak clearly after tapping record."
        case .backendError(let message):
            return message
        }
    }
}
