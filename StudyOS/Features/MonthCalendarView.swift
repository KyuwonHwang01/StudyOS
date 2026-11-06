import SwiftUI

struct MonthCalendarView: View {
    @Environment(StudyStore.self) private var store
    @Binding var selectedDay: Date
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { offset in
                    let index = (calendar.firstWeekday - 1 + offset) % 7
                    Text(calendar.veryShortStandaloneWeekdaySymbols[index])
                        .font(.caption2.weight(.semibold)).foregroundStyle(Water.secondary)
                        .frame(maxWidth: .infinity).accessibilityHidden(true)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(CalendarLayout.monthDays(containing: selectedDay), id: \.self) { date in
                    dayButton(date)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { taskLegend; deadlineLegend }
                VStack(alignment: .leading, spacing: 8) { taskLegend; deadlineLegend }
            }.font(.caption).foregroundStyle(Water.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        .padding(8).background(Water.surface, in: RoundedRectangle(cornerRadius: 26))
        .accessibilityElement(children: .contain).accessibilityIdentifier("monthCalendar")
    }

    private var taskLegend: some View { Label("Planned tasks", systemImage: "circle.fill").foregroundStyle(Water.accent) }
    private var deadlineLegend: some View { Label("Goal deadlines", systemImage: "diamond.fill").foregroundStyle(Water.warning) }

    private func dayButton(_ date: Date) -> some View {
        let selected = calendar.isDate(date, inSameDayAs: selectedDay)
        let inMonth = calendar.isDate(date, equalTo: selectedDay, toGranularity: .month)
        let taskCount = store.dayTasks(date).count
        let deadlineCount = store.goals.filter {
            !$0.isArchived && $0.completedAt == nil && $0.dueAt.map { calendar.isDate($0, inSameDayAs: date) } == true
        }.count
        return Button { selectedDay = calendar.startOfDay(for: date) } label: {
            VStack(spacing: 4) {
                Text(date.formatted(.dateTime.day())).font(.callout.weight(selected ? .semibold : .regular))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                HStack(spacing: 3) {
                    if taskCount > 0 { Circle().fill(selected ? Water.background : Water.accent).frame(width: 4, height: 4) }
                    if deadlineCount > 0 { Image(systemName: "diamond.fill").font(.system(size: 5)).foregroundStyle(selected ? Water.background : Water.warning) }
                }.frame(height: 5).accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(selected ? Water.background : inMonth ? Water.ink : Water.secondary)
            .background(selected ? Water.accent : .clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                if calendar.isDateInToday(date) && !selected { RoundedRectangle(cornerRadius: 12).stroke(Water.accent, lineWidth: 1).padding(1) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(date.formatted(date: .complete, time: .omitted))
        .accessibilityValue("\(taskCount) tasks, \(deadlineCount) goal deadlines")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("flowDay-\(StudyTime.dayKey(date))")
    }
}
