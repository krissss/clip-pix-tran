import SwiftUI

enum ControlPanelDesign {
    enum Layout {
        static let mainSidebarWidth: CGFloat = 88
        static let splitSpacing: CGFloat = 0

        static let historySidebarMinWidth: CGFloat = 280
        static let historySidebarMaxWidth: CGFloat = 360
        static let historySidebarFraction: CGFloat = 0.34

        static let headerHorizontalPadding: CGFloat = 16
        static let headerVerticalPadding: CGFloat = 12
        static let searchHorizontalPadding: CGFloat = 16
        static let pagePadding: CGFloat = 16
        static let detailContentPadding: CGFloat = 18
        static let cardPadding: CGFloat = 16
        static let historyRowThumbnailSize: CGFloat = 40
        static let compactPreviewSize: CGFloat = 38

        static let actionBarHeight: CGFloat = 56
        static let actionBarHorizontalPadding: CGFloat = 20

        enum QuickPanel {
            static let clipboardWidth: CGFloat = 420
            static let clipboardHeight: CGFloat = 430
            static let translationWidth: CGFloat = 480
            static let translationHeight: CGFloat = 424
            static let cornerRadius: CGFloat = 12
            static let headerHorizontalPadding: CGFloat = 14
            static let headerVerticalPadding: CGFloat = 10
            static let contentPadding: CGFloat = 12
            static let sectionSpacing: CGFloat = 10
            static let groupPadding: CGFloat = 10
            static let languagePickerWidth: CGFloat = 176
            static let sourceMinHeight: CGFloat = 54
            static let providerMinHeight: CGFloat = 58
        }

        enum Settings {
            static let windowWidth: CGFloat = 660
            static let windowHeight: CGFloat = 480
            static let labelWidth: CGFloat = 230
            static let controlWidth: CGFloat = 210
            static let sliderWidth: CGFloat = 154
            static let rowHeight: CGFloat = 44
            static let valueWidth: CGFloat = 42
            static let contentMinHeight: CGFloat = 344
        }

        static func historySidebarWidth(for containerWidth: CGFloat) -> CGFloat {
            min(
                historySidebarMaxWidth,
                max(historySidebarMinWidth, containerWidth * historySidebarFraction)
            )
        }
    }

    enum SidebarRole {
        case navigation
        case history

        fileprivate var background: Color {
            switch self {
            case .navigation:
                ControlPanelDesign.sidebarBackground.opacity(0.58)
            case .history:
                ControlPanelDesign.sidebarBackground
            }
        }
    }

    static let cardRadius: CGFloat = 8
    static let compactRadius: CGFloat = 6

    static var windowBackground: Color {
        Color(nsColor: .windowBackgroundColor)
    }

    static var sidebarBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.58)
    }

    static var cardBackground: Color {
        Color(nsColor: .textBackgroundColor).opacity(0.48)
    }

    static var raisedCardBackground: Color {
        Color(nsColor: .controlBackgroundColor).opacity(0.54)
    }

    static var textSurfaceBackground: Color {
        Color(nsColor: .textBackgroundColor)
    }

    static var quietFill: Color {
        Color.primary.opacity(0.034)
    }

    static var structuralLine: Color {
        Color.primary.opacity(0.055)
    }

    static var destructiveTint: Color {
        Color(nsColor: .systemRed)
    }

    static var actionBarBackground: Color {
        raisedCardBackground.opacity(0.30)
    }

    static var embeddedPanelBackground: Color {
        raisedCardBackground.opacity(0.42)
    }

    static var historyRowBackground: Color {
        raisedCardBackground.opacity(0.26)
    }

    static var panelMaterial: Material {
        .regularMaterial
    }

    static func selectedFill(
        tint: Color,
        isSelected: Bool,
        opacity: Double = 0.14
    ) -> Color {
        isSelected ? tint.opacity(opacity) : Color.clear
    }

    static func tint(for section: AppSection) -> Color {
        switch section {
        case .clip:
            Color(nsColor: .systemOrange)
        case .pix:
            Color(nsColor: .systemTeal)
        case .tran:
            Color(nsColor: .systemBlue)
        }
    }
}

struct ControlPanelBackground: View {
    var body: some View {
        ZStack {
            ControlPanelDesign.windowBackground
            ControlPanelDesign.sidebarBackground.opacity(0.36)
        }
        .ignoresSafeArea()
    }
}

struct ControlPanelPageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let tint: Color
    let trailing: Trailing

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ControlPanelIconTile(systemImage: systemImage, tint: tint, size: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            trailing
        }
    }
}

extension ControlPanelPageHeader where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            tint: tint
        ) {
            EmptyView()
        }
    }
}

struct ControlPanelSidebarHeader<Trailing: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let trailing: Trailing

    init(
        title: String,
        systemImage: String,
        tint: Color,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .controlPanelRoundedSurface(
                    background: tint.opacity(0.12),
                    cornerRadius: ControlPanelDesign.compactRadius
                )

            Text(title)
                .font(.headline)
                .lineLimit(1)

            Spacer(minLength: 8)

            trailing
        }
    }
}

extension ControlPanelSidebarHeader where Trailing == EmptyView {
    init(title: String, systemImage: String, tint: Color) {
        self.init(title: title, systemImage: systemImage, tint: tint) {
            EmptyView()
        }
    }
}

struct ControlPanelIconTile: View {
    let systemImage: String
    let tint: Color
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous)
                    .fill(tint.opacity(0.14))
            }
    }
}

struct ControlPanelMetricPill: View {
    let label: String
    let value: String
    let systemImage: String
    var tint: Color = Color.secondary

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous)
                .fill(ControlPanelDesign.raisedCardBackground)
        }
    }
}

struct ControlPanelSearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField(prompt, text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(ControlPanelDesign.quietFill, in: RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous))
    }
}

struct ControlPanelHairline: View {
    enum Orientation {
        case horizontal
        case vertical
    }

    var orientation: Orientation

    init(_ orientation: Orientation) {
        self.orientation = orientation
    }

    var body: some View {
        ControlPanelDesign.structuralLine
            .frame(
                width: orientation == .vertical ? 1 : nil,
                height: orientation == .horizontal ? 1 : nil
            )
    }
}

struct ControlPanelSectionLabel: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.headline)
        }
    }
}

struct ControlPanelCompactSectionHeader<Accessory: View>: View {
    let title: String
    var systemImage: String? = nil
    let accessory: Accessory

    init(
        title: String,
        systemImage: String? = nil,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(title)
                .font(.subheadline.weight(.semibold))

            Spacer(minLength: 8)

            accessory
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(height: 22)
    }
}

extension ControlPanelCompactSectionHeader where Accessory == EmptyView {
    init(title: String, systemImage: String? = nil) {
        self.init(title: title, systemImage: systemImage) {
            EmptyView()
        }
    }
}

struct ControlPanelEmptyState: View {
    let title: String
    var subtitle: String? = nil
    let systemImage: String
    var tint: Color = .secondary

    var body: some View {
        VStack(spacing: 12) {
            ControlPanelIconTile(systemImage: systemImage, tint: tint, size: 44)

            VStack(spacing: 5) {
                Text(title)
                    .font(.title3.weight(.semibold))

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

struct ControlPanelStatusBanner<Accessory: View>: View {
    let message: String
    var systemImage = "exclamationmark.triangle"
    var tint = Color(nsColor: .systemRed)
    let accessory: Accessory

    init(
        message: String,
        systemImage: String = "exclamationmark.triangle",
        tint: Color = Color(nsColor: .systemRed),
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 10) {
            Label(message, systemImage: systemImage)
                .font(.callout)
                .foregroundStyle(tint)

            accessory
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous))
    }
}

struct ControlPanelNoResultsState: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 24, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)
                .controlPanelQuietSurface(cornerRadius: ControlPanelDesign.cardRadius)

            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

extension ControlPanelStatusBanner where Accessory == EmptyView {
    init(
        message: String,
        systemImage: String = "exclamationmark.triangle",
        tint: Color = Color(nsColor: .systemRed)
    ) {
        self.init(message: message, systemImage: systemImage, tint: tint) {
            EmptyView()
        }
    }
}

private struct ControlPanelCardModifier: ViewModifier {
    var background: Color = ControlPanelDesign.cardBackground
    var cornerRadius: CGFloat = ControlPanelDesign.cardRadius

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(background)
            }
    }
}

private struct ControlPanelRoundedSurfaceModifier: ViewModifier {
    let background: Color
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct ControlPanelSelectedRowModifier: ViewModifier {
    let isSelected: Bool
    let tint: Color

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous)
                    .fill(ControlPanelDesign.selectedFill(tint: tint, isSelected: isSelected))
            }
    }
}

private struct ControlPanelSidebarSurfaceModifier: ViewModifier {
    let role: ControlPanelDesign.SidebarRole
    let showsTrailingBoundary: Bool

    func body(content: Content) -> some View {
        content
            .background(role.background)
            .overlay(alignment: .trailing) {
                if showsTrailingBoundary {
                    ControlPanelHairline(.vertical)
                }
            }
    }
}

private struct ControlPanelContentSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(ControlPanelDesign.windowBackground)
    }
}

private struct ControlPanelActionBarModifier: ViewModifier {
    let showsBottomBoundary: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ControlPanelDesign.Layout.actionBarHorizontalPadding)
            .frame(height: ControlPanelDesign.Layout.actionBarHeight)
            .background(ControlPanelDesign.actionBarBackground)
            .overlay(alignment: .bottom) {
                if showsBottomBoundary {
                    ControlPanelHairline(.horizontal)
                }
            }
    }
}

private struct ControlPanelPanelChromeModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(ControlPanelDesign.panelMaterial)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(ControlPanelDesign.structuralLine)
            }
    }
}

private struct ControlPanelHistoryRowModifier: ViewModifier {
    let isSelected: Bool
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 58)
            .contentShape(Rectangle())
            .background {
                RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous)
                    .fill(ControlPanelDesign.selectedFill(tint: tint, isSelected: isSelected, opacity: 0.12))
            }
    }
}

private struct ControlPanelSettingsRowGroupModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ControlPanelDesign.embeddedPanelBackground,
                in: RoundedRectangle(cornerRadius: ControlPanelDesign.cardRadius, style: .continuous)
            )
            .clipShape(RoundedRectangle(cornerRadius: ControlPanelDesign.cardRadius, style: .continuous))
    }
}

private struct ControlPanelDetailSectionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(ControlPanelDesign.Layout.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ControlPanelQuickPanelGroupModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(ControlPanelDesign.Layout.QuickPanel.groupPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ControlPanelDesign.embeddedPanelBackground,
                in: RoundedRectangle(cornerRadius: ControlPanelDesign.cardRadius, style: .continuous)
            )
    }
}

struct ControlPanelIconButtonStyle: ButtonStyle {
    enum Role {
        case normal
        case destructive
        case selected
    }

    var role: Role = .normal
    var tint: Color = Color.accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(foregroundStyle)
            .frame(width: 26, height: 26)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }

    private var foregroundStyle: Color {
        switch role {
        case .normal:
            .secondary
        case .destructive:
            ControlPanelDesign.destructiveTint
        case .selected:
            tint
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        let multiplier = isPressed ? 1.4 : 1
        switch role {
        case .normal:
            return ControlPanelDesign.quietFill.opacity(0.8 * multiplier)
        case .destructive:
            return ControlPanelDesign.destructiveTint.opacity(0.09 * multiplier)
        case .selected:
            return tint.opacity(0.12 * multiplier)
        }
    }
}

struct ControlPanelButtonStyle: ButtonStyle {
    enum Prominence {
        case primary
        case secondary
        case destructive
    }

    var tint: Color = Color.accentColor
    var prominence: Prominence = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.callout.weight(prominence == .primary ? .semibold : .regular))
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(backgroundColor(isPressed: configuration.isPressed), in: RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }

    private var foregroundStyle: Color {
        switch prominence {
        case .primary:
            .white
        case .secondary:
            .primary
        case .destructive:
            ControlPanelDesign.destructiveTint
        }
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        let opacityMultiplier = isPressed ? 1.3 : 1
        switch prominence {
        case .primary:
            return tint.opacity(0.88 * opacityMultiplier)
        case .secondary:
            return ControlPanelDesign.quietFill.opacity(0.72 * opacityMultiplier)
        case .destructive:
            return ControlPanelDesign.destructiveTint.opacity(0.1 * opacityMultiplier)
        }
    }
}

extension View {
    func controlPanelContentSurface() -> some View {
        modifier(ControlPanelContentSurfaceModifier())
    }

    func controlPanelSidebarSurface(
        _ role: ControlPanelDesign.SidebarRole = .history,
        showsTrailingBoundary: Bool = true
    ) -> some View {
        modifier(ControlPanelSidebarSurfaceModifier(role: role, showsTrailingBoundary: showsTrailingBoundary))
    }

    func controlPanelActionBar(showsBottomBoundary: Bool = true) -> some View {
        modifier(ControlPanelActionBarModifier(showsBottomBoundary: showsBottomBoundary))
    }

    func controlPanelPanelChrome(
        cornerRadius: CGFloat = ControlPanelDesign.cardRadius
    ) -> some View {
        modifier(ControlPanelPanelChromeModifier(cornerRadius: cornerRadius))
    }

    func controlPanelCard(
        background: Color = ControlPanelDesign.cardBackground,
        cornerRadius: CGFloat = ControlPanelDesign.cardRadius
    ) -> some View {
        modifier(ControlPanelCardModifier(background: background, cornerRadius: cornerRadius))
    }

    func controlPanelRoundedSurface(
        background: Color,
        cornerRadius: CGFloat = ControlPanelDesign.cardRadius
    ) -> some View {
        modifier(ControlPanelRoundedSurfaceModifier(background: background, cornerRadius: cornerRadius))
    }

    func controlPanelQuietSurface(
        cornerRadius: CGFloat = ControlPanelDesign.compactRadius
    ) -> some View {
        controlPanelRoundedSurface(
            background: ControlPanelDesign.quietFill,
            cornerRadius: cornerRadius
        )
    }

    func controlPanelTextSurface(
        cornerRadius: CGFloat = ControlPanelDesign.cardRadius
    ) -> some View {
        controlPanelRoundedSurface(
            background: ControlPanelDesign.textSurfaceBackground,
            cornerRadius: cornerRadius
        )
    }

    func controlPanelSelectedRow(isSelected: Bool, tint: Color) -> some View {
        modifier(ControlPanelSelectedRowModifier(isSelected: isSelected, tint: tint))
    }

    func controlPanelListRow(isSelected: Bool, tint: Color) -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(
                RoundedRectangle(cornerRadius: ControlPanelDesign.compactRadius, style: .continuous)
                    .fill(Color.clear)
            )
            .modifier(ControlPanelHistoryRowModifier(isSelected: isSelected, tint: tint))
    }

    func controlPanelHistoryRow(isSelected: Bool, tint: Color) -> some View {
        modifier(ControlPanelHistoryRowModifier(isSelected: isSelected, tint: tint))
    }

    func controlPanelSettingsRowGroup() -> some View {
        modifier(ControlPanelSettingsRowGroupModifier())
    }

    func controlPanelDetailSection() -> some View {
        modifier(ControlPanelDetailSectionModifier())
    }

    func controlPanelQuickPanelGroup() -> some View {
        modifier(ControlPanelQuickPanelGroupModifier())
    }

    func controlPanelSegmentedSurface() -> some View {
        padding(4)
            .background(
                ControlPanelDesign.quietFill,
                in: RoundedRectangle(cornerRadius: ControlPanelDesign.cardRadius, style: .continuous)
            )
    }
}
