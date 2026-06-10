import AppKit
import SwiftUI

struct UpdateDialogView: View {
    @Bindable var state: UpdateDialogState

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    statusContent
                    releaseNotesContent
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            footer
        }
        .frame(width: 620, height: 500)
        .background(ControlPanelBackground())
    }

    private var accentColor: Color {
        phaseAppearance.tint
    }

    private var header: some View {
        ControlPanelPageHeader(
            title: title,
            subtitle: subtitle,
            systemImage: phaseAppearance.systemImage,
            tint: accentColor
        ) {
            if showsVersionBadge {
                Text(versionBadgeTitle)
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .controlPanelRoundedSurface(
                        background: accentColor.opacity(0.11),
                        cornerRadius: ControlPanelDesign.compactRadius
                    )
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
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

                VStack(spacing: 0) {
                    ForEach(Array(state.changelogEntries.enumerated()), id: \.element.id) { index, entry in
                        changelogEntryPanel(entry)

                        if index < state.changelogEntries.count - 1 {
                            ControlPanelHairline(.horizontal)
                                .padding(.leading, 12)
                        }
                    }
                }
                .controlPanelSettingsRowGroup()
            }
        } else if let fallbackNotes = state.fallbackNotes, !fallbackNotes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader

                VStack(alignment: .leading, spacing: 8) {
                    UpdateMarkdownText(markdown: fallbackNotes)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .controlPanelSettingsRowGroup()
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
                .buttonStyle(ControlPanelButtonStyle())
            }

            Spacer()

            if let cancelAction = state.cancelAction, showsCancelButton {
                Button {
                    cancelAction()
                } label: {
                    Label("取消", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(ControlPanelButtonStyle())
            }

            if let dismissAction = state.dismissAction, showsLaterButton {
                Button {
                    dismissAction()
                } label: {
                    Label("稍后", systemImage: "clock.fill")
                }
                .buttonStyle(ControlPanelButtonStyle())
            }

            if let acknowledgeAction = state.acknowledgeAction, state.isTerminal {
                Button {
                    acknowledgeAction()
                } label: {
                    Label("好", systemImage: "checkmark.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(ControlPanelButtonStyle(tint: accentColor, prominence: .primary))
            }

            if let installAction = state.installAction, showsInstallButton {
                Button {
                    installAction()
                } label: {
                    Label(installButtonTitle, systemImage: "arrow.down.circle.fill")
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(ControlPanelButtonStyle(tint: accentColor, prominence: .primary))
            }
        }
        .controlPanelActionBar(showsBottomBoundary: false)
        .overlay(alignment: .top) {
            ControlPanelHairline(.horizontal)
        }
    }

    private var sectionHeader: some View {
        ControlPanelCompactSectionHeader(
            title: "更新内容",
            systemImage: "list.bullet.rectangle"
        )
    }

    private func changelogEntryPanel(_ entry: UpdateChangelogEntry) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(entry.displayTitle)
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)
            }

            UpdateMarkdownText(markdown: entry.body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusPanel<Content: View>(
        systemImage: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ControlPanelIconTile(systemImage: systemImage, tint: color, size: 30)

            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .controlPanelCard(background: ControlPanelDesign.raisedCardBackground)
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
                    .tint(accentColor)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    private var phaseAppearance: PhaseAppearance {
        switch state.phase {
        case .checking:
            PhaseAppearance(systemImage: "arrow.triangle.2.circlepath", tint: Color(nsColor: .systemBlue))
        case .updateFound:
            PhaseAppearance(systemImage: "arrow.down.circle", tint: Color(nsColor: .systemBlue))
        case .downloading:
            PhaseAppearance(systemImage: "arrow.down.circle", tint: Color(nsColor: .systemBlue))
        case .extracting:
            PhaseAppearance(systemImage: "shippingbox", tint: Color(nsColor: .systemOrange))
        case .readyToInstall:
            PhaseAppearance(systemImage: "checkmark.seal", tint: Color(nsColor: .systemGreen))
        case .installing:
            PhaseAppearance(systemImage: "arrow.triangle.2.circlepath.circle", tint: Color(nsColor: .systemBlue))
        case .installed:
            PhaseAppearance(systemImage: "checkmark.circle", tint: Color(nsColor: .systemGreen))
        case .notFound:
            PhaseAppearance(systemImage: "checkmark.circle", tint: Color(nsColor: .systemGreen))
        case .error:
            PhaseAppearance(systemImage: "exclamationmark.triangle", tint: ControlPanelDesign.destructiveTint)
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
        if state.currentVersion.isEmpty || state.latestVersion.isEmpty {
            return "ClipPixTran"
        }

        return "当前 \(state.currentVersion) -> 最新 \(state.latestVersion)"
    }

    private var showsVersionBadge: Bool {
        !state.latestVersion.isEmpty
    }

    private var versionBadgeTitle: String {
        "v\(state.latestVersion)"
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

    private struct PhaseAppearance {
        let systemImage: String
        let tint: Color
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
