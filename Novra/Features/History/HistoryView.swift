import SwiftUI
import Charts

struct HistoryView: View {
    var history = History.shared
    @State private var expanded: Set<UUID> = []
    @State private var message: String?

    private struct Day: Identifiable {
        let date: Date
        let freed: Int64
        var id: Date { date }
    }

    private var lastMonth: [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let byDay = Dictionary(grouping: history.records.filter { !$0.restored }) { calendar.startOfDay(for: $0.date) }
        return (0..<30).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return Day(date: day, freed: byDay[day]?.map(\.freed).sum ?? 0)
        }
    }

    private var thisMonth: Int64 {
        let start = Calendar.current.dateInterval(of: .month, for: .now)?.start ?? .now
        return history.records.filter { !$0.restored && $0.date >= start }.map(\.freed).sum
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "History", subtitle: "Everything Novra removed, kept only on this Mac. Bring back anything still in the Trash.")
                    .reveal()
                if let message {
                    Label(message, systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.green)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if history.records.isEmpty {
                    EmptyState(icon: "clock.arrow.circlepath", title: "Nothing cleaned yet",
                               message: "After your first clean, you'll see what went and how much space you got back.")
                        .frame(height: 360)
                } else {
                    summary.reveal(delay: 0.05)
                    chart.reveal(delay: 0.1)
                    VStack(spacing: 10) {
                        ForEach(Array(history.records.enumerated()), id: \.element.id) { index, record in
                            RecordCard(record: record, isOpen: expanded.contains(record.id),
                                       onToggle: { withAnimation(.snappy) { toggle(record.id) } },
                                       onRestore: { restore(record) })
                                .contextMenu {
                                    Button("Remove from History", role: .destructive) {
                                        withAnimation(.snappy) { history.forget(record.id) }
                                    }
                                }
                                .reveal(delay: 0.12 + Double(min(index, 10)) * 0.03)
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            stat("Freed all time", history.totalFreed.byteString, Theme.green)
            stat("This month", thisMonth.byteString, Theme.accent)
            stat("Cleans", "\(history.records.count)", Theme.lavender)
        }
    }

    private func stat(_ title: LocalizedStringKey, _ value: String, _ tint: Color) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 12)).foregroundStyle(Theme.secondary)
                Text(value).font(.system(size: 24, weight: .bold, design: .rounded)).foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var chart: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Last 30 days").font(.system(size: 13, weight: .semibold))
                Chart(lastMonth) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Freed", Double(day.freed) / 1e9))
                        .foregroundStyle(LinearGradient(colors: [Theme.accentDeep, Theme.accent], startPoint: .bottom, endPoint: .top))
                        .cornerRadius(3)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine().foregroundStyle(.white.opacity(0.06))
                        AxisValueLabel { if let gb = value.as(Double.self) { Text("\(gb, specifier: "%.0f") GB") } }
                            .foregroundStyle(Theme.tertiary)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.tertiary)
                    }
                }
                .frame(height: 150)
            }
        }
    }

    private func toggle(_ id: UUID) {
        if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) }
    }

    private func restore(_ record: CleanRecord) {
        let result = history.restore(record)
        withAnimation(.snappy) {
            message = result.failed == 0
                ? String(localized: "Restored \(result.restored) items to where they were.")
                : String(localized: "Restored \(result.restored) items. \(result.failed) couldn't go back because something else is in their place.")
        }
    }
}

private struct RecordCard: View {
    var record: CleanRecord
    var isOpen: Bool
    var onToggle: () -> Void
    var onRestore: () -> Void

    var body: some View {
        let restorable = record.restorable.count
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    Image(systemName: record.restored ? "arrow.uturn.backward.circle.fill" : record.movedToTrash ? "trash.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white, record.restored ? Theme.lavender : record.movedToTrash ? Theme.accent : Theme.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(record.source) · \(record.items.count) items").font(.system(size: 13.5, weight: .semibold))
                        Text(record.date.formatted(date: .abbreviated, time: .shortened) + " · " + record.date.relativeString)
                            .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                    }
                    Spacer()
                    if record.restored {
                        Text("Restored").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.lavender)
                    } else if restorable > 0 {
                        Button("Restore \(restorable)", action: onRestore).buttonStyle(PillButtonStyle(prominent: false))
                    } else if record.movedToTrash {
                        Text("Trash emptied").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                    }
                    SizeLabel(size: record.freed, tint: record.restored ? Theme.tertiary : Theme.green)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
                .onTapGesture(perform: onToggle)
                if isOpen {
                    Divider().overlay(Theme.stroke)
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(record.items.prefix(200), id: \.self) { item in
                            HStack {
                                Text(URL(filePath: item.original).tildePath)
                                    .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.secondary)
                                    .lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text(item.size.byteString).font(.system(size: 11.5, design: .rounded)).foregroundStyle(Theme.tertiary)
                            }
                        }
                        if record.items.count > 200 {
                            Text("and \(record.items.count - 200) more").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }
}
