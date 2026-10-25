import SwiftUI

/// The same activity list as setup, reachable after the participant is already home.
struct ActivitiesManageView: View {
    @Environment(AppModel.self) private var model
    @State private var drafts: [ActivityDraft] = []
    @State private var editing: ActivityDraft?
    @State private var editingIsNew = false
    @State private var loaded = false
    @State private var busy = false
    @State private var message: String?

    private let minCount = 3, maxCount = 5

    var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your activities").font(.ssTitle).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                Text("Add, change, or remove activities. Keep between \(minCount) and \(maxCount).")
                    .ssBodyText()
            }

            VStack(spacing: 16) {
                ForEach(drafts) { draft in
                    Button { editingIsNew = false; editing = draft } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(draft.name).font(.ssCardTitle).foregroundStyle(Color.ssText)
                            Text(draft.summary).ssSecondaryText()
                        }
                        .softCard()
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(draft.name), \(draft.summary)")
                    .accessibilityHint("Double tap to edit")
                }
                if drafts.count < maxCount {
                    Button { editingIsNew = true; editing = ActivityDraft() } label: {
                        Label("Add an activity", systemImage: "plus")
                    }
                    .buttonStyle(QuietButtonStyle())
                }
            }
            .gentle(value: drafts.count)

            if let message { Text(message).ssBodyText().softCard(tint: .ssTaupeSoft) }

            VStack(spacing: 8) {
                Button(action: { Task { await save() } }) {
                    if busy { ProgressView().tint(Color.ssOnSage) } else { Text("Save") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(drafts.count < minCount || busy)
                if drafts.count < minCount {
                    Text("Keep at least \(minCount) activities.").ssSecondaryText()
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { draft in
            ActivityEditorView(
                draft: draft,
                isNew: editingIsNew,
                onSave: { saved in
                    if let i = drafts.firstIndex(where: { $0.localID == saved.localID }) { drafts[i] = saved } else { drafts.append(saved) }
                },
                onDelete: drafts.count > minCount ? { drafts.removeAll { $0.localID == draft.localID } } : nil
            )
        }
        .onAppear {
            if !loaded { drafts = model.activities.map(ActivityDraft.init); loaded = true }
        }
    }

    private func save() async {
        busy = true; message = nil
        defer { busy = false }
        do {
            try await model.saveActivities(drafts, advanceSetup: false)
            drafts = model.activities.map(ActivityDraft.init)
            message = "Saved."
        } catch {
            message = "That didn't save. Please try again."
        }
    }
}
