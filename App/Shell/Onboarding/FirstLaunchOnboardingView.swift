import SwiftUI

struct FirstLaunchOnboardingView: View {
    let permissionService: OnboardingPermissionStatusProviding
    let completeAction: () -> Void
    let skipAction: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedStep: OnboardingStep = .screenRecording
    @State private var screenRecordingStatus: OnboardingPermissionStatus = .notAuthorized
    @State private var accessibilityStatus: OnboardingPermissionStatus = .notAuthorized
    @State private var statusMessage: OnboardingStatusMessage?
    @State private var isRequestingScreenRecording = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 218)

            VStack(spacing: 0) {
                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                footer
            }
            .controlPanelContentSurface()
        }
        .frame(width: 720, height: 460)
        .background(ControlPanelBackground())
        .task {
            refreshPermissionStatuses()
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else {
                return
            }

            refreshPermissionStatuses()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                ControlPanelIconTile(
                    systemImage: "sparkles.rectangle.stack",
                    tint: Color.accentColor,
                    size: 40
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.appName)
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)

                    Text(L10n.onboardingReady)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 16)

            VStack(spacing: 7) {
                ForEach(OnboardingStep.allCases) { step in
                    OnboardingStepButton(
                        step: step,
                        isSelected: selectedStep == step,
                        status: status(for: step)
                    ) {
                        selectedStep = step
                        statusMessage = nil
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 12)

            Text(L10n.onboardingSkipNote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
        }
        .controlPanelSidebarSurface(.history)
    }

    @ViewBuilder
    private var stepContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            ControlPanelPageHeader(
                title: selectedStep.title,
                subtitle: selectedStep.subtitle,
                systemImage: selectedStep.systemImage,
                tint: selectedStep.tint
            )

            if let statusMessage {
                OnboardingMessageBanner(message: statusMessage)
            }

            selectedStepContent
        }
        .padding(24)
    }

    @ViewBuilder
    private var selectedStepContent: some View {
        switch selectedStep {
        case .screenRecording:
            permissionStep(
                explanation: L10n.onboardingScreenRecordingExplanation,
                status: screenRecordingStatus,
                primaryTitle: L10n.onboardingAuthorizeScreenRecording,
                primarySystemImage: "record.circle",
                primaryAction: requestScreenRecordingAccess,
                secondaryTitle: L10n.commonOpenSystemSettings,
                secondarySystemImage: "gearshape",
                secondaryAction: openScreenRecordingSettings,
                tertiaryTitle: L10n.onboardingRecheck,
                tertiarySystemImage: "arrow.clockwise",
                tertiaryAction: refreshPermissionStatuses
            )
        case .accessibility:
            permissionStep(
                explanation: L10n.onboardingAccessibilityExplanation,
                status: accessibilityStatus,
                primaryTitle: L10n.commonOpenSystemSettings,
                primarySystemImage: "gearshape",
                primaryAction: openAccessibilitySettings,
                secondaryTitle: L10n.onboardingRecheck,
                secondarySystemImage: "arrow.clockwise",
                secondaryAction: refreshPermissionStatuses
            )
        case .shortcuts:
            shortcutsStep
        }
    }

    private func permissionStep(
        explanation: String,
        status: OnboardingPermissionStatus,
        primaryTitle: String,
        primarySystemImage: String,
        primaryAction: @escaping () -> Void,
        secondaryTitle: String,
        secondarySystemImage: String,
        secondaryAction: @escaping () -> Void,
        tertiaryTitle: String? = nil,
        tertiarySystemImage: String? = nil,
        tertiaryAction: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(explanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            OnboardingPermissionStatusCard(status: status)

            HStack(spacing: 10) {
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: primarySystemImage)
                }
                .disabled(isRequestingScreenRecording)

                Button(action: secondaryAction) {
                    Label(secondaryTitle, systemImage: secondarySystemImage)
                }

                if let tertiaryTitle, let tertiarySystemImage, let tertiaryAction {
                    Button(action: tertiaryAction) {
                        Label(tertiaryTitle, systemImage: tertiarySystemImage)
                    }
                }
            }
            .controlSize(.regular)

            Spacer(minLength: 0)
        }
    }

    private var shortcutsStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.onboardingShortcutsExplanation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                ForEach(AppKeyboardShortcut.all) { shortcut in
                    OnboardingShortcutRow(shortcut: shortcut)
                }
            }
            .controlPanelSettingsRowGroup()

            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                skipAction()
            } label: {
                Label(L10n.onboardingSkip, systemImage: "forward")
            }

            Spacer()

            Button {
                moveBackward()
            } label: {
                Label(L10n.commonPrevious, systemImage: "chevron.left")
            }
            .disabled(selectedStep == OnboardingStep.allCases.first)

            if selectedStep == OnboardingStep.allCases.last {
                Button {
                    completeAction()
                } label: {
                    Label(L10n.commonDone, systemImage: "checkmark")
                }
                .keyboardShortcut(.defaultAction)
            } else {
                Button {
                    moveForward()
                } label: {
                    Label(L10n.commonNext, systemImage: "chevron.right")
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .controlPanelActionBar()
    }

    private func status(for step: OnboardingStep) -> OnboardingPermissionStatus? {
        switch step {
        case .screenRecording:
            screenRecordingStatus
        case .accessibility:
            accessibilityStatus
        case .shortcuts:
            nil
        }
    }

    private func refreshPermissionStatuses() {
        screenRecordingStatus = permissionService.screenRecordingStatus()
        accessibilityStatus = permissionService.accessibilityStatus()
    }

    private func requestScreenRecordingAccess() {
        guard !isRequestingScreenRecording else {
            return
        }

        isRequestingScreenRecording = true
        statusMessage = nil
        Task { @MainActor in
            screenRecordingStatus = await permissionService.requestScreenRecordingAccess()
            isRequestingScreenRecording = false
            statusMessage = screenRecordingStatus == .authorized
                ? .success(L10n.onboardingScreenRecordingAuthorizedMessage)
                : screenRecordingRequestFallbackMessage()
        }
    }

    private func screenRecordingRequestFallbackMessage() -> OnboardingStatusMessage {
        Self.screenRecordingRequestFallbackMessage(
            didOpenSettings: permissionService.openScreenRecordingSettings()
        )
    }

    static func screenRecordingRequestFallbackMessage(
        didOpenSettings: Bool
    ) -> OnboardingStatusMessage {
        if didOpenSettings {
            return .warning(L10n.onboardingScreenRecordingPromptFallbackOpenedSettings)
        }

        return .warning(L10n.onboardingScreenRecordingPromptFallbackManual)
    }

    private func openScreenRecordingSettings() {
        if permissionService.openScreenRecordingSettings() {
            statusMessage = .info(L10n.onboardingSettingsOpenedRecheck)
        } else {
            statusMessage = .warning(L10n.onboardingScreenRecordingSettingsOpenFailed)
        }
    }

    private func openAccessibilitySettings() {
        if permissionService.openAccessibilitySettings() {
            statusMessage = .info(L10n.onboardingAccessibilitySettingsOpened)
        } else {
            statusMessage = .warning(L10n.onboardingAccessibilitySettingsOpenFailed)
        }
    }

    private func moveForward() {
        guard let nextStep = selectedStep.next else {
            return
        }

        selectedStep = nextStep
        statusMessage = nil
        refreshPermissionStatuses()
    }

    private func moveBackward() {
        guard let previousStep = selectedStep.previous else {
            return
        }

        selectedStep = previousStep
        statusMessage = nil
        refreshPermissionStatuses()
    }
}

enum OnboardingStep: String, CaseIterable, Identifiable {
    case screenRecording
    case accessibility
    case shortcuts

    var id: Self { self }

    var title: String {
        switch self {
        case .screenRecording:
            L10n.onboardingScreenRecordingTitle
        case .accessibility:
            L10n.onboardingAccessibilityTitle
        case .shortcuts:
            L10n.onboardingShortcutsTitle
        }
    }

    var subtitle: String {
        switch self {
        case .screenRecording:
            L10n.onboardingScreenRecordingSubtitle
        case .accessibility:
            L10n.onboardingAccessibilitySubtitle
        case .shortcuts:
            L10n.onboardingShortcutsSubtitle
        }
    }

    var systemImage: String {
        switch self {
        case .screenRecording:
            "camera.viewfinder"
        case .accessibility:
            "figure.stand"
        case .shortcuts:
            "keyboard"
        }
    }

    var tint: Color {
        switch self {
        case .screenRecording:
            ControlPanelDesign.tint(for: .pix)
        case .accessibility:
            Color(nsColor: .systemIndigo)
        case .shortcuts:
            Color(nsColor: .systemBlue)
        }
    }

    var previous: Self? {
        guard let index = Self.allCases.firstIndex(of: self),
              index > Self.allCases.startIndex else {
            return nil
        }

        return Self.allCases[Self.allCases.index(before: index)]
    }

    var next: Self? {
        guard let index = Self.allCases.firstIndex(of: self) else {
            return nil
        }

        let nextIndex = Self.allCases.index(after: index)
        guard nextIndex < Self.allCases.endIndex else {
            return nil
        }

        return Self.allCases[nextIndex]
    }
}

private struct OnboardingStepButton: View {
    let step: OnboardingStep
    let isSelected: Bool
    let status: OnboardingPermissionStatus?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: step.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isSelected ? step.tint : .secondary)
                    .frame(width: 26, height: 26)
                    .controlPanelRoundedSurface(
                        background: ControlPanelDesign.selectedFill(
                            tint: step.tint,
                            isSelected: isSelected,
                            opacity: 0.13
                        ),
                        cornerRadius: ControlPanelDesign.compactRadius
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(step.title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .lineLimit(1)

                    Text(statusText)
                        .font(.caption2)
                        .foregroundStyle(statusTint)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous))
            .controlPanelSelectedRow(isSelected: isSelected, tint: step.tint)
        }
        .buttonStyle(.plain)
    }

    private var statusText: String {
        guard let status else {
            return L10n.onboardingAdjustable
        }

        switch status {
        case .authorized:
            return L10n.onboardingAuthorized
        case .notAuthorized:
            return L10n.onboardingNotAuthorized
        }
    }

    private var statusTint: Color {
        guard let status else {
            return .secondary
        }

        switch status {
        case .authorized:
            return Color(nsColor: .systemGreen)
        case .notAuthorized:
            return Color(nsColor: .systemOrange)
        }
    }
}

private struct OnboardingPermissionStatusCard: View {
    let status: OnboardingPermissionStatus

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.headline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .controlPanelRoundedSurface(
                    background: tint.opacity(0.13),
                    cornerRadius: ControlPanelDesign.compactRadius
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .controlPanelCard(background: ControlPanelDesign.raisedCardBackground)
    }

    private var iconName: String {
        switch status {
        case .authorized:
            "checkmark.circle.fill"
        case .notAuthorized:
            "exclamationmark.triangle.fill"
        }
    }

    private var title: String {
        switch status {
        case .authorized:
            L10n.onboardingAuthorized
        case .notAuthorized:
            L10n.onboardingNotAuthorized
        }
    }

    private var subtitle: String {
        switch status {
        case .authorized:
            L10n.onboardingCapabilityReady
        case .notAuthorized:
            L10n.onboardingCapabilityNeedsPermission
        }
    }

    private var tint: Color {
        switch status {
        case .authorized:
            Color(nsColor: .systemGreen)
        case .notAuthorized:
            Color(nsColor: .systemOrange)
        }
    }
}

enum OnboardingStatusMessage: Equatable {
    case info(String)
    case success(String)
    case warning(String)

    var text: String {
        switch self {
        case let .info(text), let .success(text), let .warning(text):
            text
        }
    }

    var systemImage: String {
        switch self {
        case .info:
            "info.circle"
        case .success:
            "checkmark.circle"
        case .warning:
            "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .info:
            Color(nsColor: .systemBlue)
        case .success:
            Color(nsColor: .systemGreen)
        case .warning:
            Color(nsColor: .systemOrange)
        }
    }
}

private struct OnboardingMessageBanner: View {
    let message: OnboardingStatusMessage

    var body: some View {
        Label(message.text, systemImage: message.systemImage)
            .font(.callout)
            .foregroundStyle(message.tint)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .controlPanelRoundedSurface(
                background: message.tint.opacity(0.10),
                cornerRadius: ControlPanelDesign.compactRadius
            )
    }
}

private struct OnboardingShortcutRow: View {
    let shortcut: AppKeyboardShortcut

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Text(shortcut.title)
                .font(.callout)
                .lineLimit(1)

            Spacer(minLength: 16)

            LocalizedShortcutRecorder(name: shortcut.name)
                .frame(width: ControlPanelDesign.Layout.Settings.controlWidth, alignment: .trailing)
        }
        .frame(minHeight: ControlPanelDesign.Layout.Settings.rowHeight)
        .padding(.horizontal, 16)
    }
}

#Preview {
    FirstLaunchOnboardingView(
        permissionService: SystemOnboardingPermissionService(
            preflightScreenRecordingAccess: { false },
            requestScreenRecordingAccessHandler: { false },
            accessibilityTrusted: { true },
            openURL: { _ in true }
        ),
        completeAction: {},
        skipAction: {}
    )
}
