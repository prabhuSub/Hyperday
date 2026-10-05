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

/// Today · Tomorrow · Pick date. Comes before the time.
struct DayPicker: View {
    @Binding var day: Date
    @State private var picking = false

    private var cal: Calendar { .current }
    private var isToday: Bool { cal.isDateInToday(day) }
    private var isTomorrow: Bool { cal.isDateInTomorrow(day) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                option("Today", on: isToday && !picking) {
                    picking = false
                    day = .now
                }
                option("Tomorrow", on: isTomorrow && !picking) {
                    picking = false
                    day = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
                }
                option(isToday || isTomorrow ? "Pick date" : day.formatted(.dateTime.month(.abbreviated).day()),
                       on: picking || (!isToday && !isTomorrow), icon: "calendar") {
                    picking.toggle()
                }
            }
            if picking {
                DatePicker("Date", selection: $day, in: Calendar.current.startOfDay(for: .now)...,
                           displayedComponents: [.date])
                    .datePickerStyle(.graphical)
                    .onChange(of: day) { _, _ in picking = false }
            } else {
                Text(day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private func option(_ title: String, on: Bool, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { HDIcon(icon, size: 15) }
                Text(title).lineLimit(1)
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .foregroundStyle(on ? Theme.bg : Theme.text)
            .background(RoundedRectangle(cornerRadius: 4).fill(on ? Theme.text : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on ? Theme.text : Theme.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
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

    private let lengths = [15, 30, 60, 90, 120]
    private var startOnDay: Date { start.onDay(day) }

    var body: some View {
        NavigationStack {
            Form {
                TextField("What are you doing?", text: $title)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit(add)

                Section("Date") {
                    DayPicker(day: $day).padding(.vertical, 4)
                }

                Section("Time") {
                    DatePicker("Start", selection: $start, displayedComponents: [.hourAndMinute])
                    Picker("Length", selection: $minutes) {
                        ForEach(lengths, id: \.self) { m in
                            Text(m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h\(m % 60)"))
                                .tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Ends at \(startOnDay.addingTimeInterval(TimeInterval(minutes * 60)).shortTime)")
                        .foregroundStyle(.secondary)
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
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
                    Section { DayPicker(day: $day).padding(.vertical, 4) } header: { Text("1 · Date") }
                    Section {
                        DatePicker("Start", selection: $start, displayedComponents: [.hourAndMinute])
                        Stepper(value: $minutes, in: 5...720, step: 5) {
                            Text("Length  \(lengthText)")
                        }
                        Text("Ends at \(startOnDay.addingTimeInterval(TimeInterval(minutes * 60)).shortTime)")
                            .foregroundStyle(.secondary)
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(isPlan && title.trimmingCharacters(in: .whitespaces).isEmpty)
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
