import EventKit
import SwiftUI
import UIKit

/// Calendar tab: every calendar on the phone + your Hyperday tasks. Agenda (week) and Month.
struct CalendarTabView: View {
    enum Mode: String, CaseIterable, Hashable { case agenda = "Agenda", week = "Week", month = "Month" }

    @EnvironmentObject private var store: BlockStore
    @EnvironmentObject private var categories: CategoryStore

    @State private var mode: Mode = .agenda
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var showTasks = true
    @State private var showDeclined = false
    @State private var editing: Block?
    @State private var cache = ItemsCache()
    @State private var agendaTop: Date?   // the day at the top of the agenda list
    @State private var scrollTick = 0   // bumped on every date tap so the list scrolls even if the date didn't change

    private let cal = Calendar.current

    var body: some View {
        let range = visibleRange
        let byDay = items(in: range)

        VStack(spacing: 0) {
            if mode == .agenda {
                // Controls stay put; only the day list scrolls. It opens with TODAY at the top,
                // and you scroll up for past days or down for future ones.
                controls(byDay: byDay)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        accessNote
                        ForEach(agendaDays, id: \.self) { day in
                            daySection(day, items: byDay[day] ?? [])
                                .id(day)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 40)
                }
                .scrollPosition(id: $agendaTop, anchor: .top)
                .background(Theme.section)
                .onChange(of: agendaTop) { _, top in
                    // Keep the title and week strip in step with the day you scrolled to.
                    // Only when the week changes, so scrolling doesn't redraw everything constantly.
                    if let top, !cal.isDate(top, equalTo: selected, toGranularity: .weekOfYear) {
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) { selected = top }
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            controls(byDay: byDay)
                            VStack(alignment: .leading, spacing: 10) {
                                accessNote
                                if mode == .week {
                                    WeekGrid(days: weekDays, byDay: byDay,
                                             color: { categories.displayColor(for: $0) },
                                             onTap: { editing = $0 },
                                             onMove: { block, start, end in
                                                 let minutes = Int(end.timeIntervalSince(start) / 60)
                                                 store.update(id: block.id, title: block.title, start: start, minutes: minutes)
                                                 Task { await LiveActivityManager.shared.refresh() }
                                             })
                                        .padding(.vertical, 12)
                                        .padding(.trailing, 8)
                                        .cardBox(padding: 0)
                                } else {
                                    daySection(selected, items: byDay[selected] ?? [])
                                        .id(selected)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                            .padding(.bottom, 40)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .background(Theme.section)
                    .onChange(of: scrollTick) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(selected, anchor: .top) }
                        }
                    }
                }
            }
        }
        // Always open on today (or the day the heatmap asked for).
        .onAppear {
            tapDay(CalendarJump.pending ?? cal.startOfDay(for: .now), fromTodayButton: true, animated: false)
            CalendarJump.pending = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            tapDay(cal.startOfDay(for: .now), fromTodayButton: true)
        }
        .onChange(of: mode) { _, _ in tapDay(selected, fromTodayButton: true) }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in cache.eventsVersion += 1 }
        .sheet(item: $editing) { block in
            BlockEditorSheet(
                block: store.planBlocks.first { $0.id == block.id } ?? block,   // raw plan, not timer-adjusted
                steps: store.steps(for: block.id),
                categoryIDs: store.manualCategoryIDs(for: block.id)
            ) {
                store.delete(id: block.id)
                Task { await LiveActivityManager.shared.refresh() }
            }
            .presentationDetents([.large])
        }
    }

    private func controls(byDay: [Date: [Block]]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            titleRow
            PillNav(options: Mode.allCases, selection: $mode) { $0.rawValue }
            if mode == .month {
                monthGrid(byDay: byDay)
            } else {
                weekStrip(byDay: byDay)
                    .padding(.leading, mode == .week ? WeekGrid.labelWidth : 0)
            }
            filters
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bg)
    }

    @ViewBuilder
    private var accessNote: some View {
        if !CalendarService.shared.hasAccess {
            Text("Calendar access is off. Turn it on in Settings › Hyperday › Calendars.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
    }

    // MARK: Data

    private var weekDays: [Date] {
        let start = cal.dateInterval(of: .weekOfYear, for: selected)?.start ?? selected
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    private var monthDays: [Date?] {
        guard let month = cal.dateInterval(of: .month, for: selected) else { return [] }
        let first = month.start
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for i in 0..<count { cells.append(cal.date(byAdding: .day, value: i, to: first)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    /// Agenda: one list from 6 months back to 6 months ahead of today.
    private var agendaDays: [Date] {
        let today = cal.startOfDay(for: .now)
        return (-180...180).compactMap { cal.date(byAdding: .day, value: $0, to: today) }
    }

    private var visibleRange: DateInterval {
        if mode == .agenda, let first = agendaDays.first, let last = agendaDays.last {
            return DateInterval(start: first, end: cal.date(byAdding: .day, value: 1, to: last) ?? last)
        }
        if mode != .month {
            let start = weekDays.first ?? selected
            return DateInterval(start: start, end: cal.date(byAdding: .day, value: 7, to: start) ?? start)
        }
        return cal.dateInterval(of: .month, for: selected) ?? DateInterval(start: selected, duration: 86400 * 31)
    }

    /// Calendar events + (optionally) planned tasks, grouped by day start.
    private func items(in range: DateInterval) -> [Date: [Block]] {
        let key = "\(range.start.timeIntervalSince1970)|\(range.end.timeIntervalSince1970)|\(showTasks)|\(showDeclined)|"
            + "\(store.planBlocks.hashValue)|\(store.overrides.hashValue)|\(FocusFilterState.current.rawValue)|\(cache.eventsVersion)"
        if key == cache.key { return cache.value }
        let value = loadItems(in: range)
        cache.key = key
        cache.value = value
        return value
    }

    private func loadItems(in range: DateInterval) -> [Date: [Block]] {
        var list = CalendarService.shared.events(from: range.start, to: range.end, includeDeclined: showDeclined)
        if showTasks {
            let tasks = store.planBlocks.filter { $0.start >= range.start && $0.start < range.end }
            list += DayEngine.apply(store.overrides, to: tasks)
        }
        list = list.filter(FocusFilterState.allows)
        return Dictionary(grouping: list.sorted { $0.start < $1.start }) { cal.startOfDay(for: $0.start) }
    }

    // MARK: Header

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(titleText)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.text)
            Spacer()
            HStack(spacing: 4) {
                navButton("back") { shift(-1) }
                Button("Today") { tapDay(cal.startOfDay(for: .now), fromTodayButton: true) }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .buttonStyle(.plain)
                    .padding(.horizontal, 6)
                navButton("next") { shift(1) }
            }
        }
    }

    private var titleText: String {
        switch mode {
        case .agenda:
            return selected.formatted(Date.FormatStyle().month(.wide))
        case .week:
            let days = weekDays
            guard let first = days.first, let last = days.last else { return "" }
            let f = Date.FormatStyle().month(.abbreviated).day()
            return "\(first.formatted(f)) – \(last.formatted(f))"
        case .month:
            return selected.formatted(Date.FormatStyle().month(.wide).year())
        }
    }

    private func navButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HDIcon(symbol, size: 18)
                .foregroundStyle(Theme.muted)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Tap a date: the list below jumps to it. Tap the same date again: back to today.
    private func tapDay(_ day: Date, fromTodayButton: Bool = false, animated: Bool = true) {
        let today = cal.startOfDay(for: .now)
        let target = (!fromTodayButton && cal.isDate(day, inSameDayAs: selected)) ? today : cal.startOfDay(for: day)
        if !animated {
            // Opening the tab: land on the day directly (no scroll animation fighting the tab fade).
            selected = target
            if mode == .agenda { agendaTop = target }
            scrollTick += 1
            return
        }
        withAnimation(.easeOut(duration: 0.2)) { selected = target }
        if mode == .agenda {
            withAnimation(.easeInOut(duration: 0.3)) { agendaTop = target }
        }
        scrollTick += 1
    }

    private func shift(_ direction: Int) {
        let next = mode != .month
            ? cal.date(byAdding: .day, value: 7 * direction, to: selected)
            : cal.date(byAdding: .month, value: direction, to: selected)
        if let next {
            selected = cal.startOfDay(for: next)
            if mode == .agenda { withAnimation(.easeInOut(duration: 0.3)) { agendaTop = selected } }
        }
        scrollTick += 1
    }

    // MARK: Week strip

    private func weekStrip(byDay: [Date: [Block]]) -> some View {
        HStack(spacing: 2) {
            ForEach(weekDays, id: \.self) { day in
                Button { tapDay(day) } label: {
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.muted)
                        dayNumber(day, size: 34)
                        dots(byDay[day] ?? [], faded: false)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: Month grid

    private func monthGrid(byDay: [Date: [Block]]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let ordered = Array(symbols[(cal.firstWeekday - 1)...] + symbols[..<(cal.firstWeekday - 1)])
        let today = cal.startOfDay(for: .now)

        return VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Array(ordered.enumerated()), id: \.offset) { _, s in
                    Text(s)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Button { tapDay(day) } label: {
                            VStack(spacing: 3) {
                                dayNumber(day, size: 28, dimPast: true)
                                dots(byDay[day] ?? [], faded: day < today)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 54)
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func dayNumber(_ day: Date, size: CGFloat, dimPast: Bool = false) -> some View {
        let isToday = cal.isDateInToday(day)
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let past = day < cal.startOfDay(for: .now)
        return Text(day.formatted(.dateTime.day()))
            .font(.system(size: size > 30 ? 16 : 14, weight: isToday ? .bold : .medium))
            .foregroundStyle(isToday ? Theme.bg : (dimPast && past ? Theme.faint : Theme.text))
            .frame(width: size, height: size)
            .background(Circle().fill(isToday ? Theme.text : Color.clear))
            .overlay(Circle().stroke(isSelected && !isToday ? Theme.text : Color.clear, lineWidth: 1.5))
    }

    private func dots(_ items: [Block], faded: Bool) -> some View {
        let colors = Array(items.prefix(3)).map { categories.displayColor(for: $0) }
        return HStack(spacing: 3) {
            ForEach(Array(colors.enumerated()), id: \.offset) { _, c in
                Circle().fill(c).frame(width: 5, height: 5).opacity(faded ? 0.45 : 1)
            }
        }
        .frame(height: 5)
    }

    private var filters: some View {
        FlowLayout(spacing: 8) {
            Chip(title: "All calendars", selected: true)
            Chip(title: "Tasks", color: DayLiveStyle.accent, selected: showTasks) { showTasks.toggle() }
            Chip(title: "Declined", selected: showDeclined) { showDeclined.toggle() }
        }
    }

    private func sectionTitle(_ day: Date) -> String {
        let date = day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        if cal.isDateInToday(day) { return "Today · \(date)" }
        if cal.isDateInYesterday(day) { return "Yesterday · \(date)" }
        if cal.isDateInTomorrow(day) { return "Tomorrow · \(date)" }
        return date
    }

    private func daySection(_ day: Date, items: [Block]) -> some View {
        let now = Date.now
        return VStack(alignment: .leading, spacing: 8) {
            Caps("\(sectionTitle(day)) · \(items.count) item\(items.count == 1 ? "" : "s")")
                .padding(.top, 6)
            VStack(spacing: 0) {
                if items.isEmpty {
                    Text("Nothing scheduled")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.faint)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(Array(items.enumerated()), id: \.element.id) { index, block in
                    if index > 0 { Rectangle().fill(Theme.border).frame(height: 1) }
                    Button { editing = block } label: {
                        BlockRow(block: block, now: now,
                                 color: categories.displayColor(for: block),
                                 steps: store.steps(for: block.id),
                                 icon: categories.category(for: block).iconName)
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardBox(padding: 0)
        }
    }
}

// MARK: - Week grid

/// 7 day columns on an hour grid. Overlapping events split their column side by side.
struct WeekGrid: View {
    static let labelWidth: CGFloat = 30
    let days: [Date]
    let byDay: [Date: [Block]]
    let color: (Block) -> Color
    let onTap: (Block) -> Void
    /// Called after a planned block is dragged (move) or its bottom handle pulled (resize). Calendar events never move.
    var onMove: ((Block, Date, Date) -> Void)? = nil

    private let hourHeight: CGFloat = 44
    private static let snap = 15   // minutes

    private enum DragMode { case move, resize }
    private struct DragState {
        var id: String
        var mode: DragMode
        var translation: CGSize
    }
    @State private var drag: DragState?
    @State private var selectedID: String?

    private func snappedMinutes(_ dy: CGFloat) -> Int {
        Int((Double(dy / hourHeight) * 60 / Double(Self.snap)).rounded()) * Self.snap
    }

    private func dayShift(_ dx: CGFloat, colW: CGFloat, dayIndex: Int) -> Int {
        min(max(Int((dx / colW).rounded()), -dayIndex), days.count - 1 - dayIndex)
    }

    /// Where the block would land for a given drag.
    private func preview(_ b: Block, mode: DragMode, translation: CGSize, colW: CGFloat, dayIndex: Int) -> (Date, Date) {
        let mins = TimeInterval(snappedMinutes(translation.height) * 60)
        switch mode {
        case .move:
            let shifted = Calendar.current.date(byAdding: .day,
                                                value: dayShift(translation.width, colW: colW, dayIndex: dayIndex),
                                                to: b.start) ?? b.start
            let start = shifted.addingTimeInterval(mins)
            return (start, start.addingTimeInterval(b.end.timeIntervalSince(b.start)))
        case .resize:
            return (b.start, max(b.start.addingTimeInterval(TimeInterval(Self.snap * 60)), b.end.addingTimeInterval(mins)))
        }
    }

    private func commit(_ b: Block, mode: DragMode, translation: CGSize, colW: CGFloat, dayIndex: Int) {
        let (s, e) = preview(b, mode: mode, translation: translation, colW: colW, dayIndex: dayIndex)
        drag = nil
        guard s != b.start || e != b.end else { return }   // no change: keep it selected for resizing
        selectedID = nil
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onMove?(b, s, e)
    }

    struct Placed {
        let block: Block
        let col: Int
        let cols: Int
    }

    /// Greedy columns inside each cluster of overlapping events.
    static func layout(_ items: [Block]) -> [Placed] {
        var result: [Placed] = []
        var cluster: [(Block, Int)] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let n = (cluster.map { $0.1 }.max() ?? 0) + 1
            result += cluster.map { Placed(block: $0.0, col: $0.1, cols: n) }
            cluster = []
            columnEnds = []
        }

        for b in items.sorted(by: { $0.start < $1.start }) {
            if !cluster.isEmpty && b.start >= clusterEnd { flush() }
            if let i = columnEnds.firstIndex(where: { $0 <= b.start }) {
                columnEnds[i] = b.end
                cluster.append((b, i))
            } else {
                columnEnds.append(b.end)
                cluster.append((b, columnEnds.count - 1))
            }
            clusterEnd = max(clusterEnd, b.end)
        }
        if !cluster.isEmpty { flush() }
        return result
    }

    var body: some View {
        let cal = Calendar.current
        let all = days.flatMap { byDay[$0] ?? [] }
        let earliest = all.map { cal.component(.hour, from: $0.start) }.min() ?? 7
        let latest = all.map { cal.component(.hour, from: $0.end) + 1 }.max() ?? 22
        let startHour = min(7, earliest)
        let endHour = min(24, max(22, latest))
        let totalHeight = CGFloat(endHour - startHour) * hourHeight
        let now = Date.now

        GeometryReader { geo in
            let colW = max(1, (geo.size.width - Self.labelWidth) / 7)
            ZStack(alignment: .topLeading) {
                ForEach(startHour...endHour, id: \.self) { h in
                    let y = CGFloat(h - startHour) * hourHeight
                    Text(hourLabel(h))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.faint)
                        .frame(width: Self.labelWidth - 6, alignment: .trailing)
                        .offset(y: y - 6)
                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: geo.size.width - Self.labelWidth, height: 1)
                        .offset(x: Self.labelWidth, y: y)
                }
                ForEach(1..<7, id: \.self) { i in
                    Rectangle()
                        .fill(Theme.border.opacity(0.6))
                        .frame(width: 1, height: totalHeight)
                        .offset(x: Self.labelWidth + CGFloat(i) * colW)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { dayIndex, day in
                    ForEach(Self.layout(byDay[day] ?? []), id: \.block.id) { item in
                        eventCell(item, dayIndex: dayIndex, day: day, colW: colW,
                                  startHour: startHour, endHour: endHour, now: now)
                    }
                }
                if let todayIndex = days.firstIndex(where: { cal.isDateInToday($0) }) {
                    let minutes = now.timeIntervalSince(cal.startOfDay(for: now)) / 60
                    if minutes >= Double(startHour * 60) && minutes <= Double(endHour * 60) {
                        let y = CGFloat(minutes / 60 - Double(startHour)) * hourHeight
                        let x = Self.labelWidth + CGFloat(todayIndex) * colW
                        Rectangle().fill(Theme.red).frame(width: colW, height: 2).offset(x: x, y: y)
                        Circle().fill(Theme.red).frame(width: 7, height: 7).offset(x: x - 3.5, y: y - 2.5)
                    }
                }
            }
        }
        .frame(height: totalHeight + 8)
    }

    @ViewBuilder
    private func eventCell(_ item: Placed, dayIndex: Int, day: Date, colW: CGFloat,
                           startHour: Int, endHour: Int, now: Date) -> some View {
        let b = item.block
        let movable = onMove != nil && b.source == .plan
        let width: CGFloat = colW / CGFloat(item.cols)
        let baseX: CGFloat = Self.labelWidth + CGFloat(dayIndex) * colW + CGFloat(item.col) * width
        let frame = cellFrame(start: b.start, end: b.end, day: day, startHour: startHour, endHour: endHour)
        let active = drag?.id == b.id ? drag : nil
        let selected = movable && (selectedID == b.id || active != nil)

        // Where it will land (same as where it is when not dragging).
        let landing: (Date, Date) = active.map { preview(b, mode: $0.mode, translation: $0.translation, colW: colW, dayIndex: dayIndex) } ?? (b.start, b.end)
        let ps = landing.0
        let pe = landing.1
        let shift = active?.mode == .move ? dayShift(active!.translation.width, colW: colW, dayIndex: dayIndex) : 0
        let newDay = Calendar.current.date(byAdding: .day, value: shift, to: day) ?? day
        let pf = active == nil ? frame : cellFrame(start: ps, end: pe, day: newDay, startHour: startHour, endHour: endHour)
        let px = baseX + CGFloat(shift) * colW

        if active != nil {
            // Dashed ghost where it was.
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(Theme.muted, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .frame(width: max(4, width - 3), height: frame.height)
                .offset(x: baseX + 1, y: frame.top + 1)
        }

        // One view for the block, dragging or not, so the gesture isn't cancelled mid-drag.
        cellBody(b, height: pf.height, width: width, past: active == nil && b.end <= now, selected: selected)
            .shadow(color: .black.opacity(active != nil ? 0.25 : 0), radius: 6, y: 3)
            .contentShape(Rectangle())
            .onTapGesture {
                if selectedID != nil { selectedID = nil } else { onTap(b) }
            }
            .gesture(moveGesture(b, colW: colW, dayIndex: dayIndex), including: movable ? .all : .subviews)
            .offset(x: px + 1, y: pf.top + 1)
            .zIndex(active != nil ? 1 : 0)

        if active != nil {
            Text("\(ps.shortTime) – \(pe.shortTime)")
                .font(.system(size: 10, weight: .bold).monospacedDigit())
                .foregroundStyle(Theme.bg)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.text, in: Capsule())
                .fixedSize()
                .offset(x: min(max(Self.labelWidth, px - 20), Self.labelWidth + colW * 5), y: max(0, pf.top - 22))
                .zIndex(2)
        }

        if selected {
            // Resize handle on the bottom edge.
            let f = pf
            if active == nil || active?.mode == .resize {
                Capsule()
                    .fill(Theme.text)
                    .frame(width: 18, height: 5)
                    .padding(8)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { v in drag = DragState(id: b.id, mode: .resize, translation: v.translation) }
                            .onEnded { v in commit(b, mode: .resize, translation: v.translation, colW: colW, dayIndex: dayIndex) }
                    )
                    .offset(x: baseX + width / 2 - 16, y: f.top + f.height - 10)
            }
        }
    }

    private func moveGesture(_ b: Block, colW: CGFloat, dayIndex: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let d) = value else { return }
                if drag == nil { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
                selectedID = b.id
                drag = DragState(id: b.id, mode: .move, translation: d?.translation ?? .zero)
            }
            .onEnded { value in
                guard case .second(true, let d) = value else { drag = nil; return }
                commit(b, mode: .move, translation: d?.translation ?? .zero, colW: colW, dayIndex: dayIndex)
            }
    }

    private func cellFrame(start: Date, end: Date, day: Date, startHour: Int, endHour: Int) -> (top: CGFloat, height: CGFloat) {
        let dayStart = Calendar.current.startOfDay(for: day)
        let startMin: Double = max(Double(startHour * 60), start.timeIntervalSince(dayStart) / 60)
        let endMin: Double = min(Double(endHour * 60), end.timeIntervalSince(dayStart) / 60)
        let top = CGFloat(startMin / 60 - Double(startHour)) * hourHeight
        let height = max(14, CGFloat((endMin - startMin) / 60) * hourHeight - 2)
        return (top, height)
    }

    private func cellBody(_ b: Block, height: CGFloat, width: CGFloat, past: Bool, selected: Bool) -> some View {
        let c: Color = color(b)
        return Text(b.title)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(past ? Theme.faint : Theme.text)
            .lineLimit(max(1, Int(height / 11)))
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .frame(width: max(4, width - 3), height: height, alignment: .topLeading)
            .background(c.opacity(past ? 0.12 : (selected ? 0.4 : 0.22)))
            .overlay(alignment: .leading) {
                Rectangle().fill(c.opacity(past ? 0.5 : 1)).frame(width: 3)
            }
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 3).strokeBorder(c, lineWidth: 1.5) }
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    private func hourLabel(_ h: Int) -> String {
        let hour12 = h % 12 == 0 ? 12 : h % 12
        return "\(hour12)\(h < 12 || h == 24 ? "a" : "p")"
    }
}


/// Remembers the last calendar lookup; scrolling the agenda redraws often, EventKit lookups are slow.
final class ItemsCache {
    var key = ""
    var value: [Date: [Block]] = [:]
    var eventsVersion = 0
}
