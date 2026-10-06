import SwiftUI

// MARK: - Shared pieces

extension Date {
    /// Same clock time on another day.
    func onDay(_ day: Date) -> Date {
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute], from: self)
        return cal.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: day) ?? self
    }
}

/// v34: Apple style. A segmented control (Today · Tomorrow · Other) and a Date row with the system
/// date pill. Two Form rows (the Group flattens into the Section).
struct DayPicker: View {
    @Binding var day: Date

    private enum Choice: Hashable { case today, tomorrow, other }
    private var cal: Calendar { .current }

    private var choice: Binding<Choice> {
        Binding {
            cal.isDateInToday(day) ? .today : cal.isDateInTomorrow(day) ? .tomorrow : .other
        } set: { c in
            switch c {
            case .today: day = .now
            case .tomorrow: day = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
            case .other:
                if cal.isDateInToday(day) || cal.isDateInTomorrow(day) {
                    day = cal.date(byAdding: .day, value: 2, to: .now) ?? .now
                }
            }
        }
    }

    var body: some View {
        Group {
            Picker("Day", selection: choice) {
                Text("Today").tag(Choice.today)
                Text("Tomorrow").tag(Choice.tomorrow)
                Text("Other").tag(Choice.other)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            DatePicker("Date", selection: $day, in: cal.startOfDay(for: .now)..., displayedComponents: [.date])
        }
    }
}

/// v34: iOS 26 sheet buttons: round glass ✕ and a blue ✓. Words on older iOS.
struct SheetCloseButton: View {
    var title = "Cancel"
    let action: () -> Void
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .close, action: action)
        } else {
            Button(title, action: action)
        }
    }
}

struct SheetConfirmButton: View {
    var title = "Add"
    var disabled = false
    let action: () -> Void
    var body: some View {
        if #available(iOS 26.0, *) {
            Button(role: .confirm, action: action).disabled(disabled)
        } else {
            Button(title, action: action).disabled(disabled)
        }
    }
}

/// v34: "Ends   12:20 AM" as a plain Form row, value on the right in grey.
struct EndsRow: View {
    let end: Date
    var body: some View {
        HStack {
            Text("Ends")
            Spacer()
            Text(end.shortTime).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

/// Pick any number of categories. The first one picked sets the color. None = automatic (rules).
struct MultiCategoryChips: View {
    @Binding var selection: [String]
    let autoName: String
    @ObservedObject private var store = CategoryStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 8) {
                Chip(title: "Auto · \(autoName)", selected: selection.isEmpty) { selection = [] }
                ForEach(store.categories) { c in
                    let on = selection.contains(c.id)
                    Chip(title: selection.first == c.id && selection.count > 1 ? "\(c.name) · color" : c.name,
                         color: c.color, selected: on, icon: c.iconName) {
                        if on { selection.removeAll { $0 == c.id } } else { selection.append(c.id) }
                    }
                }
            }
            if selection.count > 1 {
                Text("The first one you picked sets the color. Stats split the time evenly between them.")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

// MARK: - Add block

/// "+" -> title, date, start, length, categories -> Add.
struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    @State private var title = ""
    @State private var day = QuickAddSheet.nextFiveMinutes()   // same day as the default start (23:56 → tomorrow)
    @State private var start = QuickAddSheet.nextFiveMinutes()
    @State private var minutes = 60
    @State private var categoryIDs: [String] = []

    private var startOnDay: Date { start.onDay(day) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("What are you doing?", text: $title)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit(add)

                Section("Date") {
                    DayPicker(day: $day)
                }

                Section("Time") {
                    DatePicker("Start", selection: $start, displayedComponents: [.hourAndMinute])
                    // v32: Apple Timer–style ruler instead of fixed segments.
                    HStack(alignment: .firstTextBaseline) {
                        Text("Length")
                        Spacer()
                        DurationReadout(minutes: minutes)
                    }
                    DurationRuler(minutes: $minutes)
                    EndsRow(end: startOnDay.addingTimeInterval(TimeInterval(minutes * 60)))
                }

                Section("Categories") {
                    MultiCategoryChips(
                        selection: $categoryIDs,
                        autoName: CategoryStore.shared.ruleCategory(title: title, calendarName: nil).name
                    )
                    .padding(.vertical, 4)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.section)
            .navigationTitle("Add block")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton(title: "Add", disabled: title.trimmingCharacters(in: .whitespaces).isEmpty, action: add)
                }
            }
            .onAppear { titleFocused = true }
        }
    }

    private func add() {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        BlockStore.shared.add(title: title, start: startOnDay, minutes: minutes, categoryIDs: categoryIDs)
        Task { await LiveActivityManager.shared.refresh() }
        dismiss()
    }

    private static func nextFiveMinutes() -> Date {
        let t = (Date.now.timeIntervalSinceReferenceDate / 300).rounded(.up) * 300
        return Date(timeIntervalSinceReferenceDate: t)
    }
}

// MARK: - Edit block

/// Tap a block -> edit it. Planned blocks: title, date, time, categories, steps, start, move, delete.
/// Calendar events: categories, steps and Start only (the event itself is edited in the Calendar app).
struct BlockEditorSheet: View {
    let block: Block
    var onDelete: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var day: Date
    @State private var start: Date
    @State private var minutes: Int
    @State private var steps: [Step]
    @State private var categoryIDs: [String]
    @State private var newStep = ""
    @FocusState private var newStepFocused: Bool

    private let originalMinutes: Int

    init(block: Block, steps: [Step], categoryIDs: [String] = [], onDelete: @escaping () -> Void = {}) {
        self.block = block
        self.onDelete = onDelete
        let mins = max(5, Int((block.duration / 60).rounded()))
        originalMinutes = mins
        _title = State(initialValue: block.title)
        _day = State(initialValue: block.start)
        _start = State(initialValue: block.start)
        _minutes = State(initialValue: mins)
        _steps = State(initialValue: steps)
        _categoryIDs = State(initialValue: categoryIDs)
    }

    private var isPlan: Bool { block.source == .plan }
    private var startOnDay: Date { start.onDay(day) }
    private var canStart: Bool { block.end > .now }

    var body: some View {
        NavigationStack {
            Form {
                if isPlan {
                    Section { TextField("Title", text: $title) } header: { Text("Title") }
                    Section { DayPicker(day: $day) } header: { Text("1 · Date") }
                    Section {
                        DatePicker("Start", selection: $start, displayedComponents: [.hourAndMinute])
                        HStack(alignment: .firstTextBaseline) {
                            Text("Length")
                            Spacer()
                            DurationReadout(minutes: minutes)
                        }
                        DurationRuler(minutes: $minutes)
                        EndsRow(end: startOnDay.addingTimeInterval(TimeInterval(minutes * 60)))
                    } header: { Text("2 · Time") }
                } else {
                    Section {
                        Text(block.title).font(.headline)
                        Text("\(block.start.shortTime) – \(block.end.shortTime)")
                            .foregroundStyle(.secondary)
                    } footer: {
                        Text("From your calendar. Change the time in the Calendar app; steps and categories are saved in Hyperday.")
                    }
                }
                PhotosSection(blockID: block.id)   // v36: photos kept as is

                Section {
                    MultiCategoryChips(
                        selection: $categoryIDs,
                        autoName: CategoryStore.shared.ruleCategory(title: block.title, calendarName: block.calendarName).name
                    )
                    .padding(.vertical, 4)
                } header: {
                    Text(isPlan ? "3 · Categories · pick any" : "Categories · pick any")
                }

                Section {
                    ForEach($steps) { $step in
                        HStack(spacing: 12) {
                            Button {
                                step.done.toggle()
                            } label: {
                                HDIcon(step.done ? "step-done" : "step-open", size: 24)
                                    .foregroundStyle(step.done ? DayLiveStyle.accent : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(step.done ? "Mark not done" : "Mark done")
                            TextField("Step", text: $step.title)
                                .strikethrough(step.done)
                        }
                    }
                    .onDelete { steps.remove(atOffsets: $0) }

                    HStack(spacing: 12) {
                        HDIcon("step-add", size: 24)
                            .foregroundStyle(.secondary)
                        TextField("Add a step", text: $newStep)
                            .focused($newStepFocused)
                            .submitLabel(.next)
                            .onSubmit(addStep)
                    }
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Each step is one segment on your Lock Screen while this block is on. Swipe left to delete.")
                }

                Section {
                    if canStart {
                        Button {
                            save(startNow: true)
                        } label: {
                            Label { Text("Start now") } icon: { HDIcon("start") }
                        }
                    }
                    if isPlan {
                        Button {
                            save(moveDays: 1)
                        } label: {
                            Label { Text("Move to tomorrow") } icon: { HDIcon("move") }
                        }
                        Button("Delete block", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                } footer: {
                    if canStart {
                        Text("Start now runs the timer from this moment for the block's length (\(lengthText)).")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.section)
            .navigationTitle(isPlan ? "Edit block" : "Steps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton(title: "Save", disabled: isPlan && title.trimmingCharacters(in: .whitespaces).isEmpty) { save() }
                }
            }
        }
    }

    private var lengthText: String {
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    private func addStep() {
        let clean = newStep.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        steps.append(Step(title: clean))
        newStep = ""
        newStepFocused = true   // keep typing the next step
    }

    private func save(startNow: Bool = false, moveDays: Int = 0) {
        addStep()   // don't lose a step typed but not submitted
        let store = BlockStore.shared
        if isPlan {
            let changed = title != block.title || startOnDay != block.start || minutes != originalMinutes
            // Only rewrite the block when something changed, so a running timer isn't reset by editing steps.
            if changed { store.update(id: block.id, title: title, start: startOnDay, minutes: minutes) }
            if moveDays != 0 { store.move(id: block.id, byDays: moveDays) }
        }
        store.setSteps(steps, for: block.id)
        store.setCategories(categoryIDs, for: block.id)
        if startNow { store.start(blockID: block.id, at: .now) }
        Task { await LiveActivityManager.shared.refresh() }
        dismiss()
    }
}
