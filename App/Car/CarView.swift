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
        .refreshable { await cars.refresh(force: true, wake: true) }   // pull down = wake + read (2¢)
        .task { await cars.refresh() }
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
                Text("Drag to turn · pinch to zoom")
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
    weak var view: SCNView?
    var home: SCNVector3 = SCNVector3(4.3, 1.5, 4.6)

    func resetCamera() {
        guard let v = view, let cam = v.pointOfView else { return }
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.5
        cam.position = home
        cam.look(at: SCNVector3(0, 0.75, 0))
        SCNTransaction.commit()
    }
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
        v.allowsCameraControl = true
        v.defaultCameraController.interactionMode = .orbitTurntable
        v.defaultCameraController.target = SCNVector3(0, 0.75, 0)
        v.delegate = context.coordinator
        pins.view = v

        guard let url = Bundle.main.url(forResource: "Car", withExtension: "usdz"),
              let scene = try? SCNScene(url: url) else { return v }
        let car = SCNNode()
        for child in scene.rootNode.childNodes { car.addChildNode(child) }
        // Blender wrote it Z-up (length along Y); turn it Y-up for SceneKit if the loader didn't.
        let (mn, mx) = car.boundingBox
        if (mx.y - mn.y) > 3 { car.eulerAngles.x = -.pi / 2 }
        scene.rootNode.addChildNode(car)
        context.coordinator.anchors = Self.anchors.compactMap { car.childNode(withName: $0, recursively: true) }

        Self.paintPlate(in: car, text: plate)

        // Showroom light: soft environment for the metallic paint + one key light.
        scene.lightingEnvironment.contents = Self.environment()
        scene.lightingEnvironment.intensity = 1.6
        let key = SCNNode(); key.light = SCNLight(); key.light?.type = .directional; key.light?.intensity = 700
        key.eulerAngles = SCNVector3(-0.9, 0.6, 0); scene.rootNode.addChildNode(key)

        let camNode = SCNNode(); camNode.camera = SCNCamera(); camNode.camera?.fieldOfView = 34
        camNode.position = pins.home; camNode.look(at: SCNVector3(0, 0.75, 0))
        scene.rootNode.addChildNode(camNode)
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

        init(pins: CarPins) { self.pins = pins }

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
