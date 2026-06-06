import SwiftUI

struct TranslationSpeechButton: View {
    let isPreparing: Bool
    let isSpeaking: Bool
    let canSpeak: Bool
    let idleHelp: String
    var speechProviderName: String?
    let action: () -> Void

    private let tint = ControlPanelDesign.tint(for: .tran)
    private var helpText: String {
        let actionText = (isPreparing || isSpeaking) ? "停止朗读" : idleHelp
        guard let speechProviderName, !speechProviderName.isEmpty else {
            return actionText
        }

        return "\(actionText)（\(speechProviderName)）"
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                if isPreparing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2")
                }

                if isSpeaking {
                    speechPulse
                }
            }
        }
        .buttonStyle(
            ControlPanelIconButtonStyle(
                role: (isPreparing || isSpeaking) ? .selected : .normal,
                tint: tint
            )
        )
        .disabled(!canSpeak && !isPreparing && !isSpeaking)
        .help(helpText)
    }

    private var speechPulse: some View {
        TimelineView(.animation) { context in
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
            Circle()
                .stroke(tint.opacity(0.5), lineWidth: 1)
                .frame(width: 22, height: 22)
                .scaleEffect(0.62 + CGFloat(phase) * 0.42)
                .opacity(0.45 - CGFloat(phase) * 0.45)
                .allowsHitTesting(false)
        }
    }
}
