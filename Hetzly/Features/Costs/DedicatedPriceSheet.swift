import SwiftUI

/// Set (or clear) the manual €/mo price for one Robot dedicated server.
/// Presented from the Costs tab's "Dedicated & Manual" section whenever a
/// dedicated-server row is tapped — whether it already has a price
/// (editing) or shows "Set price" (first time).
///
/// The server's name/number aren't editable here — unlike `ManualCostEntry`,
/// this price attaches to a specific Robot-listed server, not a free-form
/// named cost.
struct DedicatedPriceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let store: DedicatedPriceStore
    let currency: String
    let serverNumber: Int
    let serverName: String
    /// Non-nil when this server already has a price set.
    var existing: DedicatedPriceEntry?

    @State private var monthlyPrice: Decimal?
    @State private var note: String
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case price, note
    }

    init(store: DedicatedPriceStore, currency: String, serverNumber: Int, serverName: String, existing: DedicatedPriceEntry? = nil) {
        self.store = store
        self.currency = currency
        self.serverNumber = serverNumber
        self.serverName = serverName
        self.existing = existing
        _monthlyPrice = State(initialValue: existing?.monthlyPrice)
        _note = State(initialValue: existing?.note ?? "")
    }

    private var canSave: Bool {
        guard let monthlyPrice else { return false }
        return monthlyPrice > 0
    }

    var body: some View {
        NavigationStack {
            ZStack {
                CanvasBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.unit * 6) {
                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Server")
                            GlassCard {
                                HStack {
                                    Text(serverName)
                                        .bodyPrimary()
                                    Spacer()
                                    Text("#\(serverNumber)")
                                        .hetzlyMonoNumbers()
                                        .foregroundStyle(HetzlyColors.textSecondary)
                                }
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
                            Text("Robot has no pricing API for servers you already own — enter what your invoice shows.")
                                .caption()
                        }

                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Note (optional)")
                            GlassCard {
                                TextField("e.g. invoice R123456", text: $note)
                                    .textFieldStyle(.plain)
                                    .focused($focusedField, equals: .note)
                                    .submitLabel(.done)
                                    .onSubmit(save)
                            }
                        }

                        PrimaryCTA(title: existing == nil ? "Set price" : "Save changes", action: save)
                            .frame(maxWidth: .infinity)
                            .disabled(!canSave)

                        if existing != nil {
                            Button("Remove price", action: removePrice)
                                .foregroundStyle(HetzlyColors.destructive)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle(existing == nil ? "Set Price" : "Edit Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if existing == nil {
                    focusedField = .price
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func save() {
        guard canSave, let monthlyPrice else { return }
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        store.setPrice(serverNumber: serverNumber, monthlyPrice: monthlyPrice, note: trimmedNote.isEmpty ? nil : trimmedNote)
        dismiss()
    }

    private func removePrice() {
        store.removePrice(for: serverNumber)
        dismiss()
    }
}

#Preview("Set price") {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        DedicatedPriceSheet(store: DedicatedPriceStore(), currency: "EUR", serverNumber: 12345, serverName: "ax42-1")
    }
}

#Preview("Editing") {
    ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        DedicatedPriceSheet(
            store: DedicatedPriceStore(),
            currency: "EUR",
            serverNumber: 12345,
            serverName: "ax42-1",
            existing: DedicatedPriceEntry(serverNumber: 12345, monthlyPrice: Decimal(string: "39.00") ?? 0, note: "FSN1-DC14")
        )
    }
}
