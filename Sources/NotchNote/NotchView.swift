import SwiftUI

enum PanelMode { case collapsed, preview, editing }

@Observable final class PanelState {
    var mode = PanelMode.collapsed
    // Keep the outgoing contents mounted until the paper has slid back into the notch.
    var contentMode = PanelMode.preview
    var revealed = false
    var surfaceSize = CGSize(width: 500, height: 430)
    var compactWidth: CGFloat = 100
    var focusID = 0
    var taskID = 0
    var showingEditor = true
    var shortcutAvailable = true
    var isPinned = false
    var formattingPresented = false
    var formatID = 0
    var formatCommand = EditorCommand.bold
    var editorStyle = EditorStyle()
}

struct NotchView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Bindable var store: NoteStore
    @Bindable var state: PanelState
    let onEdit: () -> Void
    let onClose: () -> Void
    let onEscape: () -> Void
    let onSelectSection: (UUID) -> Void
    let onAddSection: (String) -> Void
    let onTogglePin: () -> Void
    let onInteraction: (String, Bool) -> Void
    let onExport: () -> Void

    private let paper = Color(red: 0.98, green: 0.97, blue: 0.92)
    private let ink = Color(red: 0.18, green: 0.19, blue: 0.17)

    var body: some View {
        ZStack(alignment: .top) {
            expandedSurface
                .background(.black)
                .mask(NotchReveal(progress: reduceMotion ? 1 : (state.revealed ? 1 : 0),
                                  compactWidth: state.compactWidth))
                .opacity(reduceMotion && !state.revealed ? 0 : 1)
                .allowsHitTesting(state.revealed)
                .accessibilityHidden(!state.revealed)

            ZStack {
                UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9).fill(.black)
                Button(action: onEdit) {
                    Capsule().fill(Color(red: 0.88, green: 0.75, blue: 0.35))
                        .frame(width: 28, height: 3).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("展开 NotchNote 便笺")
            }
            .frame(width: state.compactWidth, height: 10)
            .opacity(state.revealed ? 0 : 1)
            .allowsHitTesting(!state.revealed)
            .accessibilityHidden(state.revealed)
        }
        .frame(width: state.surfaceSize.width, height: state.surfaceSize.height, alignment: .top)
        .environment(\.colorScheme, .light)
    }

    private var expandedSurface: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "note.text").foregroundStyle(.yellow.opacity(0.85))
                Text("NotchNote").font(.system(size: 12, weight: .medium))
                Spacer()
                Text(state.isPinned ? "已固定" : "移开后自动收起")
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                Button(action: onTogglePin) {
                    Image(systemName: state.isPinned ? "pin.fill" : "pin").frame(width: 24, height: 24)
                        .foregroundStyle(state.isPinned ? .yellow : .white)
                }.help(state.isPinned ? "取消固定，恢复自动收起" : "固定便笺，移开鼠标也保留")
                    .accessibilityLabel(state.isPinned ? "取消固定便笺" : "固定便笺")
                Button(action: onClose) { Image(systemName: "chevron.up").frame(width: 24, height: 24) }
                    .help("收起 · Esc").accessibilityLabel("收起便笺")
            }
            .foregroundStyle(.white).buttonStyle(.plain).padding(.horizontal, 18)
            .frame(height: NotchMotion.headerHeight)
            .opacity(state.revealed ? 1 : 0)

            paperContents
                .frame(height: state.surfaceSize.height - NotchMotion.headerHeight)
                .offset(y: reduceMotion || state.revealed ? 0 : -(state.surfaceSize.height - NotchMotion.headerHeight))
                .clipped()
        }
        .frame(width: state.surfaceSize.width, height: state.surfaceSize.height)
    }

    private var paperContents: some View {
        HStack(spacing: 0) {
            notePaper
            ProjectBookmarks(store: store, onSelect: onSelectSection, onAdd: onAddSection, onInteraction: onInteraction)
        }
    }

    private var notePaper: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(store.selectedSection.title)
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 4)
                if store.pendingCount > 0 {
                    Text("\(store.pendingCount) 件待办")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(ink.opacity(0.6))
                }
            }.padding(.bottom, 12)

            if state.contentMode == .editing && state.showingEditor {
                FormattingBar(state: state, onCommand: { command in
                    state.formatCommand = command
                    state.formatID += 1
                }, onInteraction: onInteraction)
                ZStack(alignment: .topLeading) {
                    if store.text.isEmpty {
                        Text("写下此刻想到的事…\n\n不必整理好，先记下来。")
                            .font(.system(size: 15)).lineSpacing(7)
                            .foregroundStyle(ink.opacity(0.4)).padding(.top, 10).padding(.leading, 6)
                            .allowsHitTesting(false)
                    }
                    editor
                }
            } else {
                preview
            }

            Divider().overlay(ink.opacity(0.08)).padding(.top, 10)
            HStack(spacing: 12) {
                if state.contentMode == .editing {
                    Button {
                        state.showingEditor.toggle()
                        state.focusID += 1
                    } label: {
                        Label(state.showingEditor ? "勾选待办" : "继续写",
                              systemImage: state.showingEditor ? "checklist" : "pencil")
                    }.help("切换编辑和可勾选的预览")
                    if state.showingEditor {
                        Button { state.taskID += 1 } label: { Image(systemName: "checkmark.square") }
                            .help("将当前行转为待办 · ⌘⇧L").accessibilityLabel("切换当前行为待办")
                    }
                } else {
                    Button(action: onEdit) { Label("点击开始写", systemImage: "pencil") }
                }
                Spacer(minLength: 0)
                Button(action: onExport) { Image(systemName: "square.and.arrow.up") }
                    .help("导出全部栏目，可保留文字格式").accessibilityLabel("导出全部栏目")
                Text(store.saveError == nil ? (store.savedAt == nil ? "本机保存" : "已保存") : "保存异常")
                    .foregroundStyle(store.saveError == nil ? ink.opacity(0.45) : .red)
            }
            .font(.system(size: 11)).buttonStyle(.plain).padding(.top, 12)

            if let error = store.saveError {
                Text(error).font(.system(size: 10)).foregroundStyle(.red).padding(.top, 8)
            } else if state.contentMode == .editing {
                Text(state.shortcutAvailable ? "⌃⌥空格 随时唤出  ·  Esc 收起  ·  ⌘⇧L 待办" : "快捷键被占用，可通过菜单栏打开")
                    .font(.system(size: 10)).foregroundStyle(ink.opacity(0.4)).padding(.top, 8)
            }
        }
        .foregroundStyle(ink).padding(20).background(paper)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
        .padding([.leading, .bottom], 6)
    }

    private var editor: some View {
        let id = store.selectedID
        return NoteEditor(content: store.attributedText(in: id), focusID: state.focusID, taskID: state.taskID,
                          formatID: state.formatID, command: state.formatCommand,
                          onChange: { value in
                              store.updateRichText(value, in: id)
                              return store.attributedText(in: id)
                          },
                          onStyleChange: { if state.editorStyle != $0 { state.editorStyle = $0 } }, onEscape: onEscape)
            .id(id)
    }

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                if store.text.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("把脑子里的事，暂放在这里。")
                            .font(.system(size: 16, weight: .medium))
                        Text("一件待办、一闪而过的想法，\n或只是一句给自己的提醒。")
                            .font(.system(size: 14)).lineSpacing(5).foregroundStyle(ink.opacity(0.55))
                        Button("写下第一句", action: onEdit)
                            .buttonStyle(.borderedProminent).tint(Color(red: 0.85, green: 0.69, blue: 0.25))
                            .foregroundStyle(ink).padding(.top, 8)
                    }.padding(.top, 20)
                } else {
                    ForEach(RichText.lines(store.attributedText(in: store.selectedID))) { rendered in
                        let line = rendered.line
                        HStack(alignment: .top, spacing: 10) {
                            if line.isTask {
                                Button {
                                    store.toggle(line.id)
                                } label: {
                                    Image(systemName: line.isDone ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 17)).foregroundStyle(line.isDone ? ink.opacity(0.35) : ink.opacity(0.65))
                                        .frame(width: 24, height: 23)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(line.isDone ? "标记未完成：\(line.text)" : "完成：\(line.text)")
                            }
                            Text(line.text.isEmpty ? AttributedString(" ") : rendered.text)
                                .font(.system(size: 15)).lineSpacing(4)
                                .strikethrough(line.isDone).opacity(line.isDone ? 0.4 : 1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle()).onTapGesture(perform: onEdit)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }
        .id(store.selectedID)
    }
}
