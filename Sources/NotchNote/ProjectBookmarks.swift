import SwiftUI

struct ProjectBookmarks: View {
    @Bindable var store: NoteStore
    let onSelect: (UUID) -> Void
    let onAdd: (String) -> Void
    @State private var showingNewSection = false
    @State private var newTitle = ""
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
        ScrollView(showsIndicators: false) {
            VStack(spacing: 5) {
                ForEach(store.sections) { section in bookmark(section) }

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
            }.padding(.top, 12).padding(.leading, 4).padding(.bottom, 6)
        }
        .frame(width: 68).padding(.trailing, 6)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("项目索引签")
    }

    private func bookmark(_ section: NoteSection) -> some View {
        let selected = section.id == store.selectedID
        let count = store.pendingCount(in: section)
        let color = colors[(section.tint % colors.count + colors.count) % colors.count]
        return Button { onSelect(section.id) } label: {
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
