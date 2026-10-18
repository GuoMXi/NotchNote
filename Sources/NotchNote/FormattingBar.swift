import SwiftUI
import AppKit

struct FormattingBar: View {
    @Bindable var state: PanelState
    let store: NoteStore
    let reminders: MeetingReminders?
    let onCommand: (EditorCommand) -> Void
    let onInteraction: (String, Bool) -> Void

    var body: some View {
        HStack(spacing: 5) {
            Button { state.formattingPresented.toggle() } label: {
                HStack(spacing: 4) {
                    Text("Aa").font(.system(size: 13, weight: .medium))
                    Text("\(Int(state.editorStyle.size))").font(.system(size: 10))
                    Image(systemName: "chevron.down").font(.system(size: 8))
                }.padding(.horizontal, 7).frame(height: 26)
            }
            .help("字体、字号和文字颜色").accessibilityLabel("字体与颜色")
            .popover(isPresented: $state.formattingPresented, arrowEdge: .bottom) { controls }
            styleButton("bold", name: "加粗", shortcut: "⌘B", active: state.editorStyle.bold, command: .bold)
            styleButton("italic", name: "斜体", shortcut: "⌘I", active: state.editorStyle.italic, command: .italic)
            styleButton("underline", name: "下划线", shortcut: "⌘U", active: state.editorStyle.underline, command: .underline)
            Button { onCommand(.meeting) } label: {
                Label("会议", systemImage: "calendar").font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 5).frame(height: 26)
                    .background(state.editorStyle.meeting ? Color.orange.opacity(0.2) : Color.black.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: 5))
            }.help("标记或取消当前行为会议 · ⌘⇧M")
                .accessibilityLabel("切换当前行为会议")
                .accessibilityValue(state.editorStyle.meeting ? "已标记" : "未标记")
            if let reference = store.reference(forLine: state.editorStyle.lineIndex, in: store.selectedID) {
                MeetingScheduleButton(store: store, reference: reference, reminders: reminders,
                                      onInteraction: onInteraction, compact: false)
            }
            Spacer(minLength: 0)
            Text("选字设格式").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 6)
        .onChange(of: state.formattingPresented) { _, visible in onInteraction("format", visible) }
        .onDisappear { if state.formattingPresented { onInteraction("format", false) } }
    }

    private func styleButton(_ symbol: String, name: String, shortcut: String, active: Bool, command: EditorCommand) -> some View {
        Button { onCommand(command) } label: {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).frame(width: 26, height: 26)
                .background(active ? Color.yellow.opacity(0.4) : Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
        }.help("\(name) · \(shortcut)").accessibilityLabel(name).accessibilityValue(active ? "已启用" : "未启用")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("文字格式").font(.headline)
            Picker("字体", selection: Binding(get: { state.editorStyle.fontFamily }, set: { onCommand(.font($0)) })) {
                Text("系统字体").tag("")
                ForEach(NSFontManager.shared.availableFontFamilies.sorted(), id: \.self) { family in Text(family).tag(family) }
            }.pickerStyle(.menu)
            Stepper(value: Binding(get: { state.editorStyle.size }, set: { onCommand(.size($0)) }), in: 8...72) {
                Text("字号  \(Int(state.editorStyle.size)) pt")
            }
            Text("文字颜色").font(.system(size: 12, weight: .medium))
            HStack(spacing: 10) {
                ForEach(["292929", "C43D35", "AF681C", "2D7A51", "2764AB", "8550A4", "777777"], id: \.self) { hex in
                    Button { onCommand(.color(hex)) } label: {
                        Circle().fill(Color(nsColor: RichText.color(hex))).frame(width: 23, height: 23)
                            .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityLabel("文字颜色 \(hex)")
                }
            }
            Text("选中时修改选区；未选中时应用于接下来输入的文字。")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("完成") { state.formattingPresented = false } }
        }.padding(18).frame(width: 280)
    }
}
