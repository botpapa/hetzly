import SwiftUI

/// Add/edit sheet for a manually tracked fixed monthly cost (dedicated
/// servers, colocation, anything Hetzner bills flat that the Cloud API
/// can't see). Presented from the Costs tab's "Dedicated & Manual" section.
struct ManualCostSheet: View {
    @Environment(\.dismiss) private var dismiss

    let store: ManualCostStore
    let currency: String
    /// Non-nil when editing an existing entry; nil when adding.
    var editing: ManualCostEntry?

    @State private var name: String
    @State private var monthlyPrice: Decimal?
    @State private var note: String
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name, price, note
    }

    init(store: ManualCostStore, currency: String, editing: ManualCostEntry? = nil) {
        self.store = store
        self.currency = currency
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _monthlyPrice = State(initialValue: editing?.monthlyPrice)
        _note = State(initialValue: editing?.note ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        guard let monthlyPrice else { return false }
        return !trimmedName.isEmpty && monthlyPrice > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 6) {
                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Name")
                            GlassCard {
                                TextField("e.g. AX42 dedicated", text: $name)
                                    .textFieldStyle(.plain)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .name)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .price }
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Monthly price")
                            GlassCard {
                                HStack(spacing: Spacing.unit * 2) {
                                    TextField(
                                        "0",
                                        value: $monthlyPrice,
                                        format: .number.precision(.fractionLength(0...2))
                                    )
                                    .textFieldStyle(.plain)
                                    .keyboardType(.decimalPad)
                                    .hetzlyMonoNumbers()
                                    .focused($focusedField, equals: .price)

                                    Text("\(currency)/mo")
                                        .caption()
                                }
                            }
                            Text("Net price per month, e.g. what your dedicated server invoice shows.")
                                .caption()
                        }

                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Note (optional)")
                            GlassCard {
                                TextField("e.g. FSN1, invoice R123456", text: $note)
                                    .textFieldStyle(.plain)
                                    .focused($focusedField, equals: .note)
                                    .submitLabel(.done)
                                    .onSubmit(save)
                            }
                        }

                        PrimaryCTA(title: editing == nil ? "Add fixed cost" : "Save changes", action: save)
                            .frame(maxWidth: .infinity)
                            .disabled(!canSave)
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle(editing == nil ? "Add Fixed Cost" : "Edit Fixed Cost")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if editing == nil {
                    focusedField = .name
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard canSave, let monthlyPrice else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalNote = trimmedNote.isEmpty ? nil : trimmedNote

        if let editing {
            store.update(editing.id, name: trimmedName, monthlyPrice: monthlyPrice, note: finalNote)
        } else {
            store.add(name: trimmedName, monthlyPrice: monthlyPrice, note: finalNote)
        }
        dismiss()
    }
}

#Preview {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        ManualCostSheet(store: ManualCostStore(), currency: "EUR")
    }
}

#Preview("Editing") {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        ManualCostSheet(
            store: ManualCostStore(),
            currency: "EUR",
            editing: ManualCostEntry(
                name: "AX42 dedicated",
                monthlyPrice: Decimal(string: "39.00") ?? 0,
                note: "FSN1-DC14"
            )
        )
    }
}
