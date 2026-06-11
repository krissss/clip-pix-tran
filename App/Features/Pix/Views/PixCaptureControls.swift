import SwiftUI

struct PixCaptureControls: View {
    let isCapturing: Bool
    let isRecording: Bool
    let isStoppingRecording: Bool
    let captureSelectedRegionAction: () -> Void
    let captureMainDisplayAction: () -> Void
    let startRecordingAction: () -> Void
    let stopCaptureAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Button(action: captureSelectedRegionAction) {
                    PixCaptureButtonLabel(title: L10n.pixCaptureSelected, systemImage: "selection.pin.in.out")
                }
                .buttonStyle(captureButtonStyle)
                .help(L10n.pixCaptureSelectedHelp)

                Button(action: startRecordingAction) {
                    PixCaptureButtonLabel(title: L10n.pixRecordSelected, systemImage: "record.circle")
                }
                .buttonStyle(captureButtonStyle)
                .help(L10n.pixRecordSelectedHelp)

                Button(action: captureMainDisplayAction) {
                    PixCaptureButtonLabel(title: L10n.pixFullScreen, systemImage: "display")
                }
                .buttonStyle(captureButtonStyle)
                .help(L10n.pixCaptureFullScreenHelp)
            }
            .disabled(isCapturing || isRecording)

            if isCapturing {
                Button(action: stopCaptureAction) {
                    Label(L10n.pixCancelSelection, systemImage: "xmark.circle")
                }
                .buttonStyle(ControlPanelButtonStyle(prominence: .destructive))
                .help(L10n.pixCancelSelectionHelp)
            } else if isRecording {
                Button(action: stopCaptureAction) {
                    Label(
                        isStoppingRecording ? L10n.pixSaving : L10n.pixStopRecording,
                        systemImage: isStoppingRecording ? "hourglass" : "stop.circle"
                    )
                }
                .buttonStyle(ControlPanelButtonStyle(prominence: .destructive))
                .disabled(isStoppingRecording)
                .help(L10n.pixStopRecordingHelp)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .controlPanelRoundedSurface(background: ControlPanelDesign.embeddedPanelBackground)
    }

    private var captureButtonStyle: ControlPanelButtonStyle {
        ControlPanelButtonStyle(
            tint: ControlPanelDesign.tint(for: .pix),
            prominence: .primary
        )
    }
}

private struct PixCaptureButtonLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18, height: 18)

            Text(title)
        }
        .frame(maxWidth: .infinity)
    }
}
