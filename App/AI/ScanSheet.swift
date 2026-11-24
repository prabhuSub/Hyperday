import PhotosUI
import SwiftUI
import UIKit
import Vision

/// #8 Snap-to-blocks: read dates and times from a photo (whiteboard, flyer, ticket, screenshot) on the iPhone.
struct ScanSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pick: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var proposals: [PlanProposal] = []
    @State private var status: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    HStack(spacing: 10) {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("Take photo") { showCamera = true }.buttonStyle(PrimaryButtonStyle())
                        }
                        PhotosPicker(selection: $pick, matching: .images) {
                            Text("Choose photo")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                    .listRowBackground(Color.clear)
                } footer: {
                    Text("Point at a whiteboard, flyer, ticket or screenshot. Hyperday reads the text on your iPhone and turns dates and times into blocks. The photo isn't saved.")
                }
                if let status {
                    Section { Text(status).foregroundStyle(Theme.muted) }
                }
                if !proposals.isEmpty {
                    Section("\(proposals.count) found") {
                        ForEach($proposals) { $p in
                            Toggle(isOn: $p.include) {
                                VStack(alignment: .leading, spacing: 2) {
                                    TextField("Title", text: $p.title)
                                    Text("\(p.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())) · \(p.minutes) min")
                                        .font(.hd(size: 12)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.section)
            .navigationTitle("Scan to blocks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add all", action: addAll).disabled(!proposals.contains(where: \.include))
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { img in
                    showCamera = false
                    if let img { Task { await read(img) } }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pick) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        await read(img)
                    }
                }
            }
        }
    }

    private func read(_ img: UIImage) async {
        image = img
        status = "Reading…"
        let lines = await TextReader.lines(in: img)
        proposals = TextReader.proposals(from: lines)
        status = proposals.isEmpty ? "No dates or times found. Try a closer, straighter photo." : nil
    }

    private func addAll() {
        for p in proposals where p.include {
            BlockStore.shared.add(title: p.title, start: p.start, minutes: p.minutes)
        }
        Task { await LiveActivityManager.shared.refresh() }
        dismiss()
    }
}

enum TextReader {
    /// On-device text recognition (Vision).
    static func lines(in image: UIImage) async -> [String] {
        guard let cg = image.cgImage else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cg, orientation: .init(image.imageOrientation), options: [:])
            try? handler.perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }.value
    }

    /// Lines with a date/time become blocks. Title = the line without the date, or the line above it.
    static func proposals(from lines: [String]) -> [PlanProposal] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return [] }
        var out: [PlanProposal] = []
        for (i, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = detector.firstMatch(in: line, options: [], range: range), let date = match.date else { continue }
            var title = (line as NSString).replacingCharacters(in: match.range, with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " -–·:,|").union(.whitespaces))
            if title.count < 2, i > 0 { title = lines[i - 1] }
            if title.count < 2 { title = "Event" }
            let minutes = match.duration > 0 ? Int(match.duration / 60) : 60
            out.append(PlanProposal(title: title, start: date, minutes: max(5, min(minutes, 720)), categoryID: nil))
        }
        return out
    }
}

private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// The system camera, for one photo.
struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let c = UIImagePickerController()
        c.sourceType = .camera
        c.delegate = context.coordinator
        return c
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}
