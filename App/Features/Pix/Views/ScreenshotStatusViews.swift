import AppKit
import SwiftUI

struct ScreenshotStatusBanner: View {
    let message: String
    var showsSettingsButton = false

    var body: some View {
        HStack(spacing: 10) {
            ControlPanelStatusBanner(message: message) {
                if showsSettingsButton {
                    Button {
                        openScreenRecordingSettings()
                    } label: {
                        Label("打开系统设置", systemImage: "gearshape")
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

struct ScreenshotEmptyDetailPane: View {
    let needsScreenRecordingPermission: Bool

    var body: some View {
        VStack(spacing: 18) {
            ControlPanelIconTile(
                systemImage: "camera.viewfinder",
                tint: ControlPanelDesign.tint(for: .pix),
                size: 52
            )

            VStack(spacing: 6) {
                Text("还没有截图")
                    .font(.title3.weight(.semibold))
            }

            if needsScreenRecordingPermission {
                Button {
                    openScreenRecordingSettings()
                } label: {
                    Label("打开系统设置", systemImage: "gearshape")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .controlPanelContentSurface()
    }
}

private func openScreenRecordingSettings() {
    guard let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    ) else {
        return
    }

    NSWorkspace.shared.open(url)
}
