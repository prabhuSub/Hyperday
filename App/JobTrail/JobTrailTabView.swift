import SwiftUI
import WebKit

/// v61: the JobTrail tab. Your Mac's real JobTrail page, unchanged, inside Hyperday.
/// Only inside Hyperday, JobTrail's own phone bar (Map · Jobs · Running · Macs · Refresh) is hidden and the
/// same actions sit in a native JobTrail switcher on top, so it doesn't fight Hyperday's tab bar.
/// The web app itself (Mac, browser, Home Screen) is not touched.
struct JobTrailTabView: View {
    @ObservedObject private var live = JobTrailLive.shared
    @StateObject private var web = JobTrailWeb()
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
                if let url = live.pageURL {
                    JobTrailWebView(url: url, web: web)
                        .opacity(web.loaded ? 1 : 0)
                        .animation(HDEase.entry(0.6), value: web.loaded)
                }
                if live.pageURL == nil || !web.loaded {
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
final class JobTrailWeb: ObservableObject {
    @Published var loaded = false
    weak var view: WKWebView?
    func run(_ js: String) { view?.evaluateJavaScript(js, completionHandler: nil) }
}

struct JobTrailWebView: UIViewRepresentable {
    let url: URL
    let web: JobTrailWeb

    /// Only inside Hyperday: hide JobTrail's own bottom bar (Hyperday has its switcher there) and leave room
    /// above Hyperday's tab bar. The page and the server are unchanged.
    private static let css = """
    .bnav{display:none!important}
    main{padding-bottom:calc(110px + env(safe-area-inset-bottom))!important}
    .fcard.sheet{bottom:calc(84px + env(safe-area-inset-bottom))!important}
    .topbar{padding-top:10px!important}
    """

    func makeCoordinator() -> Coord { Coord(web: web) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        let js = "var s=document.createElement('style');s.textContent=`\(Self.css)`;document.documentElement.appendChild(s);"
        cfg.userContentController.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let w = WKWebView(frame: .zero, configuration: cfg)
        w.isOpaque = false
        w.backgroundColor = .black
        w.scrollView.backgroundColor = .black
        w.scrollView.contentInsetAdjustmentBehavior = .never
        w.allowsBackForwardNavigationGestures = false
        w.navigationDelegate = context.coordinator
        let rc = UIRefreshControl()
        rc.tintColor = UIColor(hd: 0xE9A23B)
        rc.addAction(UIAction { _ in
            w.evaluateJavaScript("hardReload()") { _, err in if err != nil { w.reload() } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { rc.endRefreshing() }
        }, for: .valueChanged)
        w.scrollView.refreshControl = rc
        w.load(URLRequest(url: url))
        context.coordinator.url = url
        web.view = w
        return w
    }

    func updateUIView(_ w: WKWebView, context: Context) {
        if context.coordinator.url != url {   // host changed (Tailscale address), reload
            context.coordinator.url = url
            w.load(URLRequest(url: url))
        }
    }

    final class Coord: NSObject, WKNavigationDelegate {
        let web: JobTrailWeb
        var url: URL?
        init(web: JobTrailWeb) { self.web = web }
        func webView(_ w: WKWebView, didFinish n: WKNavigation!) { Task { @MainActor in web.loaded = true } }
        func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
            Task { @MainActor in
                web.loaded = false
                await JobTrailLive.shared.poll()
            }
        }
        func webViewWebContentProcessDidTerminate(_ w: WKWebView) { w.reload() }
        /// Links that leave JobTrail open in Safari.
        func webView(_ w: WKWebView, decidePolicyFor a: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if a.navigationType == .linkActivated, let u = a.request.url, u.host != url?.host {
                UIApplication.shared.open(u); decisionHandler(.cancel); return
            }
            decisionHandler(.allow)
        }
    }
}
