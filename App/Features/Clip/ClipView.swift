import SwiftUI

struct ClipView: View {
    @Bindable var monitor: ClipboardMonitor
    let translateAction: (ClipboardItem) -> Void

    @State private var searchText = ""

    private var visibleItems: [ClipboardItem] {
        monitor.history.filteredItems(matching: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .navigationTitle("Clip")
        .searchable(
            text: $searchText,
            placement: .toolbar,
            prompt: "搜索剪贴板历史"
        )
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text("剪贴板历史")
                    .font(.title2.weight(.semibold))
                Text("复制文本后会自动出现在这里，点击条目可复制回剪贴板。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(monitor.history.items.count)/\(monitor.history.limit)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        if monitor.history.items.isEmpty {
            ContentUnavailableView(
                "暂无剪贴板文本",
                systemImage: "doc.on.clipboard",
                description: Text("复制任意文本后，它会自动加入历史。")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleItems.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    historyActions
                }

                if let errorMessage = monitor.history.persistenceErrorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                if let errorMessage = monitor.lastErrorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                ForEach(visibleItems) { item in
                    ClipboardItemRow(
                        item: item,
                        copyAction: {
                            monitor.copyToPasteboard(item)
                        },
                        togglePinnedAction: {
                            monitor.history.togglePinned(item)
                        },
                        deleteAction: {
                            monitor.history.delete(item)
                        },
                        translateAction: {
                            translateAction(item)
                        }
                    )
                    .contextMenu {
                        Button {
                            monitor.copyToPasteboard(item)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }

                        Button {
                            monitor.history.togglePinned(item)
                        } label: {
                            Label(
                                item.isPinned ? "取消收藏" : "收藏",
                                systemImage: item.isPinned ? "pin.slash" : "pin"
                            )
                        }

                        Button {
                            translateAction(item)
                        } label: {
                            Label("翻译", systemImage: "text.bubble")
                        }

                        Button(role: .destructive) {
                            monitor.history.delete(item)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private var historyActions: some View {
        HStack {
            Label("\(visibleItems.count) 条记录", systemImage: "clock")
                .foregroundStyle(.secondary)

            Spacer()

            Button(role: .destructive, action: monitor.clearHistory) {
                Label("清空全部", systemImage: "trash")
            }
            .disabled(monitor.history.items.isEmpty)
            .help("清空剪贴板历史")
        }
        .font(.callout)
        .padding(.vertical, 4)
    }
}

private struct ClipboardItemRow: View {
    let item: ClipboardItem
    let copyAction: () -> Void
    let togglePinnedAction: () -> Void
    let deleteAction: () -> Void
    let translateAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.alignleft")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.text)
                    .lineLimit(3)
                    .foregroundStyle(.primary)

                Text(item.lastCopiedAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Button(action: copyAction) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("复制")

                Button(action: togglePinnedAction) {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                }
                .buttonStyle(.borderless)
                .help(item.isPinned ? "取消收藏" : "收藏")

                Button(action: translateAction) {
                    Image(systemName: "text.bubble")
                }
                .buttonStyle(.borderless)
                .help("翻译")

                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("删除")
            }
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 6)
    }
}

#Preview {
    ClipView(
        monitor: ClipboardMonitor(
            pasteboard: PreviewClipboardService(),
            history: ClipboardHistoryStore.preview
        ),
        translateAction: { _ in }
    )
}
