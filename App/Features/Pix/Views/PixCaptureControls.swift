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
                captureActionButton(
                    title: L10n.pixCaptureSelected,
                    systemImage: "selection.pin.in.out",
                    help: L10n.pixCaptureSelectedHelp,
                    action: captureSelectedRegionAction
                )

                captureActionButton(
                    title: L10n.pixRecordSelected,
                    systemImage: "record.circle",
                    help: L10n.pixRecordSelectedHelp,
                    action: startRecordingAction
                )

                captureActionButton(
                    title: L10n.pixFullScreen,
                    systemImage: "display",
                    help: L10n.pixCaptureFullScreenHelp,
                    action: captureMainDisplayAction
                )
            }
            .disabled(isCapturing || isRecording)
            .opacity(isCapturing || isRecording ? 0.56 : 1)

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

    private func captureActionButton(
        title: String,
        systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 18, height: 18)
                .frame(maxWidth: .infinity, minHeight: 34)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .foregroundStyle(.white)
        .background(
            ControlPanelDesign.tint(for: .pix).opacity(0.88),
            in: RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous)
        )
        .contentShape(RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous))
        .help(help)
        .accessibilityLabel(title)
        .accessibilityHint(help)
    }
}
