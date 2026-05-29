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

            Divider()

            bodyContent
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(.quaternary)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chevron.down")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Image(systemName: provider.systemImage)
                .foregroundStyle(.secondary)

            Text(provider.name)
                .font(.subheadline.weight(.semibold))

            if provider.isLocal {
                Label("本地", systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            }

            Spacer()

            statusIndicator
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch status {
        case .idle:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .loading:
            ProgressView()
                .controlSize(.small)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
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
                .frame(maxWidth: .infinity, minHeight: contentMinHeight, alignment: .center)
                .padding(10)
        case .loading(let message):
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: contentMinHeight, alignment: .center)
            .padding(10)
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

                Text(translatedText)
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, minHeight: contentMinHeight, alignment: .topLeading)

                HStack {
                    Spacer()

                    Button(action: onCopy) {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                    .disabled(!canCopy)
                    .help("复制译文")
                }
            }
            .padding(10)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, minHeight: contentMinHeight, alignment: .topLeading)

                HStack {
                    Spacer()

                    Button(action: onRetry) {
                        Label("重试", systemImage: "arrow.clockwise")
                    }
                    .controlSize(.small)
                    .help("重新翻译")
                }
            }
            .padding(10)
        }
    }
}
