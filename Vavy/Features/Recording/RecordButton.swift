import SwiftUI

struct RecordButton: View {
    let isRecording: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 92, height: 92)
                .background(isRecording ? Color(uiColor: .systemRed) : Color(uiColor: .systemBlue))
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.16), radius: 10, y: 5)
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityLabel(isRecording ? "Stop recording" : "Start recording")
    }
}
