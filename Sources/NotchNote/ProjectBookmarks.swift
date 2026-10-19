import SwiftUI

struct ProjectBookmarks: View {
    @Bindable var store: NoteStore
    let onSelect: (UUID) -> Void
    let onAdd: (String) -> Void
    let onOpenScratch: () -> Void
    let onRestore: (UUID) -> Void
    let onInteraction: (String, Bool) -> Void
    @State private var showingNewSection = false
    @State private var newTitle = ""
    @State private var showingDeleted = false
    @FocusState private var nameFocused: Bool

    private let colors: [Color] = [
        Color(red: 0.96, green: 0.84, blue: 0.53),
        Color(red: 0.72, green: 0.83, blue: 0.66),
        Color(red: 0.70, green: 0.82, blue: 0.94),
        Color(red: 0.96, green: 0.76, blue: 0.63),
        Color(red: 0.81, green: 0.75, blue: 0.92),
        Color(red: 0.65, green: 0.84, blue: 0.81),
        Color(red: 0.94, green: 0.73, blue: 0.80)
    ]

    var body: some View {
        VStack(spacing: 4) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 5) {
                    if let meetings = store.sections.first(where: { $0.id == store.meetingsSectionID }) { bookmark(meetings) }
                    if let scratch = store.sections.first(where: { $0.id == store.scratchSectionID }) { bookmark(scratch) }
                    else {
                        Button(action: onOpenScratch) {
                            Text("随手记").font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.black.opacity(0.7)).frame(maxWidth: .infinity).frame(height: 42)
                                .background(colors[1].opacity(0.78))
                                .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 8, topTrailingRadius: 8))
                        }.buttonStyle(.plain).help("零散的小任务和临时想法都放这里")
                            .accessibilityLabel("打开随手记，记录零散任务")
                    }
                    ForEach(store.sections.filter { $0.id != store.meetingsSectionID && $0.id != store.scratchSectionID }) { section in bookmark(section) }
                }.padding(.top, 12).padding(.leading, 4)
            }
            HStack(spacing: 0) { addButton; trashButton }
                .padding(.leading, 4).padding(.bottom, 6)
        }
        .frame(width: 68).padding(.trailing, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("项目索引签")
        .onChange(of: showingNewSection) { _, visible in onInteraction("newSection", visible) }
        .onChange(of: showingDeleted) { _, visible in onInteraction("deletedSections", visible) }
    }

    private var addButton: some View {
        Button {
            onSelect(store.selectedID)
            newTitle = ""
            showingNewSection = true
        } label: {
            Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.65)).frame(maxWidth: .infinity).frame(height: 28)
        }
        .buttonStyle(.plain).help("添加新栏目").accessibilityLabel("添加新栏目")
        .popover(isPresented: $showingNewSection, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 12) {
                Text("贴一张新索引签").font(.headline)
                TextField("栏目名称", text: $newTitle)
                    .textFieldStyle(.roundedBorder).focused($nameFocused)
                    .onSubmit(createSection)
                HStack {
                    Button("取消") { showingNewSection = false }
                    Spacer()
                    Button("添加", action: createSection)
                        .keyboardShortcut(.defaultAction)
                        .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(18).frame(width: 240)
                .onAppear { nameFocused = true }
        }
    }

    private var trashButton: some View {
        Button { showingDeleted = true } label: {
            HStack(spacing: 3) {
                Image(systemName: "trash")
                if !store.deletedSections.isEmpty { Text("\(store.deletedSections.count)").font(.system(size: 9)) }
            }.font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                .frame(maxWidth: .infinity).frame(height: 26)
        }.buttonStyle(.plain).help("已删除项目，可恢复")
            .accessibilityLabel("已删除项目，\(store.deletedSections.count) 个")
            .popover(isPresented: $showingDeleted, arrowEdge: .trailing) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("已删除项目").font(.headline)
                    if store.deletedSections.isEmpty {
                        Text("暂无已删除项目").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        Text("恢复时保留文字、格式和会议时间；提醒恢复为关闭，可重新开启。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(store.deletedSections) { deleted in
                                    HStack {
                                        Text(deleted.section.title).font(.system(size: 12)).lineLimit(2)
                                        Spacer()
                                        Button("恢复") { showingDeleted = false; onRestore(deleted.id) }
                                            .accessibilityLabel("恢复项目：\(deleted.section.title)")
                                    }
                                }
                            }
                        }.frame(height: min(200, CGFloat(store.deletedSections.count) * 40))
                    }
                }.padding(16).frame(width: 250)
            }
    }

    private func bookmark(_ section: NoteSection) -> some View {
        let selected = section.id == store.selectedID
        let count = store.pendingCount(in: section)
        let color = colors[(section.tint % colors.count + colors.count) % colors.count]
        return Button { if section.id == store.scratchSectionID { onOpenScratch() } else { onSelect(section.id) } } label: {
            HStack(spacing: 2) {
                Text(section.title).font(.system(size: 11, weight: selected ? .bold : .medium))
                    .lineLimit(2).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if count > 0 {
                    Text(count > 99 ? "99+" : "\(count)")
                        .font(.system(size: 9, weight: .semibold)).opacity(0.65)
                }
            }
            .foregroundStyle(Color.black.opacity(selected ? 0.85 : 0.65))
            .padding(.horizontal, 6).frame(height: 42)
            .background(color.opacity(selected ? 1 : 0.78))
            .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 8, topTrailingRadius: 8))
            .overlay(alignment: .leading) {
                if selected { Rectangle().fill(.black.opacity(0.18)).frame(width: 3) }
            }
            .offset(x: selected ? -4 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(section.title) · \(count) 件待办")
        .accessibilityLabel("显示栏目：\(section.title)")
        .accessibilityValue(selected ? "已选中，\(count) 件待办" : "\(count) 件待办")
    }

    private func createSection() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        showingNewSection = false
        onAdd(title)
    }
}
