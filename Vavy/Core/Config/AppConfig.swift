import Foundation

struct AppConfig {
    static let defaultBackendBaseURL = URL(string: "https://vavy-backend.vercel.app")!

    private static let backendBaseURLKey = "backend_base_url"

    static var backendBaseURL: URL {
        get {
            guard let savedValue = UserDefaults.standard.string(forKey: backendBaseURLKey),
                  let savedURL = normalizedBackendBaseURL(from: savedValue) else {
                return defaultBackendBaseURL
            }

            return savedURL
        }
        set {
            UserDefaults.standard.set(newValue.absoluteString, forKey: backendBaseURLKey)
        }
    }

    static func normalizedBackendBaseURL(from value: String) -> URL? {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else { return nil }

        let valueWithScheme: String
        if trimmedValue.contains("://") {
            valueWithScheme = trimmedValue
        } else if trimmedValue == "localhost"
                    || trimmedValue.hasPrefix("localhost:")
                    || trimmedValue.hasPrefix("127.")
                    || trimmedValue.hasPrefix("192.168.")
                    || trimmedValue.hasPrefix("10.")
                    || trimmedValue.hasPrefix("172.") {
            valueWithScheme = "http://\(trimmedValue)"
        } else {
            valueWithScheme = "https://\(trimmedValue)"
        }

        guard let url = URL(string: valueWithScheme),
              url.scheme != nil,
              url.host != nil else {
            return nil
        }

        return url
    }
}
