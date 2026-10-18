import SwiftUI

nonisolated enum MeetingCalendarMath {
    static func days(in month: Date, calendar: Calendar) -> [Date] {
        guard let start = calendar.dateInterval(of: .month, for: month)?.start,
              let range = calendar.range(of: .day, in: .month, for: start) else { return [] }
        let leading = (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
        let count = ((leading + range.count + 6) / 7) * 7
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0 - leading, to: start) }
    }

    static func selecting(_ day: Date, keepingTimeOf selection: Date, calendar: Calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute], from: selection)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }
}

/// A full-width calendar with no enclosing field or focus border.
struct MeetingCalendar: View {
    @Binding var selection: Date
    @State private var month: Date
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.firstWeekday = 1
        return value
    }

    init(selection: Binding<Date>) {
        _selection = selection
        _month = State(initialValue: selection.wrappedValue)
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 2) {
                Text("\(String(calendar.component(.year, from: month)))年\(calendar.component(.month, from: month))月")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                monthButton("chevron.left", label: "上个月", offset: -1)
                Button("今天") { choose(.now) }
                    .font(.system(size: 10)).frame(width: 28, height: 24)
                    .help("选择今天，保留已选时间")
                monthButton("chevron.right", label: "下个月", offset: 1)
            }.buttonStyle(.plain)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(["日", "一", "二", "三", "四", "五", "六"].enumerated()), id: \.offset) { _, day in
                    Text(day).font(.system(size: 10)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity).frame(height: 18)
                        .accessibilityHidden(true)
                }
                ForEach(MeetingCalendarMath.days(in: month, calendar: calendar), id: \.self) { day in
                    let selected = calendar.isDate(day, inSameDayAs: selection)
                    let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
                    Button { choose(day) } label: {
                        Text("\(calendar.component(.day, from: day))")
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.white : (inMonth ? Color.primary : Color.secondary.opacity(0.45)))
                            .frame(maxWidth: .infinity).frame(height: 26)
                            .background(selected ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(day.formatted(.dateTime.year().month().day().weekday().locale(Locale(identifier: "zh_CN"))))
                        .accessibilityValue(selected ? "已选择" : "未选择")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
        .onChange(of: selection) { _, value in
            if !calendar.isDate(value, equalTo: month, toGranularity: .month) { month = value }
        }
    }

    private func monthButton(_ symbol: String, label: String, offset: Int) -> some View {
        Button {
            if let next = calendar.date(byAdding: .month, value: offset, to: calendar.dateInterval(of: .month, for: month)?.start ?? month) {
                month = next
            }
        } label: {
            Image(systemName: symbol).font(.system(size: 10, weight: .medium)).frame(width: 22, height: 24)
        }.accessibilityLabel(label).help(label)
    }

    private func choose(_ day: Date) {
        selection = MeetingCalendarMath.selecting(day, keepingTimeOf: selection, calendar: calendar)
        month = day
    }
}
