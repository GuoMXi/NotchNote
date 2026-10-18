import SwiftUI

enum PanelMode { case collapsed, preview, editing }

@Observable final class PanelState {
    var mode = PanelMode.collapsed
    var focusID = 0
    var taskID = 0
    var showingEditor = true
    var shortcutAvailable = true
}

struct NotchView: View {
    @Bindable var store: NoteStore
    @Bindable var state: PanelState
    let onHover: (Bool) -> Void
    let onEdit: () -> Void
    let onClose: () -> Void
    let onExport: () -> Void

    private let paper = Color(red: 0.98, green: 0.97, blue: 0.92)
    private let ink = Color(red: 0.18, green: 0.19, blue: 0.17)

    var body: some View {
        Group {
            if state.mode == .collapsed {
                Button(action: onEdit) {
                    Capsule().fill(Color(red: 0.88, green: 0.75, blue: 0.35))
                        .frame(width: 28, height: 3).frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("展开 NotchNote 便笺")
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "note.text").foregroundStyle(.yellow.opacity(0.85))
                        Text("NotchNote").font(.system(size: 12, weight: .medium))
                        Spacer()
                        Text(state.mode == .editing ? "安心写，已保持展开" : "随手记，慢慢做")
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
                        Button(action: onClose) { Image(systemName: "chevron.up").frame(width: 24, height: 24) }
                            .help("收起 · Esc").accessibilityLabel("收起便笺")
                    }
                    .foregroundStyle(.white).buttonStyle(.plain).padding(.horizontal, 18).frame(height: 42)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("留在这里，就不会忘。")
                                .font(.system(size: 20, weight: .semibold))
                            Spacer(minLength: 4)
                            if store.pendingCount > 0 {
                                Text("\(store.pendingCount) 件待办")
                                    .font(.system(size: 11, weight: .medium)).foregroundStyle(ink.opacity(0.6))
                            }
                        }.padding(.bottom, 12)

                        if state.mode == .editing && state.showingEditor {
                            ZStack(alignment: .topLeading) {
                                if store.text.isEmpty {
                                    Text("写下此刻想到的事…\n\n不必整理好，先记下来。")
                                        .font(.system(size: 15)).lineSpacing(7)
                                        .foregroundStyle(ink.opacity(0.4)).padding(.top, 10).padding(.leading, 6)
                                        .allowsHitTesting(false)
                                }
                                NoteEditor(text: $store.text, focusID: state.focusID,
                                           taskID: state.taskID, onEscape: onClose)
                            }
                        } else {
                            preview
                        }

                        Divider().overlay(ink.opacity(0.08)).padding(.top, 10)
                        HStack(spacing: 12) {
                            if state.mode == .editing {
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
                                .help("导出纯文本备份").accessibilityLabel("导出便笺")
                            Text(store.saveError == nil ? (store.savedAt == nil ? "本机保存" : "已保存") : "保存异常")
                                .foregroundStyle(store.saveError == nil ? ink.opacity(0.45) : .red)
                        }
                        .font(.system(size: 11)).buttonStyle(.plain).padding(.top, 12)

                        if let error = store.saveError {
                            Text(error).font(.system(size: 10)).foregroundStyle(.red).padding(.top, 8)
                        } else if state.mode == .editing {
                            Text(state.shortcutAvailable ? "⌃⌥空格 随时唤出  ·  Esc 收起  ·  ⌘⇧L 待办" : "快捷键被占用，可通过菜单栏打开")
                                .font(.system(size: 10)).foregroundStyle(ink.opacity(0.4)).padding(.top, 8)
                        }
                    }
                    .foregroundStyle(ink).padding(20).background(paper)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18))
                    .padding([.horizontal, .bottom], 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: state.mode == .collapsed ? 9 : 24,
                                        bottomTrailingRadius: state.mode == .collapsed ? 9 : 24))
        .onHover(perform: onHover)
        .environment(\.colorScheme, .light)
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
                    ForEach(store.lines) { line in
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
                            Text(line.text.isEmpty ? " " : line.text)
                                .font(.system(size: 15)).lineSpacing(4)
                                .strikethrough(line.isDone).foregroundStyle(ink.opacity(line.isDone ? 0.35 : 1))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle()).onTapGesture(perform: onEdit)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        }
    }
}
