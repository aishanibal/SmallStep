import SwiftUI

struct ActivitiesSetupView: View {
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
            StepProgress(step: 1, of: 2)

            VStack(alignment: .leading, spacing: 12) {
                Text("Your activities").font(.ssTitle).foregroundStyle(Color.ssText).accessibilityAddTraits(.isHeader)
                Text("Add \(minCount) to \(maxCount) wellness activities.")
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
                    if busy { ProgressView().tint(Color.ssOnSage) } else { Text("Continue") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(drafts.count < minCount || busy)
                if drafts.count < minCount {
                    Text("Add \(minCount - drafts.count) more to continue.").ssSecondaryText()
                }
            }
        }
        .sheet(item: $editing) { draft in
            ActivityEditorView(draft: draft, isNew: editingIsNew) { saved in
                if let i = drafts.firstIndex(where: { $0.localID == saved.localID }) { drafts[i] = saved } else { drafts.append(saved) }
            } onDelete: {
                drafts.removeAll { $0.localID == draft.localID }
            }
        }
        .onAppear {
            model.markSetupStarted()
            if !loaded { drafts = model.activities.map(ActivityDraft.init); loaded = true }
        }
    }

    private func save() async {
        busy = true; message = nil
        defer { busy = false }
        do { try await model.saveActivities(drafts) }
        catch { message = "That didn't save. Please try again." }
    }
}

struct ActivityEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: ActivityDraft
    let isNew: Bool
    let onSave: (ActivityDraft) -> Void
    var onDelete: (() -> Void)?

    @State private var choice: String?
    @State private var custom = ""

    init(draft: ActivityDraft, isNew: Bool, onSave: @escaping (ActivityDraft) -> Void, onDelete: (() -> Void)? = nil) {
        _draft = State(initialValue: draft)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        let known = ActivityDraft.categories.contains(draft.category)
        _choice = State(initialValue: known ? draft.category : (isNew ? "movement" : "other"))
        _custom = State(initialValue: known ? "" : draft.category)
    }

    var body: some View {
        NavigationStack {
            ScreenScroll {
                section("Name") {
                    TextField("e.g. Evening walk", text: $draft.name).font(.ssBody).frame(minHeight: 44)
                    Divider().overlay(Color.ssHairline)
                }

                section("Kind of activity") {
                    ChipGroup(options: (ActivityDraft.categories + ["other"]).map { ($0, $0.capitalized) }, selection: $choice)
                    if choice == "other" {
                        TextField("What would you call it?", text: $custom).font(.ssBody).frame(minHeight: 44)
                        Divider().overlay(Color.ssHairline)
                    }
                }

                section("How long it usually takes") {
                    Stepper(value: $draft.durationMin, in: 5...240, step: 5) {
                        Text("About \(draft.durationMin) minutes").ssBodyText()
                    }
                }

                section("Where") {
                    Picker("Where", selection: $draft.location) {
                        ForEach(ActivityLocation.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                section("Priority") {
                    Picker("Priority", selection: $draft.priority) {
                        Text("1").tag(1); Text("2").tag(2); Text("3").tag(3)
                    }
                    .pickerStyle(.segmented)
                    Text("3 matters most.").ssSecondaryText()
                }

                section("How often per week") {
                    Picker("How often", selection: $draft.weeklyIntention) {
                        Text("Whenever").tag(Int?.none)
                        ForEach(1...7, id: \.self) { n in Text("About \(n) \(n == 1 ? "time" : "times") a week").tag(Int?.some(n)) }
                    }
                    .pickerStyle(.menu).tint(Color.ssBlue)
                }

                VStack(spacing: 8) {
                    Button("Save") { commit() }.buttonStyle(PrimaryButtonStyle()).disabled(!canSave)
                    if !isNew, let onDelete {
                        Button("Remove this activity") { onDelete(); dismiss() }.buttonStyle(QuietButtonStyle())
                    }
                }
            }
            .navigationTitle(isNew ? "New activity" : "Edit activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private var resolvedCategory: String {
        guard let choice else { return "" }
        if choice == "other" { return custom.trimmingCharacters(in: .whitespaces).isEmpty ? "other" : custom }
        return choice
    }

    private var canSave: Bool {
        var d = draft; d.category = resolvedCategory
        return d.isValid
    }

    private func commit() {
        draft.category = resolvedCategory
        onSave(draft)
        dismiss()
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).ssSecondaryText().accessibilityAddTraits(.isHeader)
            content()
        }
    }
}
