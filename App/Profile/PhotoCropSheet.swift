import SwiftUI
import UIKit

/// v70: crop a photo to the profile circle. Drag to move, pinch to zoom, double-tap to reset.
/// The image always covers the circle, so the result never has empty edges.
struct PhotoCropItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

struct PhotoCropSheet: View {
    let image: UIImage
    let onDone: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var side: CGFloat = 300

    private let maxScale: CGFloat = 6

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let s = max(120, min(geo.size.width, geo.size.height) - 40)
                let base = baseSize(s)
                ZStack {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: base.width * scale, height: base.height * scale)
                        .offset(offset)
                    // Dim everything outside the circle.
                    Rectangle()
                        .fill(Color.black.opacity(0.62))
                        .mask {
                            Rectangle()
                                .overlay(Circle().frame(width: s, height: s).blendMode(.destinationOut))
                                .compositingGroup()
                        }
                        .allowsHitTesting(false)
                    Circle()
                        .strokeBorder(Color.white.opacity(0.85), lineWidth: 1)
                        .frame(width: s, height: s)
                        .allowsHitTesting(false)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(drag.simultaneously(with: magnify))
                .onTapGesture(count: 2) {
                    withAnimation(HDEase.standard(0.35)) {
                        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
                    }
                }
                .onAppear { side = s }
                .onChange(of: s) { _, v in side = v; clamp() }
            }
            .background(Color.black.ignoresSafeArea())
            .overlay(alignment: .bottom) {
                Text("DRAG TO MOVE · PINCH TO ZOOM")
                    .font(.hdMono(size: 10.5, weight: .medium)).kerning(1.4)
                    .foregroundStyle(HDTone.dim)
                    .padding(.bottom, 18)
                    .allowsHitTesting(false)
            }
            .navigationTitle("Crop photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        if let out = render() { onDone(out) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .interactiveDismissDisabled()
    }

    /// The image's size at zoom 1: just big enough to cover the circle.
    private func baseSize(_ s: CGFloat) -> CGSize {
        let w = max(image.size.width, 1), h = max(image.size.height, 1)
        let k = s / min(w, h)
        return CGSize(width: w * k, height: h * k)
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                offset = CGSize(width: lastOffset.width + v.translation.width,
                                height: lastOffset.height + v.translation.height)
                clamp()
            }
            .onEnded { _ in lastOffset = offset }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in
                scale = min(maxScale, max(1, lastScale * v.magnification))
                clamp()
            }
            .onEnded { _ in lastScale = scale; lastOffset = offset }
    }

    /// Keep the circle covered by the image.
    private func clamp() {
        let b = baseSize(side)
        let mx = max(0, (b.width * scale - side) / 2), my = max(0, (b.height * scale - side) / 2)
        offset = CGSize(width: min(mx, max(-mx, offset.width)), height: min(my, max(-my, offset.height)))
    }

    /// The square under the circle, 512 px.
    private func render(px: CGFloat = 512) -> UIImage? {
        let b = baseSize(side)
        let dispW = b.width * scale
        guard dispW > 0 else { return nil }
        let k = image.size.width / dispW                     // image points per screen point
        let x0 = (dispW / 2 - offset.width) - side / 2       // circle's left edge, in displayed-image points
        let y0 = (b.height * scale / 2 - offset.height) - side / 2
        let r = px / (side * k)                               // output pixels per image point
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: px, height: px), format: fmt).image { _ in
            image.draw(in: CGRect(x: -x0 * k * r, y: -y0 * k * r,
                                  width: image.size.width * r, height: image.size.height * r))
        }
    }
}
