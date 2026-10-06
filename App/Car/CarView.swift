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
            // v34: like the car's screen. Drag spins the car; these jump to a view (tap again any time to get back).
            HStack(spacing: 6) {
                ForEach(CarAngle.allCases) { a in
                    Button(a.title) { pins.go(a) }
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(pins.angle == a ? .black : .white)
                        .padding(.horizontal, 11).frame(height: 28)
                        .background(Capsule().fill(pins.angle == a ? Color.white : Color.white.opacity(0.12)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 12)
        }
        .frame(height: 360)
        .background(Color(red: 0.06, green: 0.07, blue: 0.08))
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

enum CarAngle: String, CaseIterable, Identifiable {
    case threeQuarter, side, front, rear, top
    var id: String { rawValue }
    var title: String {
        switch self { case .threeQuarter: return "3/4"; case .side: return "Side"; case .front: return "Front"; case .rear: return "Rear"; case .top: return "Top" }
    }
}

/// Where each anchor (baked into Car.usdz) lands on screen, updated as you turn the car.
@MainActor
final class CarPins: ObservableObject {
    @Published var points: [String: CGPoint] = [:]
    @Published var angle: CarAngle? = .threeQuarter
    var onGo: ((CarAngle) -> Void)?

    func go(_ a: CarAngle) { angle = a; onGo?(a) }
    func resetCamera() { go(.threeQuarter) }
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

        // v34: the car's own screen look. Dark space, a low-poly grid floor and wireframe mountains,
        // all real 3D, so the world turns with you as you spin the car.
        let bg = UIColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1)
        scene.background.contents = bg   // v32: flat sky, no gradients (the lighting environment stays: it lights the paint)
        scene.lightingEnvironment.contents = Self.environment()     // studio light for the paint
        scene.lightingEnvironment.intensity = 1.3
        scene.fogColor = bg; scene.fogStartDistance = 18; scene.fogEndDistance = 150; scene.fogDensityExponent = 1.4
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 500
        key.light?.castsShadow = true; key.light?.shadowMode = .deferred; key.light?.shadowRadius = 8
        key.light?.shadowColor = UIColor(white: 0, alpha: 0.7); key.light?.shadowSampleCount = 8
        key.light?.automaticallyAdjustsShadowProjection = true
        key.eulerAngles = SCNVector3(-1.25, 0.4, 0); scene.rootNode.addChildNode(key)
        let ground = Self.groundY(car)
        Self.addGrid(to: scene.rootNode, y: ground)
        Self.addMountains(to: scene.rootNode, y: ground)

        // Which way the car faces, from the anchors baked into the model, so the view buttons are exact.
        if let f = car.childNode(withName: "Anchor_Frunk", recursively: true),
           let r = car.childNode(withName: "Anchor_Trunk", recursively: true),
           let d = car.childNode(withName: "Anchor_DriverDoor", recursively: true) {
            let fw = f.worldPosition, rw = r.worldPosition, dw = d.worldPosition
            c.front = Self.flatUnit(SCNVector3(fw.x - rw.x, 0, fw.z - rw.z))
            c.left = Self.flatUnit(SCNVector3(dw.x, 0, dw.z))
        }
        pins.onGo = { [weak c] a in c?.go(a) }

        let camNode = SCNNode(); camNode.camera = SCNCamera(); camNode.camera?.fieldOfView = 34
        scene.rootNode.addChildNode(camNode)
        c.cam = camNode
        c.go(.threeQuarter, animated: false)
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
        var front = SCNVector3(0, 0, 1), left = SCNVector3(1, 0, 0)    // set from the model's anchors
        var yaw: Float = 0, tilt: Float = 0.17, dist: Float = 9.6
        private var spin: Float = 0                     // radians per frame after a flick
        private var startDist: Float = 9.6
        private var link: CADisplayLink?

        init(pins: CarPins) { self.pins = pins }

        /// Camera on a circle around the parked car. yaw = angle around it, tilt = height of the view.
        func apply() {
            let flat = dist * cos(tilt)
            let pos = SCNVector3(flat * sin(yaw), 0.7 + dist * sin(tilt), flat * cos(yaw))
            cam?.position = pos
            // Near the top, "up" on screen = away from the camera, so the view never flips or rolls.
            let up = tilt > 1.1 ? SCNVector3(-sin(yaw), 0, -cos(yaw)) : SCNVector3(0, 1, 0)
            cam?.look(at: SCNVector3(0, 0.7, 0), up: up, localFront: SCNVector3(0, 0, -1))
        }

        func go(_ a: CarAngle, animated: Bool = true) {
            stopSpin()
            let dir: SCNVector3
            switch a {
            case .front: dir = front
            case .rear: dir = SCNVector3(-front.x, 0, -front.z)
            case .side: dir = left
            case .threeQuarter, .top: dir = CarSceneView.flatUnit(SCNVector3(front.x + left.x * 0.9, 0, front.z + left.z * 0.9))
            }
            var target = atan2(dir.x, dir.z)
            while target - yaw > .pi { target -= 2 * .pi }             // turn the short way round
            while target - yaw < -.pi { target += 2 * .pi }
            yaw = target
            tilt = a == .top ? 1.32 : (a == .side ? 0.08 : 0.17)
            dist = a == .top ? 10.5 : 9.6
            guard animated else { apply(); return }
            SCNTransaction.begin(); SCNTransaction.animationDuration = 0.7
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            apply()
            SCNTransaction.commit()
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view); g.setTranslation(.zero, in: g.view)
            switch g.state {
            case .began:
                stopSpin()
                DispatchQueue.main.async { [pins] in pins.angle = nil }
            case .changed:
                yaw -= Float(t.x) * 0.009                 // spin only, like the car's screen
                apply()
            case .ended, .cancelled:
                spin = -Float(g.velocity(in: g.view).x) * 0.009 / 60
                if abs(spin) > 0.002 { startSpin() }
            default: break
            }
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            if g.state == .began { startDist = dist; stopSpin() }
            dist = min(14, max(6.5, startDist / Float(max(g.scale, 0.1))))
            apply()
        }

        @objc func reset() {
            go(.threeQuarter)
            DispatchQueue.main.async { [pins] in pins.angle = .threeQuarter }
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

    static func flatUnit(_ v: SCNVector3) -> SCNVector3 {
        let l = max(0.0001, (v.x * v.x + v.z * v.z).squareRoot())
        return SCNVector3(v.x / l, 0, v.z / l)
    }

    /// Low-poly grid floor: squares cut into triangles, faint lines, fading into the dark.
    static func addGrid(to root: SCNNode, y: Float) {
        let tile = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).image { ctx in
            UIColor(red: 0.085, green: 0.09, blue: 0.1, alpha: 1).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            let line = UIBezierPath(); line.lineWidth = 2
            line.move(to: CGPoint(x: 0, y: 0)); line.addLine(to: CGPoint(x: 256, y: 0))
            line.move(to: CGPoint(x: 0, y: 0)); line.addLine(to: CGPoint(x: 0, y: 256))
            line.move(to: CGPoint(x: 0, y: 256)); line.addLine(to: CGPoint(x: 256, y: 0))     // the triangle cut
            UIColor(white: 0.3, alpha: 1).setStroke(); line.stroke()
        }
        let m = SCNMaterial(); m.lightingModel = .lambert; m.diffuse.contents = tile
        m.diffuse.wrapS = .repeat; m.diffuse.wrapT = .repeat; m.diffuse.contentsTransform = SCNMatrix4MakeScale(80, 80, 1)
        m.diffuse.mipFilter = .linear
        let plane = SCNPlane(width: 320, height: 320); plane.materials = [m]
        let n = SCNNode(geometry: plane); n.eulerAngles.x = -.pi / 2; n.position = SCNVector3(0, y, 0)
        root.addChildNode(n)
    }

    /// A ring of low-poly hills on the horizon, dark faces with light wire edges.
    static func addMountains(to root: SCNNode, y: Float) {
        var verts: [SCNVector3] = []
        var rng = SystemRandomNumberGenerator()
        let seg = 90, radii: [Float] = [48, 66, 88, 115]
        var h = [[Float]](repeating: [Float](repeating: 0, count: seg), count: radii.count)
        for i in 0..<seg {
            let wave = 0.5 + 0.5 * sin(Float(i) / Float(seg) * .pi * 6)
            h[1][i] = 2 + 9 * wave * Float.random(in: 0.6...1.2, using: &rng)
            h[2][i] = 4 + 16 * wave * Float.random(in: 0.5...1.2, using: &rng)
            h[3][i] = 1 + 6 * Float.random(in: 0.3...1.0, using: &rng)
        }
        func p(_ r: Int, _ i: Int) -> SCNVector3 {
            let a = Float(i % seg) / Float(seg) * 2 * .pi
            return SCNVector3(radii[r] * cos(a), y + h[r][i % seg], radii[r] * sin(a))
        }
        for r in 0..<(radii.count - 1) {
            for i in 0..<seg {
                verts += [p(r, i), p(r + 1, i), p(r + 1, i + 1), p(r, i), p(r + 1, i + 1), p(r, i + 1)]
            }
        }
        let src = SCNGeometrySource(vertices: verts)
        let idx = SCNGeometryElement(indices: (0..<Int32(verts.count)).map { $0 }, primitiveType: .triangles)
        let solid = SCNGeometry(sources: [src], elements: [idx])
        let sm = SCNMaterial(); sm.lightingModel = .constant; sm.diffuse.contents = UIColor(red: 0.07, green: 0.075, blue: 0.085, alpha: 1)
        sm.isDoubleSided = true; solid.materials = [sm]
        root.addChildNode(SCNNode(geometry: solid))
        let wire = SCNGeometry(sources: [src], elements: [idx])
        let wm = SCNMaterial(); wm.lightingModel = .constant; wm.diffuse.contents = UIColor(white: 0.42, alpha: 1)
        wm.fillMode = .lines; wm.isDoubleSided = true; wire.materials = [wm]
        let wn = SCNNode(geometry: wire); wn.position.y = 0.02
        root.addChildNode(wn)
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
