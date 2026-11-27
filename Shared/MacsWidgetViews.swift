import SwiftUI

// v64: the Macs widgets (JobTrail on your Home Screen). Views only; the widget configuration and the
// timeline live in Widget/MacsWidgets.swift. Shared with the app for a debug preview.

// MARK: - Sample data (placeholder / previews)

extension JTSnapshot {
    static var sample: JTSnapshot {
        let now = Date.now
        func t(_ m: Double) -> Date { now.addingTimeInterval(-m * 60) }
        let macs = [
            MacLive(id: "local", name: "MacBook Pro", desktop: false, online: true, running: 3, waiting: 2, gpu: 12, mem: 42,
                    top: "S01_run2.sh · S01.ok", topSince: t(48), topWaiting: false),
            MacLive(id: "remote", name: "Mac mini", desktop: true, online: true, running: 1, waiting: 0, gpu: 98, mem: 37,
                    top: "~/ai/ltx-2-mlx/.venv/bin/python render_s01.py", topSince: t(22), topWaiting: false),
        ]
        let live = [
            JTJob(id: "a", label: "render_s01.py", machine: "remote", state: "running", startedAt: t(22)),
            JTJob(id: "b", label: "S01_run2.sh · S01.ok", machine: "local", state: "running", startedAt: t(48)),
            JTJob(id: "c", label: "python3 - 2>/dev/null", machine: "local", state: "running", startedAt: t(95)),
            JTJob(id: "d", label: "watch: ssh mini 'grep -q fini'", machine: "local", state: "waiting", startedAt: t(130)),
        ]
        var recent: [JTJob] = []
        for i in 0..<60 {
            let s = t(Double(i) * 23 + 30)
            recent.append(JTJob(id: "r\(i)", label: "job \(i)", machine: i % 3 == 0 ? "local" : "remote",
                                state: i % 11 == 0 ? "failed" : "done", startedAt: s, endedAt: s.addingTimeInterval(600)))
        }
        let samples = (0..<72).map { k -> JTSample in
            let x = Double(k)
            return JTSample(t: t(Double(72 - k) * 4),
                            gpu: ["local": Int(15 + 12 * sin(x / 5) + (k > 50 ? 20 : 0)), "remote": Int(min(99, 60 + 35 * sin(x / 9) + (k > 40 ? 20 : 0)))],
                            mem: ["local": Int(38 + 6 * sin(x / 7)), "remote": Int(30 + 8 * sin(x / 6))])
        }
        return JTSnapshot(updated: now, reachable: true, macs: macs, live: live, recent: recent, samples: samples)
    }
}

// MARK: - Pieces

/// A data sparkline (0…100) with a soft fill, JobTrail's machine graphs.
struct JTSpark: View {
    var values: [Double]
    var color: Color
    var fill = true
    var body: some View {
        Canvas { c, size in
            guard values.count > 1 else {
                c.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(HDTone.hover))
                return
            }
            let step = size.width / CGFloat(values.count - 1)
            func pt(_ i: Int) -> CGPoint {
                CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(min(max(values[i], 0), 100)) / 100 * (size.height - 2) - 1)
            }
            var line = Path()
            line.move(to: pt(0))
            for i in 1..<values.count { line.addLine(to: pt(i)) }
            if fill {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                c.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.32), color.opacity(0)]),
                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            }
            c.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            let last = pt(values.count - 1)
            c.fill(Path(ellipseIn: CGRect(x: last.x - 2.5, y: last.y - 2.5, width: 5, height: 5)), with: .color(color))
        }
    }
}

private func shortJob(_ s: String) -> String { MacRowItem.short(s) }

private func macStatus(_ m: MacLive) -> HDStatus {
    switch m.statusRaw { case "running": .running; case "waiting": .waiting; case "failed": .failed; default: .idle }
}

private func jobStatus(_ j: JTJob) -> HDStatus {
    switch j.state { case "running": .running; case "waiting": .waiting; case "failed": .failed; case "done": .done; default: .idle }
}

private struct WCap: View {
    let text: String
    var color: Color = HDTone.faintDark
    var body: some View {
        Text(text.uppercased()).font(.mono(9, .semibold)).kerning(0.8).foregroundStyle(color).lineLimit(1)
    }
}

/// GPU (amber, filled) and memory (blue line) on one graph, numbers on top. Shows "collecting" until
/// there are a few readings (the history builds up as the app and the widget read JobTrail).
struct DualGraph: View {
    let gpu: Int?
    let mem: Int?
    let gpuSeries: [Double]
    let memSeries: [Double]
    var height: CGFloat = 26
    var body: some View {
        let hot = (gpu ?? 0) >= 90
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                WCap(text: "GPU")
                Text(gpu.map { "\($0)%" } ?? "–").font(.mono(11, .semibold)).monospacedDigit()
                    .foregroundStyle(hot ? HDTone.danger : HDTone.textHi)
                Spacer(minLength: 2)
                WCap(text: "MEM")
                Text(mem.map { "\($0)%" } ?? "–").font(.mono(11, .semibold)).monospacedDigit()
                    .foregroundStyle(HDTone.blue)
            }
            ZStack {
                if gpuSeries.count < 3 {
                    // not enough history yet: today's values as level lines
                    GeometryReader { g in
                        let y = { (v: Int?) in g.size.height - CGFloat(min(max(v ?? 0, 0), 100)) / 100 * (g.size.height - 2) - 1 }
                        Path { p in p.move(to: CGPoint(x: 0, y: y(gpu))); p.addLine(to: CGPoint(x: g.size.width, y: y(gpu))) }
                            .stroke(hot ? HDTone.danger : HDTone.amber, style: StrokeStyle(lineWidth: 1.2, dash: [3, 3]))
                        Path { p in p.move(to: CGPoint(x: 0, y: y(mem))); p.addLine(to: CGPoint(x: g.size.width, y: y(mem))) }
                            .stroke(HDTone.blue.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    }
                    Text("COLLECTING HISTORY").font(.mono(7.5, .semibold)).kerning(0.6).foregroundStyle(HDTone.faintDark)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                } else {
                    JTSpark(values: gpuSeries, color: hot ? HDTone.danger : HDTone.amber)
                    JTSpark(values: memSeries, color: HDTone.blue, fill: false)
                }
            }
            .frame(height: height)
            .background(alignment: .bottom) { Rectangle().fill(HDTone.hover).frame(height: 1) }
        }
    }
}

/// v75: chip temperature (green / amber ≥ 80° / red ≥ 95°), battery when low, fan speed — small, on one line.
struct MacVitalsInline: View {
    let mac: MacLive
    var body: some View {
        HStack(spacing: 5) {
            if let b = mac.battery, b < 20, mac.charging != true {
                Text("\(b)%").font(.mono(9.5, .bold)).foregroundStyle(HDTone.danger)
            }
            if let t = mac.temp {
                Text("\(t)°").font(.mono(9.5, .semibold)).monospacedDigit()
                    .foregroundStyle(t >= 95 ? HDTone.danger : t >= 80 ? HDTone.amber : HDTone.green)
            }
            if let f = mac.fan, f > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "fan").font(.system(size: 8, weight: .semibold))
                    Text(String(format: "%.1fk", Double(f) / 1000)).font(.mono(9.5, .medium))
                }.foregroundStyle(HDTone.faintDark)
            }
        }
        .lineLimit(1)
    }
}

/// One Mac: header, GPU + MEM graphs, newest job with a live clock.
struct MacPanel: View {
    let mac: MacLive
    let snap: JTSnapshot
    var graphHeight: CGFloat = 24
    var showJob = true
    var body: some View {
        let st = macStatus(mac)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: mac.desktop ? "macmini" : "laptopcomputer")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(HDTone.dim)
                Text(mac.name).font(.geist(size: 12.5, weight: .semibold)).foregroundStyle(HDTone.textHi).lineLimit(1)
                Spacer(minLength: 2)
                if mac.online { MacVitalsInline(mac: mac) }
                JTStatusDot(status: st, size: 5, animated: false)
            }
            if mac.online {
                DualGraph(gpu: mac.gpu, mem: mac.mem,
                          gpuSeries: snap.series(mac.id, gpu: true, hours: 6),
                          memSeries: snap.series(mac.id, gpu: false, hours: 6),
                          height: graphHeight)
                if showJob {
                    HStack(spacing: 5) {
                        if mac.running + mac.waiting > 0 {
                            Text("\(mac.running)").font(.mono(9, .bold)).foregroundStyle(.black)
                                .padding(.horizontal, 4).background(Capsule().fill(mac.running > 0 ? HDTone.green : HDTone.amber))
                        }
                        Text(mac.top.map(shortJob) ?? "idle")
                            .font(.mono(10, .medium)).foregroundStyle(mac.top == nil ? HDTone.faintDark : HDTone.soft)
                            .lineLimit(1).truncationMode(.middle).layoutPriority(-1)
                        Spacer(minLength: 2)
                        if let since = mac.topSince, mac.topWaiting != true {
                            Text(timerInterval: since...since.addingTimeInterval(7 * 86_400), countsDown: false)
                                .font(.mono(10, .semibold)).foregroundStyle(HDTone.green)
                                .monospacedDigit().multilineTextAlignment(.trailing).frame(width: 46, alignment: .trailing)
                        }
                    }
                }
            } else {
                Spacer(minLength: 0)
                Text("OFFLINE").font(.mono(11, .semibold)).kerning(0.8).foregroundStyle(HDTone.danger)
                Spacer(minLength: 0)
            }
        }
    }
}

/// 24 columns: jobs started each hour (blue done, red failed, green still running).
struct HourlyBars: View {
    let snap: JTSnapshot
    var now: Date = .now
    var body: some View {
        let hours = snap.hourly(now: now)
        let top = max(1, hours.map { $0.done + $0.failed + $0.running }.max() ?? 1)
        GeometryReader { g in
            let w = (g.size.width - 23 * 2) / 24
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<24, id: \.self) { i in
                    let h = hours[i]
                    let unit = g.size.height / CGFloat(top)
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Rectangle().fill(HDTone.green).frame(height: CGFloat(h.running) * unit)
                        Rectangle().fill(HDTone.danger).frame(height: CGFloat(h.failed) * unit)
                        Rectangle().fill(HDTone.blue.opacity(0.85)).frame(height: CGFloat(h.done) * unit)
                        if h.done + h.failed + h.running == 0 { Rectangle().fill(HDTone.hover).frame(height: 1) }
                    }
                    .frame(width: w)
                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                }
            }
        }
    }
}

private struct StaleNote: View {
    let snap: JTSnapshot
    let now: Date
    var body: some View {
        if !snap.reachable || now.timeIntervalSince(snap.updated) > 20 * 60 {
            WCap(text: snap.updated == .distantPast ? "no data yet" : "as of \(snap.updated.formatted(date: .omitted, time: .shortened))",
                 color: HDTone.amber)
        }
    }
}

// MARK: - Families

struct MacsSmallView: View {
    let snap: JTSnapshot
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                JTECGMark().frame(width: 14, height: 14)
                Text("MACS").font(.mono(10, .semibold)).kerning(1).foregroundStyle(HDTone.dim)
                Spacer()
                let run = snap.macs.reduce(0) { $0 + $1.running }
                if run > 0 { JTPill(text: "\(run) run", kind: .running) } else { StaleNote(snap: snap, now: now) }
            }
            ForEach(snap.macs.prefix(2), id: \.name) { m in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: m.desktop ? "macmini" : "laptopcomputer")
                            .font(.system(size: 10, weight: .semibold)).foregroundStyle(HDTone.dim)
                        JTStatusDot(status: macStatus(m), size: 5, animated: false)
                        Text(m.desktop ? "MINI" : "MBP").font(.mono(9.5, .semibold)).foregroundStyle(HDTone.soft)
                        Spacer(minLength: 2)
                        if !m.online { Text("OFF").font(.mono(10, .semibold)).foregroundStyle(HDTone.danger) }
                        else if m.running > 0 { Text("\(m.running)▸").font(.mono(10, .bold)).foregroundStyle(HDTone.green) }
                    }
                    DualGraph(gpu: m.gpu, mem: m.mem, gpuSeries: snap.series(m.id, gpu: true, hours: 6),
                              memSeries: snap.series(m.id, gpu: false, hours: 6), height: 16)
                        .opacity(m.online ? 1 : 0.4)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct MacsMediumView: View {
    let snap: JTSnapshot
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(snap.macs.prefix(2).enumerated()), id: \.offset) { i, m in
                    if i > 0 { Rectangle().fill(HDTone.hover).frame(width: 1) }
                    MacPanel(mac: m, snap: snap, graphHeight: 20)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            JTECGMark().frame(width: 14, height: 14)
            Text("JobTrail").font(.geist(size: 13, weight: .semibold)).foregroundStyle(HDTone.textHi)
            Spacer()
            StaleNote(snap: snap, now: now)
            let run = snap.macs.reduce(0) { $0 + $1.running }, wait = snap.macs.reduce(0) { $0 + $1.waiting }
            Text("\(run) RUNNING · \(wait) WAITING").font(.mono(9, .semibold)).kerning(0.6)
                .foregroundStyle(run > 0 ? HDTone.green : HDTone.faintDark)
        }
    }
}

struct MacsLargeView: View {
    let snap: JTSnapshot
    let now: Date
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 6) {
                JTECGMark().frame(width: 15, height: 15)
                Text("JobTrail").font(.geist(size: 14, weight: .semibold)).foregroundStyle(HDTone.textHi)
                Spacer()
                StaleNote(snap: snap, now: now)
                let run = snap.macs.reduce(0) { $0 + $1.running }, wait = snap.macs.reduce(0) { $0 + $1.waiting }
                JTPill(text: "\(run) running · \(wait) waiting", kind: run > 0 ? .running : .plain)
            }
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(snap.macs.prefix(2).enumerated()), id: \.offset) { i, m in
                    if i > 0 { Rectangle().fill(HDTone.hover).frame(width: 1) }
                    MacPanel(mac: m, snap: snap, graphHeight: 22, showJob: false)
                }
            }
            Rectangle().fill(HDTone.hover).frame(height: 1)
            WCap(text: "Running now")
            VStack(spacing: 5) {
                let jobs = Array(snap.live.prefix(4))
                if jobs.isEmpty {
                    Text("NOTHING RUNNING").font(.mono(10, .medium)).foregroundStyle(HDTone.faintDark)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(jobs) { j in
                    let st = jobStatus(j)
                    HStack(spacing: 7) {
                        JTStatusDot(status: st, size: 5, animated: false)
                        Text(j.machine == "remote" ? "MINI" : "MBP")
                            .font(.mono(8.5, .semibold)).foregroundStyle(j.machine == "remote" ? Color(UIColor(hd: 0xE8C48A)) : HDTone.soft)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(j.machine == "remote" ? Color(UIColor(hd: 0x2A2114)) : HDTone.hover))
                        Text(shortJob(j.label)).font(.mono(10.5, .medium)).foregroundStyle(HDTone.textHi)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 4)
                        if st == .running {
                            Text(timerInterval: j.startedAt...j.startedAt.addingTimeInterval(7 * 86_400), countsDown: false)
                                .font(.mono(10.5, .semibold)).foregroundStyle(HDTone.green)
                                .monospacedDigit().multilineTextAlignment(.trailing).frame(width: 56, alignment: .trailing)
                        } else {
                            Text(st == .waiting ? "WAITING" : j.state.uppercased())
                                .font(.mono(9, .semibold)).kerning(0.6).foregroundStyle(st.color)
                        }
                    }
                }
            }
            Rectangle().fill(HDTone.hover).frame(height: 1)
            HStack {
                WCap(text: "Last 24 h · jobs started")
                Spacer()
                HStack(spacing: 8) {
                    legend(HDTone.blue, "done"); legend(HDTone.danger, "failed"); legend(HDTone.green, "running")
                }
            }
            HourlyBars(snap: snap, now: now).frame(maxHeight: .infinity)
            HStack {
                Text("24H AGO"); Spacer(); Text("12H"); Spacer(); Text("NOW")
            }
            .font(.mono(8, .medium)).foregroundStyle(HDTone.faintDark)
        }
    }

    private func legend(_ c: Color, _ t: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(c).frame(width: 5, height: 5)
            Text(t).font(.mono(8.5)).foregroundStyle(HDTone.faintDark)
        }
    }
}

/// Lock Screen (monochrome): both Macs, running jobs, GPU / MEM.
struct MacsLockView: View {
    let snap: JTSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(snap.macs.prefix(2), id: \.name) { m in
                HStack(spacing: 5) {
                    Image(systemName: m.desktop ? "macmini" : "laptopcomputer").font(.system(size: 11, weight: .semibold))
                        .frame(width: 16)
                    if !m.online {
                        Text("offline").font(.mono(11, .semibold))
                    } else {
                        Text("\(m.running) run").font(.mono(11, .bold)).fixedSize()
                        Spacer(minLength: 2)
                        Text("GPU \(m.gpu ?? 0)  MEM \(m.mem ?? 0)" + (m.temp.map { "  \($0)°" } ?? "")).font(.mono(10.5, .medium)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
            }
            if snap.macs.isEmpty { Text("JobTrail · open Hyperday").font(.geist(size: 12, weight: .semibold)) }
        }
    }
}

/// JobTrail's pulse mark, stroked in amber.
struct JTECGMark: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                let sx = g.size.width / 24, sy = g.size.height / 24
                p.move(to: CGPoint(x: 3 * sx, y: 12 * sy)); p.addLine(to: CGPoint(x: 7 * sx, y: 12 * sy))
                p.addLine(to: CGPoint(x: 10 * sx, y: 5 * sy)); p.addLine(to: CGPoint(x: 14 * sx, y: 19 * sy))
                p.addLine(to: CGPoint(x: 17 * sx, y: 12 * sy)); p.addLine(to: CGPoint(x: 21 * sx, y: 12 * sy))
            }
            .stroke(HDTone.amber, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }
    }
}
