import SwiftUI

struct TranslationProviderCard: View {
    let provider: TranslationProviderDescriptor
    let status: TranslationProviderStatus
    let translatedText: String
    let canCopy: Bool
    let canSpeak: Bool
    let isSpeaking: Bool
    let onCopy: () -> Void
    let onSpeak: () -> Void
    let onRetry: () -> Void
    var contentMinHeight: CGFloat = 70
    var isCompact = false

    private var horizontalPadding: CGFloat {
        isCompact ? 8 : 10
    }

    private var headerTopPadding: CGFloat {
        isCompact ? 5 : 6
    }

    private var headerBottomPadding: CGFloat {
        isCompact ? 2 : 3
    }

    private var bodyBottomPadding: CGFloat {
        isCompact ? 7 : 9
    }

    private var contentSpacing: CGFloat {
        isCompact ? 5 : 8
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            bodyContent
        }
        .controlPanelRoundedSurface(
            background: ControlPanelDesign.historyRowBackground,
            cornerRadius: ControlPanelDesign.compactRadius
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: provider.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: isCompact ? 16 : 18)

            Text(provider.name)
                .font(isCompact ? .caption : .caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if provider.isLocal {
                Label("本地", systemImage: "lock")
                    .font(isCompact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, isCompact ? 6 : 7)
                    .padding(.vertical, isCompact ? 2 : 3)
                    .controlPanelRoundedSurface(
                        background: ControlPanelDesign.quietFill,
                        cornerRadius: ControlPanelDesign.compactRadius
                    )
            }

            Spacer()

            if case .success = status {
                resultActions
            } else {
                statusIndicator
            }
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.top, headerTopPadding)
        .padding(.bottom, headerBottomPadding)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .idle:
            Image(systemName: "circle.dotted")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var bodyContent: some View {
        switch status {
        case .idle(let message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: min(contentMinHeight, 34), alignment: .topLeading)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, bodyBottomPadding)
        case .loading(let message):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: min(contentMinHeight, 34), alignment: .topLeading)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bodyBottomPadding)
        case .success:
            CompactTranslationText(
                text: translatedText,
                font: isCompact ? .callout : .body,
                lineSpacing: isCompact ? 1 : 2,
                enableSelection: true
            )
                .layoutPriority(1)
                .padding(.horizontal, horizontalPadding)
                .padding(.bottom, bodyBottomPadding)
        case .failed(let message):
            VStack(alignment: .leading, spacing: contentSpacing) {
                HStack(alignment: .top, spacing: 10) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, minHeight: min(contentMinHeight, 44), alignment: .topLeading)

                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(ControlPanelIconButtonStyle(role: .destructive))
                    .help("重新翻译")
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, bodyBottomPadding)
        }
    }

    private var resultActions: some View {
        HStack(spacing: 6) {
            TranslationSpeechButton(
                isSpeaking: isSpeaking,
                canSpeak: canSpeak,
                idleHelp: "朗读译文",
                action: onSpeak
            )

            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(ControlPanelIconButtonStyle())
            .disabled(!canCopy)
            .help("复制译文")
        }
    }
}
