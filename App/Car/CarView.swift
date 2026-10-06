import SceneKit
import SwiftUI
import UIKit

/// v31 Car tab (v29 mockup): your Quicksilver Model Y in 3D, badges pinned to the car, battery / range / inside.
struct CarView: View {
    @EnvironmentObject private var cars: CarStore
    @StateObject private var pins = CarPins()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                statusLine
                stage
                if let c = cars.car {
                    InfoRow(items: [
                        InfoItem(label: "Battery", value: "\(c.battery)%", color: DayLiveStyle.doneGreen),
                        InfoItem(label: "Range", value: "\(c.rangeMiles) mi", color: Color(hex: "#64D2FF")),
                        InfoItem(label: "Inside", value: c.insideF.map { "\($0)°F" } ?? "—", color: Theme.blue),
                    ])
                }
                plateRow
                if !cars.signedIn { connectCard }
                if let m = cars.message {
                    Text(m).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Text("3D model: “2021 Tesla Model Y” by tonielpro520 on Sketchfab, CC BY 4.0, repainted Quicksilver.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.faint)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 120)
        }
        .refreshable { await cars.start(force: true, wake: true).value }   // pull down = wake + read (2¢)
        .onAppear { cars.start() }
    }

    /// Your plate, drawn on the 3D car. Stays on this iPhone.
    private var plateRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.and.text.magnifyingglass").foregroundStyle(Theme.muted)
            Text("Plate").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
            TextField("Type your plate", text: $cars.plate)
                .textInputAutocapitalization(.characters).autocorrectionDisabled().submitLabel(.done)
                .multilineTextAlignment(.trailing).font(.system(size: 15, weight: .heavy))
        }
        .cardBox(padding: 14)
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            let c = cars.car
            let color: Color = c?.charging == true ? DayLiveStyle.doneGreen : (c?.locked == false ? .red : DayLiveStyle.doneGreen)
            Circle().fill(color).frame(width: 8, height: 8)
            Text(statusText).font(.system(size: 13, weight: .bold)).foregroundStyle(color)
            if let c, !c.isSample {
                Text("· " + c.updatedAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
            if cars.busy { ProgressView().controlSize(.mini) }
        }
    }

    private var statusText: String {
        guard let c = cars.car else { return cars.signedIn ? "Reading your car…" : "Not connected" }
        if c.isSample { return "Sample car" }
        if c.charging { return "Charging" + (c.fullAt.map { " · full by " + $0.formatted(date: .omitted, time: .shortened) } ?? "") }
        return [cars.asleep ? "Asleep" : "Parked", c.place, c.locked == false ? "Unlocked" : (c.locked == true ? "Locked" : nil)]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var stage: some View {
        ZStack(alignment: .topLeading) {
            CarSceneView(pins: pins, plate: cars.plate)
            ForEach(badges, id: \.id) { b in
                if let p = pins.points[b.id] {
                    CarBadge(icon: b.icon, text: b.text, color: b.color)
                        .position(x: p.x, y: max(18, p.y - 26))
                    Circle().fill(b.color).frame(width: 10, height: 10)
                        .shadow(color: b.color, radius: 6)
                        .position(p)
                }
            }
            HStack(spacing: 8) {
                Text("Drag to turn · pinch to zoom · double-tap")
                Button { pins.resetCamera() } label: { Image(systemName: "arrow.counterclockwise") }
            }
            .font(.system(size: 11.5, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(Color.black.opacity(0.45)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 12)
        }
        .frame(height: 330)
        .background(RadialGradient(colors: [Color(hex: "#F4F5F7"), Color(hex: "#D5D9DE")], center: .init(x: 0.5, y: 0.35),
                                   startRadius: 10, endRadius: 320))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private struct Badge { let id: String; let icon: String; let text: String; let color: Color }

    private var badges: [Badge] {
        guard let c = cars.car else { return [] }
        let grey = Color(white: 0.55)
        var out: [Badge] = []
        if let locked = c.locked {
            out.append(Badge(id: "Anchor_DriverDoor", icon: locked ? "lock.fill" : "lock.open.fill",
                             text: locked ? "Locked" : "Unlocked", color: locked ? DayLiveStyle.doneGreen : .red))
        }
        out.append(Badge(id: "Anchor_ChargePort", icon: "bolt.fill",
                         text: c.charging ? "Charging" + (c.chargeKW.map { " \(Int($0)) kW" } ?? "") : "Port closed",
                         color: c.charging ? DayLiveStyle.doneGreen : grey))
        if let s = c.sentry {
            out.append(Badge(id: "Anchor_Roof", icon: "shield.fill", text: s ? "Sentry on" : "Sentry off",
                             color: s ? Color(hex: "#BF5AF2") : grey))
        }
        return out
    }

    private var connectCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Connect your Tesla", icon: "car", color: Color(hex: "#64D2FF"))
            Text("Sign in with Tesla once. Hyperday reads battery, range, lock and location; your login stays in this iPhone's Keychain.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
            Button("Sign in with Tesla") { Task { await cars.connect() } }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!cars.hasClientID)
            if !cars.hasClientID {
                Text("Add the Client ID in Settings › Car first (or run deploy.sh, which reads it from .tesla-keys).")
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
            }
        }
        .cardBox()
    }
}

struct CarBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 18, height: 18).background(Circle().fill(color))
            Text(text).font(.system(size: 11.5, weight: .heavy)).foregroundStyle(.white).fixedSize()
        }
        .padding(.leading, 3).padding(.trailing, 9).padding(.vertical, 3)
        .background(Capsule().fill(Color(red: 0.08, green: 0.09, blue: 0.12).opacity(0.75)))
        .overlay(Capsule().stroke(color.opacity(0.55), lineWidth: 1.5))
    }
}

// MARK: - SceneKit

/// Where each anchor (baked into Car.usdz) lands on screen, updated as you turn the car.
@MainActor
final class CarPins: ObservableObject {
    @Published var points: [String: CGPoint] = [:]
    var onReset: (() -> Void)?

    func resetCamera() { onReset?() }
}

struct CarSceneView: UIViewRepresentable {
    @ObservedObject var pins: CarPins
    var plate: String

    static let anchors = ["Anchor_DriverDoor", "Anchor_ChargePort", "Anchor_Roof"]

    func makeCoordinator() -> Coordinator { Coordinator(pins: pins) }

    func makeUIView(context: Context) -> SCNView {
        let v = SCNView()
        v.backgroundColor = .clear
        v.antialiasingMode = .multisampling4X
        // v32: Tesla-screen feel. The car spins on a turntable under your finger (with momentum),
        // a little tilt up/down, pinch to zoom within limits, double-tap to reset. No free camera.
        v.allowsCameraControl = false
        v.rendersContinuously = true
        v.delegate = context.coordinator
        let c = context.coordinator
        v.addGestureRecognizer(UIPanGestureRecognizer(target: c, action: #selector(Coordinator.pan(_:))))
        v.addGestureRecognizer(UIPinchGestureRecognizer(target: c, action: #selector(Coordinator.pinch(_:))))
        let dbl = UITapGestureRecognizer(target: c, action: #selector(Coordinator.reset)); dbl.numberOfTapsRequired = 2
        v.addGestureRecognizer(dbl)
        pins.onReset = { [weak c] in c?.reset() }

        guard let url = Bundle.main.url(forResource: "Car", withExtension: "usdz"),
              let scene = try? SCNScene(url: url) else { return v }
        let car = SCNNode()
        for child in scene.rootNode.childNodes { car.addChildNode(child) }
        // Blender wrote it Z-up (length along Y); turn it Y-up for SceneKit if the loader didn't.
        let (mn, mx) = car.boundingBox
        if (mx.y - mn.y) > 3 { car.eulerAngles.x = -.pi / 2 }
        let turn = SCNNode()                        // the turntable
        turn.addChildNode(car)
        scene.rootNode.addChildNode(turn)
        c.turn = turn
        context.coordinator.anchors = Self.anchors.compactMap { car.childNode(withName: $0, recursively: true) }

        Self.paintPlate(in: car, text: plate)

        // v33: parked on a Point Reyes cliff road. The 360° scenery is the background and what the paint reflects.
        if let pano = Bundle.main.url(forResource: "PointReyes360", withExtension: "jpg").flatMap({ UIImage(contentsOfFile: $0.path) }) {
            scene.background.contents = pano
            scene.lightingEnvironment.contents = pano
            scene.lightingEnvironment.intensity = 1.25
        } else {
            scene.lightingEnvironment.contents = Self.environment()
            scene.lightingEnvironment.intensity = 1.0
        }
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 450
        key.light?.castsShadow = true; key.light?.shadowMode = .deferred; key.light?.shadowRadius = 6
        key.light?.shadowColor = UIColor(white: 0, alpha: 0.55); key.light?.shadowSampleCount = 8
        key.light?.orthographicScale = 6; key.light?.automaticallyAdjustsShadowProjection = true
        key.eulerAngles = SCNVector3(-1.1, 0.5, 0); scene.rootNode.addChildNode(key)
        // Real ground under the car: the cliff road (your lane, double yellow, white edge) and the grass verge.
        // The 360° only does the far scenery, so the car never slides over a painted road as you orbit.
        Self.addRoad(to: scene.rootNode, y: Self.groundY(car))

        let camNode = SCNNode(); camNode.camera = SCNCamera(); camNode.camera?.fieldOfView = 34
        scene.rootNode.addChildNode(camNode)
        c.cam = camNode
        c.apply()
        v.scene = scene
        v.pointOfView = camNode
        return v
    }

    func updateUIView(_ v: SCNView, context: Context) {
        guard plate != context.coordinator.plate, let root = v.scene?.rootNode else { return }
        context.coordinator.plate = plate
        Self.paintPlate(in: root, text: plate)
    }

    final class Coordinator: NSObject, SCNSceneRendererDelegate {
        let pins: CarPins
        var anchors: [SCNNode] = []
        var plate = ""
        private var last: TimeInterval = 0

        weak var turn: SCNNode?
        weak var cam: SCNNode?
        static let homeYaw: Float = 2.35, homeTilt: Float = 0.16, homeDist: Float = 9.2
        var yaw = homeYaw, tilt = homeTilt, dist = homeDist
        private var spin: Float = 0                     // radians per frame after a flick
        private var startDist: Float = 9.2
        private var link: CADisplayLink?

        init(pins: CarPins) { self.pins = pins }

        /// v33: the car stays parked on the road and the camera orbits it, so the Point Reyes scenery
        /// swings past as you drag (same feel as the turntable: same yaw, opposite side).
        func apply() {
            let a = -yaw, flat = dist * cos(tilt)
            cam?.position = SCNVector3(flat * sin(a), 0.75 + dist * sin(tilt), flat * cos(a))
            cam?.look(at: SCNVector3(0, 0.75, 0))
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view); g.setTranslation(.zero, in: g.view)
            switch g.state {
            case .began: stopSpin()
            case .changed:
                yaw += Float(t.x) * 0.009
                tilt = min(1.45, max(0.03, tilt + Float(t.y) * 0.005))   // up to almost straight down on the roof, never below the road
                apply()
            case .ended, .cancelled:
                spin = Float(g.velocity(in: g.view).x) * 0.009 / 60
                if abs(spin) > 0.002 { startSpin() }
            default: break
            }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            if g.state == .began { startDist = dist; stopSpin() }
            dist = min(13, max(6.2, startDist / Float(max(g.scale, 0.1))))
            apply()
        }

        @objc func reset() {
            stopSpin()
            yaw = Self.homeYaw; tilt = Self.homeTilt; dist = Self.homeDist
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.6
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            apply()
            SCNTransaction.commit()
        }

        private func startSpin() {
            link?.invalidate()
            let l = CADisplayLink(target: self, selector: #selector(step)); l.add(to: .main, forMode: .common); link = l
        }
        private func stopSpin() { link?.invalidate(); link = nil; spin = 0 }
        @objc private func step() {
            yaw += spin; spin *= 0.95                   // glides to a stop, like the Tesla screen
            apply()
            if abs(spin) < 0.0004 { stopSpin() }
        }

        func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
            guard time - last > 1.0 / 20, let cam = renderer.pointOfView else { return }
            last = time
            let camPos = cam.presentation.worldPosition
            var out: [String: CGPoint] = [:]
            for a in anchors {
                let w = a.presentation.worldPosition
                // Hide pins on the far side of the car.
                let toCam = SCNVector3(camPos.x - w.x, camPos.y - w.y, camPos.z - w.z)
                let outward = SCNVector3(w.x, w.y - 0.75, w.z)
                guard toCam.x * outward.x + toCam.y * outward.y + toCam.z * outward.z > 0 else { continue }
                let p = renderer.projectPoint(w)
                guard p.z > 0, p.z < 1 else { continue }
                out[a.name ?? ""] = CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
            }
            DispatchQueue.main.async { [pins] in pins.points = out }
        }
    }

    /// v33: 3D road along Z (the 360°'s "road ahead" is -Z). Ocean side is -X, hills +X.
    /// The car sits in the ocean-side lane; the centre line is 2 m to its right, like the scenery's camera.
    static func addRoad(to root: SCNNode, y: Float) {
        let width: CGFloat = 8.4, length: CGFloat = 600
        func flat(_ w: CGFloat, _ l: CGFloat, _ x: Float, _ m: SCNMaterial, lift: Float = 0) {
            let p = SCNPlane(width: w, height: l); p.materials = [m]
            let n = SCNNode(geometry: p); n.eulerAngles.x = -.pi / 2; n.position = SCNVector3(x, y + lift, 0)
            root.addChildNode(n)
        }
        // asphalt tile: 8.4 m across × 8.4 m along, repeated down the road
        let road = UIGraphicsImageRenderer(size: CGSize(width: 512, height: 512)).image { ctx in
            UIColor(white: 0.11, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 512, height: 512))
            for _ in 0..<2600 {                                   // grain
                UIColor(white: CGFloat.random(in: 0.05...0.2), alpha: 0.5).setFill()
                ctx.fill(CGRect(x: .random(in: 0...512), y: .random(in: 0...512), width: 2, height: 2))
            }
            let px: CGFloat = 512 / 8.4
            UIColor(red: 0.82, green: 0.62, blue: 0.08, alpha: 1).setFill()      // double yellow at the centre
            ctx.fill(CGRect(x: 256 - 0.2 * px, y: 0, width: 0.1 * px, height: 512))
            ctx.fill(CGRect(x: 256 + 0.1 * px, y: 0, width: 0.1 * px, height: 512))
            UIColor(white: 0.85, alpha: 1).setFill()                                // white edge lines
            ctx.fill(CGRect(x: 0.25 * px, y: 0, width: 0.12 * px, height: 512))
            ctx.fill(CGRect(x: 512 - 0.37 * px, y: 0, width: 0.12 * px, height: 512))
        }
        let rm = SCNMaterial(); rm.lightingModel = .physicallyBased
        rm.diffuse.contents = road; rm.roughness.contents = 0.85
        rm.diffuse.wrapT = .repeat; rm.diffuse.contentsTransform = SCNMatrix4MakeScale(1, Float(length / width), 1)
        flat(width, length, 2.0, rm)                                // centre line 2 m to the car's right

        let grass = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { ctx in
            UIColor(red: 0.62, green: 0.47, blue: 0.22, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            for _ in 0..<3000 {
                UIColor(red: .random(in: 0.45...0.8), green: .random(in: 0.35...0.6), blue: .random(in: 0.12...0.3), alpha: 0.6).setFill()
                ctx.fill(CGRect(x: .random(in: 0...256), y: .random(in: 0...256), width: 1.5, height: .random(in: 2...6)))
            }
        }
        let gm = SCNMaterial(); gm.lightingModel = .physicallyBased; gm.diffuse.contents = grass; gm.roughness.contents = 1.0
        gm.diffuse.wrapS = .repeat; gm.diffuse.wrapT = .repeat; gm.diffuse.contentsTransform = SCNMatrix4MakeScale(20, Float(length / 3), 1)
        flat(60, length, 6.2 + 30, gm, lift: -0.02)                 // hills side
        let gravel = SCNMaterial(); gravel.lightingModel = .physicallyBased; gravel.diffuse.contents = UIColor(red: 0.42, green: 0.37, blue: 0.3, alpha: 1)
        gravel.roughness.contents = 1.0
        flat(2.2, length, -2.2 - 1.1, gravel, lift: -0.02)          // a strip of shoulder, then the cliff edge
    }

    /// Lowest point of the car (the tyres) after it's turned upright.
    static func groundY(_ node: SCNNode) -> Float {
        let (mn, mx) = node.boundingBox
        let corners = [mn, mx]
        var lowest = Float.greatestFiniteMagnitude
        for x in [corners[0].x, corners[1].x] { for y in [corners[0].y, corners[1].y] { for z in [corners[0].z, corners[1].z] {
            let w = node.convertPosition(SCNVector3(x, y, z), to: nil)
            lowest = min(lowest, w.y)
        } } }
        return lowest == .greatestFiniteMagnitude ? 0 : lowest
    }

    /// Your plate number, drawn on the phone (never stored in the model or the repo).
    static func paintPlate(in node: SCNNode, text: String) {
        let size = CGSize(width: 600, height: 300)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(white: 0.98, alpha: 1).setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.1, alpha: 1).setStroke()
            let frame = UIBezierPath(roundedRect: CGRect(x: 6, y: 6, width: 588, height: 288), cornerRadius: 22); frame.lineWidth = 8; frame.stroke()
            let state = NSAttributedString(string: "California", attributes: [
                .font: UIFont(name: "Georgia-BoldItalic", size: 52) ?? .italicSystemFont(ofSize: 52),
                .foregroundColor: UIColor(red: 0.8, green: 0.1, blue: 0.16, alpha: 1)])
            state.draw(at: CGPoint(x: (size.width - state.size().width) / 2, y: 22))
            let num = NSAttributedString(string: text.uppercased(), attributes: [
                .font: UIFont.systemFont(ofSize: 132, weight: .heavy).withCondensed(),
                .foregroundColor: UIColor(red: 0.08, green: 0.12, blue: 0.45, alpha: 1)])
            num.draw(at: CGPoint(x: (size.width - num.size().width) / 2, y: 100))
        }
        node.enumerateHierarchy { n, _ in
            for m in n.geometry?.materials ?? [] where (m.name ?? "").hasPrefix("Plate") && !(m.name ?? "").hasPrefix("PlateFrame") {
                m.diffuse.contents = text.isEmpty ? UIColor(white: 0.95, alpha: 1) : img
            }
        }
    }

    /// Vertical gradient used as the reflection environment (bright sky, darker floor), like a showroom.
    static func environment() -> UIImage {
        let size = CGSize(width: 512, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(white: 0.98, alpha: 1).cgColor, UIColor(white: 0.72, alpha: 1).cgColor,
                          UIColor(white: 0.22, alpha: 1).cgColor, UIColor(white: 0.12, alpha: 1).cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.45, 0.55, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
        }
    }
}

private extension UIFont {
    func withCondensed() -> UIFont {
        guard let d = fontDescriptor.withSymbolicTraits(.traitCondensed) else { return self }
        return UIFont(descriptor: d, size: pointSize)
    }
}
