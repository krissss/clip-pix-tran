import AppKit
import SwiftUI

struct UpdateDialogView: View {
    @Bindable var state: UpdateDialogState

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusContent
                    releaseNotesContent
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 260)

            Divider()

            footer
        }
        .frame(width: 560, height: 520)
        .background(updateBackground)
    }

    private var accentColor: Color {
        Color(nsColor: .systemBlue)
    }

    private var updateBackground: some View {
        ZStack(alignment: .topLeading) {
            Color(nsColor: .windowBackgroundColor)

            LinearGradient(
                colors: [
                    accentColor.opacity(0.08),
                    accentColor.opacity(0.03),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Rectangle()
                .fill(accentColor.opacity(0.18))
                .frame(width: 2)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.24), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.10), radius: 5, y: 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)

                subtitleView
            }

            Spacer(minLength: 16)
        }
        .padding(20)
    }

    @ViewBuilder
    private var subtitleView: some View {
        if state.currentVersion.isEmpty || state.latestVersion.isEmpty {
            Text("ClipPixTran")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else {
            Text(subtitle)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(accentColor)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous)
                        .fill(accentColor.opacity(0.10))
                }
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch state.phase {
        case .checking:
            statusPanel(systemImage: "arrow.triangle.2.circlepath", color: .blue) {
                progressRow(title: "正在检查更新...", progress: nil)
            }
        case .updateFound:
            if let message = state.message {
                statusPanel(systemImage: "arrow.down.circle.fill", color: .blue) {
                    statusText(message)
                }
            }
        case let .downloading(progress):
            statusPanel(systemImage: "arrow.down.circle.fill", color: .blue) {
                progressRow(title: "正在下载更新...", progress: progress)
            }
        case let .extracting(progress):
            statusPanel(systemImage: "shippingbox.fill", color: .orange) {
                progressRow(title: "正在准备更新...", progress: progress)
            }
        case .readyToInstall:
            statusPanel(systemImage: "checkmark.seal.fill", color: .green) {
                statusText("更新已准备好。安装完成后 ClipPixTran 会重新启动。")
            }
        case .installing:
            statusPanel(systemImage: "arrow.triangle.2.circlepath.circle.fill", color: .blue) {
                progressRow(title: "正在安装更新...", progress: nil)
            }
        case .installed:
            statusPanel(systemImage: "checkmark.circle.fill", color: .green) {
                statusText("更新已安装完成。")
            }
        case .notFound:
            statusPanel(systemImage: "checkmark.circle.fill", color: .green) {
                statusText(state.message ?? "ClipPixTran 已经是最新版本。")
            }
        case .error:
            statusPanel(systemImage: "exclamationmark.triangle.fill", color: .red) {
                statusText(state.message ?? "ClipPixTran 无法完成更新检查。", color: .red)
            }
        }
    }

    @ViewBuilder
    private var releaseNotesContent: some View {
        if !state.changelogEntries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader

                ForEach(state.changelogEntries) { entry in
                    changelogEntryPanel(entry)
                }
            }
        } else if let fallbackNotes = state.fallbackNotes, !fallbackNotes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader

                UpdateInsetPanel(spacing: 8) {
                    UpdateMarkdownText(markdown: fallbackNotes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let skipAction = state.skipAction, showsSkipButton {
                Button {
                    skipAction()
                } label: {
                    Label("跳过此版本", systemImage: "forward.end.fill")
                }
                .controlSize(.large)
            }

            Spacer()

            if let cancelAction = state.cancelAction, showsCancelButton {
                Button {
                    cancelAction()
                } label: {
                    Label("取消", systemImage: "xmark.circle.fill")
                }
                .controlSize(.large)
            }

            if let dismissAction = state.dismissAction, showsLaterButton {
                Button {
                    dismissAction()
                } label: {
                    Label("稍后", systemImage: "clock.fill")
                }
                .controlSize(.large)
            }

            if let acknowledgeAction = state.acknowledgeAction, state.isTerminal {
                Button {
                    acknowledgeAction()
                } label: {
                    Label("好", systemImage: "checkmark.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
            }

            if let installAction = state.installAction, showsInstallButton {
                Button {
                    installAction()
                } label: {
                    Label(installButtonTitle, systemImage: "arrow.down.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(.secondary.opacity(0.035))
    }

    private var sectionHeader: some View {
        HStack(spacing: 10) {
            ControlPanelIconTile(
                systemImage: "list.bullet.rectangle.fill",
                tint: accentColor,
                size: 26
            )

            Text("更新内容")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
    }

    private func changelogEntryPanel(_ entry: UpdateChangelogEntry) -> some View {
        UpdateInsetPanel(spacing: 10) {
            HStack(spacing: 8) {
                Text(entry.displayTitle)
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)
            }

            Divider()
                .opacity(0.45)

            UpdateMarkdownText(markdown: entry.body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func statusPanel<Content: View>(
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ControlPanelIconTile(systemImage: systemImage, tint: color, size: 28)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: ControlPanelDesign.cardRadius, style: .continuous)
                .fill(color.opacity(0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: ControlPanelDesign.cardRadius, style: .continuous)
                .stroke(color.opacity(0.10), lineWidth: 1)
        }
    }

    private func statusText(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(color)
            .textSelection(.enabled)
    }

    private func progressRow(title: String, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
            if let progress {
                ProgressView(value: min(max(progress, 0), 1))
                    .tint(.blue)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var title: String {
        switch state.phase {
        case .notFound:
            return "已是最新版本"
        case .error:
            return "更新失败"
        case .readyToInstall:
            return "可以安装了"
        case .installing:
            return "正在安装更新..."
        case .installed:
            return "更新已安装"
        default:
            if state.latestVersion.isEmpty {
                return "ClipPixTran 更新"
            }

            return "ClipPixTran \(state.latestVersion) 可用"
        }
    }

    private var subtitle: String {
        "当前 \(state.currentVersion) -> 最新 \(state.latestVersion)"
    }

    private var showsInstallButton: Bool {
        switch state.phase {
        case .updateFound, .readyToInstall:
            true
        default:
            false
        }
    }

    private var showsLaterButton: Bool {
        switch state.phase {
        case .updateFound, .readyToInstall:
            true
        default:
            false
        }
    }

    private var showsSkipButton: Bool {
        if case .updateFound = state.phase {
            return true
        }

        return false
    }

    private var showsCancelButton: Bool {
        switch state.phase {
        case .checking, .downloading:
            true
        default:
            false
        }
    }

    private var installButtonTitle: String {
        if case .readyToInstall = state.phase {
            return "安装并重启"
        }

        return "安装更新"
    }
}

private struct UpdateInsetPanel<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: ControlPanelDesign.cardRadius, style: .continuous)
                .fill(ControlPanelDesign.raisedCardBackground)
        }
        .overlay {
            RoundedRectangle(cornerRadius: ControlPanelDesign.cardRadius, style: .continuous)
                .stroke(ControlPanelDesign.structuralLine, lineWidth: 1)
        }
    }
}

private struct UpdateMarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func lineView(_ line: MarkdownLine) -> some View {
        switch line {
        case let .heading(text):
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)

        case let .bullet(text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("-")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.tertiary)

                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case let .text(text):
            Text(text)
                .fixedSize(horizontal: false, vertical: true)

        case .spacer:
            Color.clear
                .frame(height: 2)
        }
    }

    private var lines: [MarkdownLine] {
        var result: [MarkdownLine] = []
        var previousWasSpacer = false

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.isEmpty {
                if !previousWasSpacer {
                    result.append(.spacer)
                    previousWasSpacer = true
                }
                continue
            }

            previousWasSpacer = false

            if line.hasPrefix("### ") {
                result.append(.heading(String(line.dropFirst(4))))
            } else if line.hasPrefix("## ") {
                result.append(.heading(String(line.dropFirst(3))))
            } else if line.hasPrefix("- ") {
                result.append(.bullet(String(line.dropFirst(2))))
            } else if line.hasPrefix("* ") {
                result.append(.bullet(String(line.dropFirst(2))))
            } else {
                result.append(.text(line))
            }
        }

        while result.first == .spacer {
            result.removeFirst()
        }
        while result.last == .spacer {
            result.removeLast()
        }

        return result
    }

    private enum MarkdownLine: Equatable {
        case heading(String)
        case bullet(String)
        case text(String)
        case spacer
    }
}

#Preview {
    let state = UpdateDialogState()
    state.phase = .updateFound
    state.currentVersion = "0.1.0"
    state.latestVersion = "0.2.0"
    state.changelogEntries = [
        UpdateChangelogEntry(
            version: "0.2.0",
            date: "2026-06-09",
            body: """
            ### Added

            - 支持菜单栏直接打开设置
            - 添加首次启动引导
            """
        ),
        UpdateChangelogEntry(
            version: "0.1.1",
            date: "2026-06-07",
            body: """
            ### Fixed

            - 显示版本并本地化更新提示
            """
        )
    ]
    state.installAction = {}
    state.dismissAction = {}
    state.skipAction = {}
    return UpdateDialogView(state: state)
}
