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
                    PixCaptureButtonLabel(title: "截图", systemImage: "selection.pin.in.out")
                }
                .buttonStyle(captureButtonStyle)
                .help("拖拽选择屏幕区域截图")

                Button(action: startRecordingAction) {
                    PixCaptureButtonLabel(title: "录屏", systemImage: "record.circle")
                }
                .buttonStyle(captureButtonStyle)
                .help("拖拽选择屏幕区域并开始录屏")

                Button(action: captureMainDisplayAction) {
                    PixCaptureButtonLabel(title: "全屏", systemImage: "display")
                }
                .buttonStyle(captureButtonStyle)
                .help("捕获主屏幕画面")
            }
            .disabled(isCapturing || isRecording)

            if isCapturing {
                Button(action: stopCaptureAction) {
                    Label("取消框选", systemImage: "xmark.circle")
                }
                .buttonStyle(ControlPanelButtonStyle(prominence: .destructive))
                .help("结束当前框选")
            } else if isRecording {
                Button(action: stopCaptureAction) {
                    Label(
                        isStoppingRecording ? "正在保存" : "停止录屏",
                        systemImage: isStoppingRecording ? "hourglass" : "stop.circle"
                    )
                }
                .buttonStyle(ControlPanelButtonStyle(prominence: .destructive))
                .disabled(isStoppingRecording)
                .help("停止并保存当前录屏")
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
