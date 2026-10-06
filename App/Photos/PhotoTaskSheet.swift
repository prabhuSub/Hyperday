import SwiftUI
import UIKit

/// v36 Photo task (replaces Scan to blocks): camera first, then title + time. The picture is kept
/// exactly as taken and attached to a normal block. Nothing is read from it.
struct PhotoTaskSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var images: [UIImage] = []
    @State private var title = ""
    @State private var day = Date.now
    @State private var start = PhotoTaskSheet.nextFiveMinutes()
    @State private var minutes = 15
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var replacingFirst = false
    private let hasCamera = UIImagePickerController.isSourceTypeAvailable(.camera)

    private var startOnDay: Date { start.onDay(day) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if images.isEmpty {
                        HStack(spacing: 10) {
                            if hasCamera { Button("Take photo") { replacingFirst = false; showCamera = true } }
                            Spacer()
                            Button("Choose photo") { replacingFirst = false; showLibrary = true }
                        }
                    } else {
                        HStack(alignment: .top, spacing: 14) {
                            Image(uiImage: images[0]).resizable().scaledToFill()
                                .frame(width: 110, height: 146)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 10) {
                                Text(images.count > 1 ? "\(images.count) photos · saved as is, not read." : "Saved as is, not read.")
                                    .font(.subheadline).foregroundStyle(.secondary)
                                Button("Retake") {
                                    replacingFirst = true
                                    if hasCamera { showCamera = true } else { showLibrary = true }
                                }
                                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                                Menu {
                                    if hasCamera { Button { replacingFirst = false; showCamera = true } label: { Label("Take photo", systemImage: "camera") } }
                                    Button { replacingFirst = false; showLibrary = true } label: { Label("Choose photo", systemImage: "photo.on.rectangle") }
                                } label: { Text("+ Another photo") }
                                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } footer: {
                    Text("Kept only in Hyperday on this iPhone, locked while the phone is locked. Not read, not uploaded, not in backups.")
                }
                Section {
                    TextField("Photo task", text: $title)
                }
                Section("When") {
                    DayPicker(day: $day)
                    DatePicker("Start", selection: $start, displayedComponents: [.hourAndMinute])
                    HStack(alignment: .firstTextBaseline) {
                        Text("Length")
                        Spacer()
                        DurationReadout(minutes: minutes)
                    }
                    DurationRuler(minutes: $minutes)
                    EndsRow(end: startOnDay.addingTimeInterval(TimeInterval(minutes * 60)))
                }
            }
            .navigationTitle("Photo task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCloseButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    SheetConfirmButton(title: "Add", disabled: images.isEmpty, action: add)
                }
            }
            .onAppear { if images.isEmpty && hasCamera { showCamera = true } }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { img in
                    showCamera = false
                    if let img { put(img) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showLibrary) {
                LibraryPicker { img in
                    showLibrary = false
                    if let img { put(img) }
                }
                .ignoresSafeArea()
            }
        }
    }

    private func put(_ img: UIImage) {
        if replacingFirst, !images.isEmpty { images[0] = img } else { images.append(img) }
    }

    private func add() {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !images.isEmpty,
              let id = BlockStore.shared.add(title: clean.isEmpty ? "Photo task" : clean, start: startOnDay, minutes: minutes)
        else { return }
        for img in images { PhotoStore.shared.add(img, to: id) }
        Task { await LiveActivityManager.shared.refresh() }
        dismiss()
    }

    private static func nextFiveMinutes() -> Date {
        let t = (Date.now.timeIntervalSinceReferenceDate / 300).rounded(.up) * 300
        return Date(timeIntervalSinceReferenceDate: t)
    }
}
