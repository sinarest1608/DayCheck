import SwiftUI

/// Marker value for pushing `HistoryView` via `NavigationLink(value:)`.
/// Every destination in this flow (this, and `Date` for `WeekDetailView`) is
/// registered on the single owning `NavigationStack` in `ContentView` — mixing
/// the old closure-style `NavigationLink` for one level with value-based
/// `navigationDestination` for a nested level breaks destination lookup for
/// the nested push (it renders a blank placeholder instead of the real view).
struct HistoryRoute: Hashable {}

struct HistoryView: View {
    var historyStore: HistoryStore

    // Multi-select is hand-rolled rather than using List(selection:) + EditMode:
    // that combo doesn't reliably surface selection circles or the delete bar
    // in this build, so selection state and its checkmarks are managed directly.
    @State private var isSelecting = false
    @State private var selectedWeekStarts: Set<Date> = []
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        List {
            if historyStore.weeks.isEmpty {
                ContentUnavailableView(
                    "No History Yet",
                    systemImage: "calendar",
                    description: Text("Shared days will show up here, grouped by week.")
                )
            } else {
                ForEach(historyStore.weeks) { week in
                    row(for: week)
                }
                .onDelete(perform: deleteWeeks(at:))
            }
        }
        .navigationTitle("History")
        .toolbar {
            if !historyStore.weeks.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(isSelecting ? "Done" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting { selectedWeekStarts.removeAll() }
                    }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                if isSelecting && !selectedWeekStarts.isEmpty {
                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label(
                            "Delete \(selectedWeekStarts.count) Week\(selectedWeekStarts.count == 1 ? "" : "s")",
                            systemImage: "trash"
                        )
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete \(selectedWeekStarts.count) week\(selectedWeekStarts.count == 1 ? "" : "s")? This can't be undone.",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedWeekStarts.count) Week\(selectedWeekStarts.count == 1 ? "" : "s")", role: .destructive) {
                deleteWeeks(withStarts: selectedWeekStarts)
                selectedWeekStarts.removeAll()
                isSelecting = false
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func row(for week: WeekSummary) -> some View {
        if isSelecting {
            Button {
                if selectedWeekStarts.contains(week.weekStart) {
                    selectedWeekStarts.remove(week.weekStart)
                } else {
                    selectedWeekStarts.insert(week.weekStart)
                }
            } label: {
                HStack {
                    Image(systemName: selectedWeekStarts.contains(week.weekStart) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedWeekStarts.contains(week.weekStart) ? Color.accentColor : Color.secondary)
                    WeekRow(week: week)
                }
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: week.weekStart) {
                WeekRow(week: week)
            }
        }
    }

    /// Swipe-to-delete (like Notes): deletes immediately, no confirmation —
    /// matches the one-tap swipe-delete convention. The multi-select bulk
    /// delete above still confirms since it can remove many weeks at once.
    private func deleteWeeks(at offsets: IndexSet) {
        let weeks = historyStore.weeks
        deleteWeeks(withStarts: Set(offsets.map { weeks[$0].weekStart }))
    }

    private func deleteWeeks(withStarts starts: Set<Date>) {
        let datesToDelete = Set(
            historyStore.weeks
                .filter { starts.contains($0.weekStart) }
                .flatMap { $0.records.map(\.date) }
        )
        historyStore.delete(dates: datesToDelete)
    }
}

private struct WeekRow: View {
    let week: WeekSummary

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(Self.dateFormatter.string(from: week.weekStart)) – \(Self.dateFormatter.string(from: week.weekEnd))")
                .font(.headline)
            Text("\(week.daysLogged) day\(week.daysLogged == 1 ? "" : "s") logged")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                statText("👣", "\(Int(week.avgSteps.rounded()))")
                statText("💧", String(format: "%.1fL", week.avgWaterLiters))
                statText("⚖️", String(format: "%.1fKg", week.avgWeightKg))
                statText("🍽️", "\(Int(week.avgDietPercent.rounded()))%")
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func statText(_ emoji: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(emoji)
            Text(value)
        }
    }
}

struct WeekDetailView: View {
    var historyStore: HistoryStore
    let weekStart: Date

    @State private var isSelecting = false
    @State private var selectedDates: Set<Date> = []
    @State private var isShowingDeleteConfirmation = false

    private var week: WeekSummary? {
        historyStore.weeks.first { $0.weekStart == weekStart }
    }

    var body: some View {
        List {
            if let week {
                Section("Averages") {
                    LabeledContent("Steps", value: "\(Int(week.avgSteps.rounded()))")
                    LabeledContent("Water", value: String(format: "%.1f L", week.avgWaterLiters))
                    LabeledContent("Weight", value: String(format: "%.1f Kg", week.avgWeightKg))
                    LabeledContent("Diet", value: "\(Int(week.avgDietPercent.rounded()))%")
                    LabeledContent("Supplements", value: "\(week.supplementsDays)/\(week.daysLogged) days")
                    LabeledContent("Chamomile Tea", value: "\(week.chamomileDays)/\(week.daysLogged) days")
                }

                Section("Days") {
                    ForEach(week.records) { record in
                        row(for: record)
                    }
                    .onDelete(perform: deleteDays(at:))
                }
            } else {
                ContentUnavailableView("No Days Left", systemImage: "calendar.badge.minus")
            }
        }
        .navigationTitle("Week of \(Self.weekTitleFormatter.string(from: weekStart))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let week, !week.records.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button(isSelecting ? "Done" : "Select") {
                        isSelecting.toggle()
                        if !isSelecting { selectedDates.removeAll() }
                    }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                if isSelecting && !selectedDates.isEmpty {
                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label(
                            "Delete \(selectedDates.count) Day\(selectedDates.count == 1 ? "" : "s")",
                            systemImage: "trash"
                        )
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete \(selectedDates.count) day\(selectedDates.count == 1 ? "" : "s")? This can't be undone.",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedDates.count) Day\(selectedDates.count == 1 ? "" : "s")", role: .destructive) {
                historyStore.delete(dates: selectedDates)
                selectedDates.removeAll()
                isSelecting = false
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func row(for record: DailyRecord) -> some View {
        let content = VStack(alignment: .leading, spacing: 4) {
            Text(Self.dayFormatter.string(from: record.date))
                .font(.subheadline.bold())
            Text("\(record.weightKg, specifier: "%.1f") Kg · \(record.waterLiters, specifier: "%.1f") L · \(Int(record.steps)) steps · Diet \(record.dietPercent)%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())

        if isSelecting {
            Button {
                if selectedDates.contains(record.date) {
                    selectedDates.remove(record.date)
                } else {
                    selectedDates.insert(record.date)
                }
            } label: {
                HStack {
                    Image(systemName: selectedDates.contains(record.date) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selectedDates.contains(record.date) ? Color.accentColor : Color.secondary)
                    content
                }
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    private func deleteDays(at offsets: IndexSet) {
        guard let week else { return }
        let dates = Set(offsets.map { week.records[$0].date })
        historyStore.delete(dates: dates)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter
    }()

    private static let weekTitleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()
}

#Preview {
    NavigationStack {
        HistoryView(historyStore: HistoryStore())
    }
}
