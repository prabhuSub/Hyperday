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
                    .font(.hd(size: 12))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
}

// MARK: - Add block

/// "+" -> title, date, start, length, categories -> Add.
/// v60: rebuilt as a JobTrail screen: a glowing title card, a sliding day switcher, quick lengths,
/// a live preview of the row it will make, and a pinned amber Add button.
struct QuickAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var titleFocused: Bool

    @State private var title = ""
    @State private var day = QuickAddSheet.nextFiveMinutes()   // same day as the default start (23:56 → tomorrow)
    @State private var start = QuickAddSheet.nextFiveMinutes()
    @State private var minutes = 60
    @State private var categoryIDs: [String] = []
    @State private var added = false
    @Namespace private var ns

    private var startOnDay: Date { start.onDay(day) }
    private var endOnDay: Date { startOnDay.addingTimeInterval(TimeInterval(minutes * 60)) }
    private var trimmed: String { title.trimmingCharacters(in: .whitespaces) }
    private var cal: Calendar { .current }

    private enum DayChoice: String, CaseIterable { case today = "Today", tomorrow = "Tomorrow", other = "Other" }
    private var dayChoice: DayChoice { cal.isDateInToday(day) ? .today : cal.isDateInTomorrow(day) ? .tomorrow : .other }
    private let quickLengths = [15, 30, 45, 60, 90, 120]

    private var category: Category {
        if let first = categoryIDs.first, let c = CategoryStore.shared.category(id: first) { return c }
        return CategoryStore.shared.ruleCategory(title: title, calendarName: nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    titleCard.jtStagger(0)
                    JTSectionHead("When", sub: dayLabel).jtStagger(1)
                    whenCard.jtStagger(2)
                    JTSectionHead("Length", sub: lengthText).jtStagger(3)
                    lengthCard.jtStagger(4)
                    JTSectionHead("Categories", sub: categoryIDs.isEmpty ? "auto" : "\(categoryIDs.count) picked").jtStagger(5)
                    JTCard(padding: 14) {
                        MultiCategoryChips(selection: $categoryIDs,
                                           autoName: CategoryStore.shared.ruleCategory(title: title, calendarName: nil).name)
                    }
                    .jtStagger(6)
                    JTSectionHead("Preview").jtStagger(7)
                    preview.jtStagger(8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.bg)
            .overlay { JTGrain().ignoresSafeArea() }
            .safeAreaInset(edge: .bottom) { addBar }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        JTStatusDot(status: trimmed.isEmpty ? .idle : .waiting, size: 6)
                        Text("ADD BLOCK").font(.hdMono(size: 13, weight: .semibold)).kerning(2)
                    }
                }
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton { dismiss() } }
            }
            .onAppear { titleFocused = true }
        }
        .environment(\.colorScheme, .dark)
    }

    // MARK: Pieces

    private var titleCard: some View {
        JTCard(state: titleFocused ? .glow : .normal, padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    HDIcon(category.iconName, size: 16).foregroundStyle(category.color)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.raised))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.navActive, lineWidth: 1))
                        .animation(HDEase.standard(), value: category.id)
                    Text("WHAT ARE YOU DOING?").font(.hdMono(size: 10, weight: .semibold)).kerning(1).foregroundStyle(Theme.faint)
                    Spacer()
                    if !trimmed.isEmpty { JTPill(text: category.name, kind: .busy).transition(.blurReplace) }
                }
                TextField("", text: $title, prompt: Text("Deep work, gym, call mom…").foregroundStyle(Theme.faint), axis: .vertical)
                    .font(.hd(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .tint(HDTone.amber)
                    .lineLimit(1...3)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit(add)
            }
        }
        .animation(HDEase.standard(0.4), value: trimmed.isEmpty)
        .animation(HDEase.standard(0.4), value: titleFocused)
    }

    private var whenCard: some View {
        JTCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                // JobTrail switcher with a sliding selection
                HStack(spacing: 2) {
                    ForEach(DayChoice.allCases, id: \.self) { c in
                        let on = dayChoice == c
                        Button {
                            withAnimation(HDEase.standard(0.4)) { pick(c) }
                        } label: {
                            Text(c.rawValue.uppercased())
                                .font(.hdMono(size: 11, weight: .semibold)).kerning(0.8)
                                .foregroundStyle(on ? Theme.text : Theme.faint)
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                                .background {
                                    if on {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.hover)
                                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(HDTone.amber.opacity(0.3)))
                                            .matchedGeometryEffect(id: "day", in: ns)
                                    }
                                }
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(JTPressStyle())
                    }
                }
                .padding(3)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.navActive))
                .sensoryFeedback(.selection, trigger: dayChoice)

                if dayChoice == .other {
                    DatePicker("Date", selection: $day, in: cal.startOfDay(for: .now)..., displayedComponents: [.date])
                        .font(.hd(size: 15))
                        .tint(HDTone.amber)
                        .transition(.blurReplace.combined(with: .move(edge: .top)))
                }
                Rectangle().fill(Theme.navActive).frame(height: 1)
                HStack {
                    Text("STARTS").font(.hdMono(size: 10, weight: .semibold)).kerning(1).foregroundStyle(Theme.faint)
                    Spacer()
                    DatePicker("Start", selection: $start, displayedComponents: [.hourAndMinute])
                        .labelsHidden().tint(HDTone.amber)
                }
                HStack {
                    Text("ENDS").font(.hdMono(size: 10, weight: .semibold)).kerning(1).foregroundStyle(Theme.faint)
                    Spacer()
                    Text(endOnDay.shortTime)
                        .font(.hdMono(size: 15, weight: .semibold)).foregroundStyle(HDTone.amber)
                        .contentTransition(.numericText())
                        .animation(HDEase.standard(), value: endOnDay)
                }
            }
        }
    }

    private var lengthCard: some View {
        JTCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    DurationReadout(minutes: minutes)
                    Spacer()
                    JTPulseLine(status: trimmed.isEmpty ? .idle : .waiting, boxed: false).frame(width: 54, height: 16)
                }
                DurationRuler(minutes: $minutes)
                // quick lengths (JobTrail range buttons)
                HStack(spacing: 6) {
                    ForEach(quickLengths, id: \.self) { m in
                        let on = minutes == m
                        Button {
                            withAnimation(HDEase.standard(0.35)) { minutes = m }
                        } label: {
                            Text(m < 60 ? "\(m)m" : (m % 60 == 0 ? "\(m / 60)h" : "\(m / 60).\(m % 60 * 10 / 60)h"))
                                .font(.hdMono(size: 11, weight: .semibold))
                                .foregroundStyle(on ? Color.black : Theme.muted)
                                .frame(maxWidth: .infinity).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? HDTone.amber : Theme.raised))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(on ? Color.clear : Theme.navActive))
                        }
                        .buttonStyle(JTPressStyle())
                    }
                }
                .sensoryFeedback(.selection, trigger: minutes)
            }
        }
    }

    /// How the new block will look in Today, with where it lands in the day.
    private var preview: some View {
        let shown = trimmed.isEmpty ? "Your block" : trimmed
        let previewBlock = Block(id: "preview", title: shown, start: startOnDay, end: endOnDay, source: .plan)
        return JTCard(state: trimmed.isEmpty ? .normal : .glow) {
            VStack(spacing: 0) {
                BlockRow(block: previewBlock, now: .now, color: category.color,
                         icon: category.iconName, pill: startOnDay > .now ? .upcoming(startOnDay) : .live(endOnDay))
                    .opacity(trimmed.isEmpty ? 0.5 : 1)
                    .id(shown.isEmpty)
                    .hdBlurIn(!trimmed.isEmpty)
                Rectangle().fill(Theme.navActive).frame(height: 1)
                dayBar.padding(14)
            }
        }
        .animation(HDEase.standard(0.4), value: startOnDay)
        .animation(HDEase.standard(0.4), value: minutes)
    }

    /// The day 6 AM–midnight with the new block placed on it and an amber "now" tick.
    private var dayBar: some View {
        let dayStart = cal.startOfDay(for: startOnDay).addingTimeInterval(6 * 3600)
        let span: TimeInterval = 18 * 3600
        let f: (Date) -> CGFloat = { CGFloat(min(max($0.timeIntervalSince(dayStart) / span, 0), 1)) }
        return VStack(spacing: 6) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(HDTone.hover).frame(height: 10)
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(category.color)
                        .frame(width: max(6, w * (f(endOnDay) - f(startOnDay))), height: 10)
                        .hdShimmer(!trimmed.isEmpty, color: .white)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .shadow(color: category.color.opacity(0.6), radius: 6)
                        .offset(x: w * f(startOnDay))
                    if cal.isDate(startOnDay, inSameDayAs: .now) {
                        ZStack {
                            RippleRings(color: HDTone.amber, size: 6)
                            PulseDot(color: HDTone.amber, size: 6)
                        }
                        .frame(width: 6, height: 6)
                        .offset(x: w * f(.now) - 3)
                    }
                }
                .frame(height: 14)
            }
            .frame(height: 14)
            HStack {
                Text("6 AM"); Spacer(); Text("NOON"); Spacer(); Text("6 PM"); Spacer(); Text("12 AM")
            }
            .font(.hdMono(size: 9, weight: .medium)).foregroundStyle(Theme.faint)
        }
    }

    private var addBar: some View {
        Button(action: add) {
            HStack(spacing: 8) {
                if added {
                    Image(systemName: "checkmark").font(.geist(size: 15, weight: .bold)).transition(.scale.combined(with: .opacity))
                    Text("Added")
                } else {
                    PlusMark(weight: 2.4).fill(Color.black).frame(width: 13, height: 13)
                    Text(trimmed.isEmpty ? "Add block" : "Add · \(startOnDay.shortTime)")
                        .contentTransition(.numericText())
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(trimmed.isEmpty)
        .opacity(trimmed.isEmpty ? 0.45 : 1)
        .hdGlow(radius: 9, active: false, hot: !trimmed.isEmpty)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(LinearGradient(colors: [Theme.bg.opacity(0), Theme.bg], startPoint: .top, endPoint: .center))
        .animation(HDEase.standard(0.35), value: trimmed.isEmpty)
        .sensoryFeedback(.success, trigger: added)
    }

    private var dayLabel: String {
        startOnDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var lengthText: String {
        let h = minutes / 60, m = minutes % 60
        return h == 0 ? "\(m)m" : (m == 0 ? "\(h)h" : "\(h)h \(m)m")
    }

    private func pick(_ c: DayChoice) {
        switch c {
        case .today: day = .now
        case .tomorrow: day = cal.date(byAdding: .day, value: 1, to: .now) ?? .now
        case .other:
            if cal.isDateInToday(day) || cal.isDateInTomorrow(day) { day = cal.date(byAdding: .day, value: 2, to: .now) ?? .now }
        }
    }

    private func add() {
        guard !trimmed.isEmpty, !added else { return }
        BlockStore.shared.add(title: title, start: startOnDay, minutes: minutes, categoryIDs: categoryIDs)
        Task { await LiveActivityManager.shared.refresh() }
        withAnimation(HDEase.standard(0.3)) { added = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { dismiss() }   // let the ✓ land
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
                        Text(block.title).font(.hd(size: 17, weight: .semibold))
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
