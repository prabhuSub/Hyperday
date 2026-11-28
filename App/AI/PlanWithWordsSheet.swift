import SwiftUI

/// #5: type or dictate (keyboard mic) what you want to do; Apple Intelligence fits it into your free time.
struct PlanWithWordsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var proposals: [PlanProposal] = []
    @State private var working = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("gym after work, call mom at lunch, finish the project doc (90 min)", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($focused)
                        .hdShimmer(working)   // v57: what's being written shimmers
                    Button { Task { await plan() } } label: {
                        HStack(spacing: 4) {
                            Text(working ? "Planning" : "Fit into my day")
                            if working { BlinkCursor() }   // v57: typing cursor while writing
                        }
                    }
                        .hdShimmer(working)
                        .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty || working || !AIPlanner.isAvailable)
                } footer: {
                    Text(AIPlanner.isAvailable
                         ? "Apple Intelligence on your iPhone reads this and picks times around your calendar. Nothing is sent anywhere. Tap the mic on the keyboard to speak."
                         : AIPlanner.unavailableReason)
                }
                if let error {
                    Section { Text(error).foregroundStyle(Theme.red) }
                }
                if !proposals.isEmpty {
                    Section("Fitted into your free time") {
                        ForEach($proposals) { $p in
                            Toggle(isOn: $p.include) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.title)
                                    Text("\(p.start.formatted(.dateTime.weekday(.abbreviated).hour().minute())) · \(p.minutes) min")
                                        .font(.hdMono(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                            .hdBlurIn()   // v57: proposals fade in from blur
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.section)
            .navigationTitle("Plan with words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add all", action: addAll).disabled(!proposals.contains(where: \.include))
                }
            }
            .onAppear { focused = true }
        }
    }

    private func plan() async {
        working = true
        error = nil
        do {
            proposals = try await AIPlanner.plan(text)
            if proposals.isEmpty { error = "Couldn't find any tasks in that. Try listing them with commas." }
        } catch {
            self.error = "Apple Intelligence couldn't plan that: \(error.localizedDescription)"
        }
        working = false
    }

    private func addAll() {
        for p in proposals where p.include {
            BlockStore.shared.add(title: p.title, start: p.start, minutes: p.minutes,
                                  categoryIDs: p.categoryID.map { [$0] } ?? [])
        }
        Task { await LiveActivityManager.shared.refresh() }
        dismiss()
    }
}
