import PhotosUI
import SwiftUI
import UIKit

/// v36 Photo tasks: the exact picture kept on a block. Never read (no text recognition), never uploaded.
/// Privacy: files live in Application Support/Attachments (not the Files app, not the App Group the
/// widgets see), with complete file protection (unreadable while the phone is locked), excluded from
/// iCloud device backup and from Hyperday's weekly backup.
@MainActor
final class PhotoStore: ObservableObject {
    static let shared = PhotoStore()

    /// Block id → photo file names, oldest first.
    @Published private(set) var photos: [String: [String]] = [:]

    private let dir: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        var url = base.appendingPathComponent("Attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.complete])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()
    private var indexURL: URL { dir.appendingPathComponent("index.json") }

    private init() { load() }

    func names(for blockID: String) -> [String] { photos[blockID] ?? [] }

    /// Saves the picture as is (only shrunk to 2400 px on the long side so it isn't 20 MB).
    @discardableResult
    func add(_ image: UIImage, to blockID: String) -> String? {
        let img = Self.downscaled(image, maxSide: 2400)
        guard let data = img.jpegData(compressionQuality: 0.85) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: dir.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        } catch { return nil }
        photos[blockID, default: []].append(name)
        save()
        return name
    }

    func image(_ name: String) -> UIImage? {
        UIImage(contentsOfFile: dir.appendingPathComponent(name).path)
    }

    func thumbnail(_ name: String, side: CGFloat = 160) -> UIImage? {
        image(name)?.preparingThumbnail(of: CGSize(width: side, height: side * 4 / 3))
    }

    func fileURL(_ name: String) -> URL { dir.appendingPathComponent(name) }

    func remove(_ name: String, from blockID: String) {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        photos[blockID]?.removeAll { $0 == name }
        if photos[blockID]?.isEmpty == true { photos[blockID] = nil }
        save()
    }

    func removeAll(for blockID: String) {
        for n in names(for: blockID) { try? FileManager.default.removeItem(at: dir.appendingPathComponent(n)) }
        photos[blockID] = nil
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data) else { return }
        photos = map
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(photos) else { return }
        try? data.write(to: indexURL, options: [.atomic, .completeFileProtection])
    }

    static func downscaled(_ img: UIImage, maxSide: CGFloat) -> UIImage {
        let side = max(img.size.width, img.size.height)
        guard side > maxSide else { return img }
        let s = maxSide / side
        let size = CGSize(width: img.size.width * s, height: img.size.height * s)
        let f = UIGraphicsImageRendererFormat.default(); f.scale = 1
        return UIGraphicsImageRenderer(size: size, format: f).image { _ in img.draw(in: CGRect(origin: .zero, size: size)) }
    }
}

/// One thumbnail, 3:4, rounded like Photos.
struct PhotoThumb: View {
    let name: String
    var width: CGFloat = 96
    var radius: CGFloat = 10
    var body: some View {
        Group {
            if let img = PhotoStore.shared.thumbnail(name, side: width * 2) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                Color(UIColor.tertiarySystemFill)
            }
        }
        .frame(width: width, height: width * 4 / 3)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(.black.opacity(0.1), lineWidth: 0.5))
    }
}

/// Full-screen photo: pinch to zoom, double-tap to reset, Share, Delete.
struct PhotoViewer: View {
    let name: String
    var onDelete: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var base: CGFloat = 1
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let img = PhotoStore.shared.image(name) {
                    Image(uiImage: img).resizable().scaledToFit()
                        .scaleEffect(scale)
                        .gesture(MagnifyGesture()
                            .onChanged { scale = max(1, min(5, base * $0.magnification)) }
                            .onEnded { _ in base = scale })
                        .onTapGesture(count: 2) { withAnimation(.snappy) { scale = 1; base = 1 } }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton(title: "Close") { dismiss() } }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    ShareLink(item: PhotoStore.shared.fileURL(name)) { Image(systemName: "square.and.arrow.up") }
                    if onDelete != nil {
                        Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .confirmationDialog("Delete this photo?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete photo", role: .destructive) { onDelete?(); dismiss() }
            }
        }
    }
}

/// Edit sheet: the block's photos, + Add photo (camera or library). Changes save right away.
struct PhotosSection: View {
    let blockID: String
    @ObservedObject private var store = PhotoStore.shared
    @State private var viewing: PhotoName?
    @State private var showCamera = false
    @State private var showLibrary = false

    var body: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.names(for: blockID), id: \.self) { n in
                        PhotoThumb(name: n)
                            .onTapGesture { viewing = PhotoName(name: n) }
                            .contextMenu {
                                ShareLink(item: store.fileURL(n)) { Label("Share", systemImage: "square.and.arrow.up") }
                                Button(role: .destructive) { store.remove(n, from: blockID) } label: { Label("Delete", systemImage: "trash") }
                            }
                    }
                    Menu {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
                        }
                        Button { showLibrary = true } label: { Label("Choose photo", systemImage: "photo.on.rectangle") }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "plus").font(.system(size: 24, weight: .semibold))
                            Text("Add photo").font(.footnote.weight(.semibold))
                        }
                        .frame(width: 96, height: 128)
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])).foregroundStyle(.tertiary))
                    }
                }
                .padding(.vertical, 4)
            }
        } header: { Text("Photos") }
        .fullScreenCover(item: $viewing) { p in
            PhotoViewer(name: p.name) { store.remove(p.name, from: blockID) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { img in
                showCamera = false
                if let img { store.add(img, to: blockID) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showLibrary) {
            LibraryPicker { img in
                showLibrary = false
                if let img { store.add(img, to: blockID) }
            }
            .ignoresSafeArea()
        }
    }
}

struct PhotoName: Identifiable { let name: String; var id: String { name } }

/// Apple's photo library picker (PHPicker): no permission prompt, only the picked photo comes back.
struct LibraryPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(); config.filter = .images; config.selectionLimit = 1
        let c = PHPickerViewController(configuration: config); c.delegate = context.coordinator
        return c
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let p = results.first?.itemProvider, p.canLoadObject(ofClass: UIImage.self) else { done(nil); return }
            p.loadObject(ofClass: UIImage.self) { obj, _ in
                let img = obj as? UIImage
                DispatchQueue.main.async { self.done(img) }
            }
        }
    }
}
