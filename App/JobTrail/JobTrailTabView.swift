import SwiftUI
import WebKit

/// v61: the JobTrail tab. Your Mac's real JobTrail page, unchanged, inside Hyperday.
/// Only inside Hyperday, JobTrail's own phone bar (Map · Jobs · Running · Macs · Refresh) is hidden and the
/// same actions sit in a native JobTrail switcher on top, so it doesn't fight Hyperday's tab bar.
/// The web app itself (Mac, browser, Home Screen) is not touched.
struct JobTrailTabView: View {
    @ObservedObject private var live = JobTrailLive.shared
    @ObservedObject private var web = JobTrailWeb.shared
    @State private var section: Section = .map
    @Namespace private var ns

    enum Section: String, CaseIterable {
        case map = "Map", jobs = "Jobs", running = "Running", macs = "Macs"
        var js: String {
            switch self {
            case .map: return "navMap()"
            case .jobs: return "navJobs()"
            case .running: return "navRunning()"
            case .macs: return "navMachines()"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                Color.black
                // v73: once the page is up it stays up through a failed read or a network switch.
                if let url = live.pageURL ?? web.url {
                    JobTrailWebView(url: url)
                        .opacity(web.loaded ? 1 : 0)
                        .animation(HDEase.entry(0.6), value: web.loaded)
                }
                if !web.loaded {
                    connecting
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
        .toolbar(.hidden, for: .tabBar)
        .environment(\.colorScheme, .dark)
        .task {
            JobTrailLive.shared.start()
            await JobTrailLive.shared.poll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .jtScrollTop)) { note in
            guard (note.object as? String) == AppTab.jobtrail.rawValue else { return }
            web.run("window.scrollTo({top:0,behavior:'smooth'})")
        }
    }

    // MARK: Header: JobTrail mark, live badge, section switcher

    private var header: some View {
        // JobTrail's own title bar (with the live badge and Mac filter) stays as it is in the page.
        VStack(spacing: 10) {
            // JobTrail's own phone sections, as a native switcher.
            HStack(spacing: 2) {
                ForEach(Section.allCases, id: \.self) { s in
                    let on = section == s
                    Button {
                        withAnimation(HDEase.standard(0.4)) { section = s }
                        web.run(s.js)
                    } label: {
                        HStack(spacing: 5) {
                            if s == .running && live.runningTotal > 0 {
                                Text("\(live.runningTotal)")
                                    .font(.mono(9.5, .bold)).foregroundStyle(.black)
                                    .padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15)
                                    .background(Capsule().fill(HDTone.green))
                                    .contentTransition(.numericText())
                            }
                            Text(s.rawValue.uppercased()).font(.mono(10.5, .semibold)).kerning(0.6)
                        }
                        .foregroundStyle(on ? HDTone.textHi : HDTone.dim)
                        .frame(maxWidth: .infinity).padding(.vertical, 7)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(HDTone.hover)
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(HDTone.amber.opacity(0.3)))
                                    .matchedGeometryEffect(id: "jt-sec", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(JTPressStyle())
                }
            }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(HDTone.surface))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(HDTone.hover))
            .sensoryFeedback(.selection, trigger: section)
            .opacity(live.reachable ? 1 : 0.5)
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .background(Color.black)
        .overlay(alignment: .bottom) { Rectangle().fill(HDTone.hover).frame(height: 1) }
    }

    private var subtitle: String {
        guard live.reachable else { return JobTrailConfig.isConfigured ? "connecting over Tailscale…" : "not set up" }
        let names = live.macs.map { "\($0.name) \($0.online ? "●" : "○")" }.joined(separator: "  ")
        return names.isEmpty ? "your Macs, live" : names
    }

    // MARK: Connecting / offline

    @ViewBuilder
    private var connecting: some View {
        VStack(spacing: 16) {
            if !JobTrailConfig.isConfigured {
                JTEmpty(title: "JobTrail isn't set up here",
                        text: "Run ./deploy.sh on the MacBook with JobTrail and Tailscale running. It picks up the key and address.")
            } else if live.pageURL == nil && live.lastUpdate == nil && !live.reachable {
                JTPulseLine(status: .waiting).frame(width: 140, height: 40)
                Text("CONNECTING TO YOUR MAC").font(.mono(11, .semibold)).kerning(1).foregroundStyle(HDTone.dim)
                Text("Over Tailscale. Is the MacBook awake and Tailscale on here and there?")
                    .font(.geist(size: 13)).foregroundStyle(HDTone.faintDark).multilineTextAlignment(.center)
                Button("Try again") { Task { await JobTrailLive.shared.poll() } }
                    .buttonStyle(SecondaryButtonStyle(width: 160))
            } else {
                JTPulseLine(status: .running).frame(width: 140, height: 40)
                Text("LOADING JOBTRAIL").font(.mono(11, .semibold)).kerning(1).foregroundStyle(HDTone.dim)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .transition(.opacity)
    }
}

/// JobTrail's "Running" glyph: a heartbeat line (M3 12h4l3-7 4 14 3-7h4).
struct JTECGShape: Shape {
    func path(in r: CGRect) -> Path {
        let sx = r.width / 24, sy = r.height / 24
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * sx, y: r.minY + y * sy) }
        var path = Path()
        path.move(to: p(3, 12)); path.addLine(to: p(7, 12)); path.addLine(to: p(10, 5))
        path.addLine(to: p(14, 19)); path.addLine(to: p(17, 12)); path.addLine(to: p(21, 12))
        return path
    }
}

// MARK: - Web view

@MainActor
final class JobTrailWeb: NSObject, ObservableObject, WKNavigationDelegate {
    /// v72: one web view for the whole app, started as soon as JobTrail answers (at launch), not when the tab is
    /// first opened, so switching to the tab shows the page right away instead of loading it from scratch.
    static let shared = JobTrailWeb()

    /// True once the page has painted at least once. A later failed reload keeps the old page on screen (WebKit
    /// leaves it there), so the loading screen only ever shows before the first paint.
    @Published var loaded = false
    private(set) var view: WKWebView?
    private(set) var url: URL?
    private var loadStarted: Date?
    private var retryTask: Task<Void, Never>?
    private var attempts = 0

    /// v73: no reload when Hyperday comes back from the background any more. The page itself reconnects its live
    /// stream when it becomes visible (and reloads only if nothing arrives), which keeps what's on screen instead of
    /// blanking it for seconds, and a reload that fails while the phone's network wakes up is retried (see below).
    private override init() { super.init() }

    /// A page request that takes longer than this is given up and retried (WebKit's default waits 60 s, which on a
    /// Wi-Fi ↔ 5G switch left the loading screen up for a minute or for good).
    private static let loadTimeout: TimeInterval = 12

    /// Only inside Hyperday: hide JobTrail's own bottom bar (Hyperday has its switcher there) and leave room
    /// above Hyperday's tab bar. v69: on phone widths JobTrail draws its legend at the top of the map, where the
    /// chat cards cover it; here it moves to the free strip at the map's bottom. The page and the server are unchanged.
    private static let css = """
    .bnav{display:none!important}
    main{padding-bottom:calc(110px + env(safe-area-inset-bottom))!important}
    .fcard.sheet{bottom:calc(84px + env(safe-area-inset-bottom))!important}
    .topbar{padding-top:10px!important}
    @media (max-width:719px){
      .map .legend{position:absolute!important;top:auto!important;bottom:4px!important;left:8px!important;right:8px!important;
        padding:0!important;height:16px!important;flex-wrap:nowrap!important;justify-content:center!important;gap:9px!important;
        font-size:9.5px!important;z-index:3}
      .map .legend .hint{display:none!important}
    }
    """

    /// The shared web view, created and loading `url` on first call; a new address (Tailscale host) reloads it.
    @discardableResult
    func prepare(_ url: URL) -> WKWebView {
        if let w = view {
            if self.url != url { self.url = url; load() }
            return w
        }
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let js = "var s=document.createElement('style');s.textContent=`\(Self.css)`;document.documentElement.appendChild(s);"
        cfg.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let w = WKWebView(frame: CGRect(x: 0, y: 0, width: 440, height: 900), configuration: cfg)
        w.isOpaque = false
        w.backgroundColor = .black
        w.scrollView.backgroundColor = .black
        w.scrollView.contentInsetAdjustmentBehavior = .never
        w.allowsBackForwardNavigationGestures = false
        w.navigationDelegate = self
        let rc = UIRefreshControl()
        rc.tintColor = UIColor(hd: 0xE9A23B)
        rc.addAction(UIAction { [weak w] _ in
            w?.evaluateJavaScript("hardReload()") { _, err in if err != nil { w?.reload() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { rc.endRefreshing() }
        }, for: .valueChanged)
        w.scrollView.refreshControl = rc
        self.url = url
        view = w
        load()
        return w
    }

    func run(_ js: String) { view?.evaluateJavaScript(js, completionHandler: nil) }
    func refresh() {
        guard let w = view else { return }
        w.evaluateJavaScript("hardReload()") { [weak self] _, err in if err != nil { self?.load() } }
    }

    /// (Re)load the page now, with a short timeout.
    private func load() {
        guard let w = view, let url else { return }
        retryTask?.cancel(); retryTask = nil
        loadStarted = Date()
        w.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: Self.loadTimeout))
    }

    /// After a failed load: try again in 1, 2, 4, 8, then every 10 s, until a load succeeds.
    private func retrySoon() {
        guard retryTask == nil else { return }
        let delay = min(10.0, pow(2.0, Double(attempts)))
        attempts += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            self.load()
        }
    }

    /// Called whenever JobTrail answered a poll (so the network works): reload a page that never painted and isn't
    /// loading, or one stuck loading past the timeout.
    func networkOK() {
        guard let w = view else { return }
        if w.isLoading, let t = loadStarted, Date().timeIntervalSince(t) > Self.loadTimeout + 3 {
            w.stopLoading(); load()
        } else if !loaded && !w.isLoading && retryTask == nil {
            load()
        }
    }

    // MARK: WKNavigationDelegate

    func webView(_ w: WKWebView, didStartProvisionalNavigation n: WKNavigation!) { loadStarted = Date() }
    /// Show the page as soon as it has painted (commit), not after every font and script finished loading.
    func webView(_ w: WKWebView, didCommit n: WKNavigation!) { loaded = true; attempts = 0 }
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { loaded = true; loadStarted = nil }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        loadStarted = nil
        if (e as NSError).code == NSURLErrorCancelled { return }   // replaced by a newer load
        retrySoon()
    }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) {
        loadStarted = nil
        if (e as NSError).code == NSURLErrorCancelled { return }
        if !loaded { retrySoon() }
    }
    func webViewWebContentProcessDidTerminate(_ w: WKWebView) { load() }
    /// Links that leave JobTrail open in Safari.
    func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        if a.navigationType == .linkActivated, let u = a.request.url, u.host != url?.host {
            UIApplication.shared.open(u); decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
}

struct JobTrailWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView { JobTrailWeb.shared.prepare(url) }
    func updateUIView(_ w: WKWebView, context: Context) { JobTrailWeb.shared.prepare(url) }
}
