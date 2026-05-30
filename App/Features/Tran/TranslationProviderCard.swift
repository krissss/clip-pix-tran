import SwiftUI

struct TranslationProviderCard: View {
    let provider: TranslationProviderDescriptor
    let status: TranslationProviderStatus
    let translatedText: String
    var detectedSourceLanguageCode: String? = nil
    let canCopy: Bool
    let onCopy: () -> Void
    let onRetry: () -> Void
    var contentMinHeight: CGFloat = 70

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
                .frame(width: 18)

            Text(provider.name)
                .font(.subheadline.weight(.semibold))

            if provider.isLocal {
                Label("本地", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .controlPanelRoundedSurface(
                        background: ControlPanelDesign.quietFill,
                        cornerRadius: ControlPanelDesign.compactRadius
                    )
            }

            Spacer()

            statusIndicator
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
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
                .frame(maxWidth: .infinity, minHeight: contentMinHeight, alignment: .topLeading)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
        case .loading(let message):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: contentMinHeight, alignment: .topLeading)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        case .success:
            VStack(alignment: .leading, spacing: 8) {
                if let detectedSourceLanguageCode {
                    Label(
                        "检测为 \(TranslationLanguage.name(for: detectedSourceLanguageCode))",
                        systemImage: "waveform.badge.magnifyingglass"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 10) {
                    Text(translatedText)
                        .font(.callout)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, minHeight: contentMinHeight, alignment: .topLeading)

                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(ControlPanelIconButtonStyle())
                    .disabled(!canCopy)
                    .help("复制译文")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 10) {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, minHeight: contentMinHeight, alignment: .topLeading)

                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(ControlPanelIconButtonStyle(role: .destructive))
                    .help("重新翻译")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }
}
