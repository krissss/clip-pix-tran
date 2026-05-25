import SwiftUI

struct TranView: View {
    @Bindable var controller: TranslationController

    var body: some View {
        VStack(spacing: 0) {
            editor

            Divider()
                .padding(.horizontal, 16)

            history
        }
        .navigationTitle("Tran")
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("文本翻译")
                    .font(.title3.weight(.semibold))

                Spacer()

                Picker("目标语言", selection: targetLanguageSelection) {
                    ForEach(TranslationLanguage.supported) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                .frame(width: 150)

                Button {
                    Task {
                        await controller.translate()
                    }
                } label: {
                    if controller.isTranslating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("翻译", systemImage: "arrow.right.circle")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isTranslating)
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("原文")
                            .font(.headline)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 28)

                    ShortcutTextEditor(text: $controller.sourceText) {
                        Task {
                            await controller.translate()
                        }
                    }
                        .frame(minHeight: 180)
                        .background(.quaternary.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("译文")
                            .font(.headline)

                        Spacer()

                        Button(action: controller.copyResultToPasteboard) {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .help("复制译文")
                        .controlSize(.small)
                        .disabled(controller.translatedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .frame(height: 28)

                    TextEditor(text: $controller.translatedText)
                        .font(.body)
                        .frame(minHeight: 180)
                        .scrollContentBackground(.hidden)
                        .background(.quaternary.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(maxWidth: .infinity)
            }

            if let errorMessage = controller.lastErrorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var history: some View {
        if controller.history.items.isEmpty {
            ContentUnavailableView(
                "还没有翻译记录",
                systemImage: "text.bubble",
                description: Text("输入文本并点击翻译后，结果会出现在这里。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    historyActions

                    if let errorMessage = controller.history.persistenceErrorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }

                    ForEach(controller.history.items) { item in
                        TranslationHistoryRow(
                            item: item,
                            onUse: {
                                controller.useHistoryItem(item)
                            },
                            onDelete: {
                                controller.deleteHistoryItem(item)
                            }
                        )
                    }
                }
                .padding(.bottom, 8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var historyActions: some View {
        HStack {
            Label("\(controller.history.items.count) 条记录", systemImage: "clock")
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive, action: controller.clearHistory) {
                Label("清空全部", systemImage: "trash")
            }
            .disabled(controller.history.items.isEmpty)
            .help("清空翻译历史")
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var targetLanguageSelection: Binding<String> {
        Binding {
            controller.targetLanguageCode
        } set: { newValue in
            controller.selectTargetLanguage(newValue)
        }
    }
}

private struct ShortcutTextEditor: NSViewRepresentable {
    @Binding var text: String
    let onCommandReturn: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommandReturn: onCommandReturn)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true

        let textView = CommandReturnTextView()
        textView.delegate = context.coordinator
        textView.onCommandReturn = context.coordinator.handleCommandReturn
        textView.string = text
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onCommandReturn = onCommandReturn

        guard let textView = scrollView.documentView as? CommandReturnTextView else {
            return
        }

        if textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        var onCommandReturn: () -> Void

        init(text: Binding<String>, onCommandReturn: @escaping () -> Void) {
            self.text = text
            self.onCommandReturn = onCommandReturn
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else {
                return
            }

            text.wrappedValue = textView.string
        }

        func handleCommandReturn() {
            onCommandReturn()
        }
    }
}

private final class CommandReturnTextView: NSTextView {
    var onCommandReturn: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let modifierFlags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturnKey = event.keyCode == 36 || event.keyCode == 76

        if isReturnKey, modifierFlags.contains(.command) {
            onCommandReturn?()
            return
        }

        super.keyDown(with: event)
    }
}

private struct TranslationHistoryRow: View {
    let item: TranslationHistoryItem
    let onUse: () -> Void
    let onDelete: () -> Void

    private var languageText: String {
        TranslationLanguage.name(for: item.targetLanguageCode)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(languageText)
                    .font(.headline)

                Text(item.sourceText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                Text(item.translatedText)
                    .font(.body)
                    .lineLimit(3)
            }

            Spacer()

            HStack(spacing: 8) {
                Button(action: onUse) {
                    Label("使用", systemImage: "arrow.up.left")
                }
                .help("载入这条翻译")

                Button(role: .destructive, action: onDelete) {
                    Label("删除", systemImage: "trash")
                }
                .help("删除翻译记录")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.horizontal, 16)
        }
        .contentShape(Rectangle())
    }
}

#Preview {
    TranView(
        controller: TranslationController(
            history: .preview,
            translationService: FallbackTranslationService(),
            pasteboard: PreviewClipboardService()
        )
    )
}
