import SwiftUI

/// Set (or clear) the manual "what I actually pay" €/mo override for one
/// Cloud server — mirrors `DedicatedPriceSheet`, but for Cloud servers
/// instead of Robot dedicated ones. Reusable across two presentation sites
/// (per the pricing-accuracy wave contract): the Costs tab's per-project
/// breakdown, and the server detail page's hero/price row — so the init
/// takes everything it needs as plain values rather than a Costs-specific
/// row type.
///
/// Unlike Robot servers (which have no pricing API at all), a Cloud server
/// always has *a* list price from `/pricing` — this sheet shows it as a
/// hint so the user knows what they're overriding, and why: Hetzner has no
/// per-server real-price field, so a grandfathered/legacy rate always
/// over-reports using list price alone.
struct CloudServerPriceSheet: View {
    @Environment(\.dismiss) private var dismiss

    let store: CloudServerPriceStore
    let currency: String
    let serverNumber: Int
    let serverName: String
    /// Hetzner's current list price for this server's type + location, if
    /// known — shown as a hint, never as the value being edited.
    let listPriceMonthly: Decimal?

    @State private var monthlyPrice: Decimal?
    @State private var note: String
    @FocusState private var focusedField: Field?

    /// Captured at `init` so the title/CTA copy doesn't flip mid-edit if the
    /// underlying store happens to change while the sheet is open.
    private let hadExistingOverride: Bool

    private enum Field: Hashable {
        case price, note
    }

    init(store: CloudServerPriceStore, currency: String, serverNumber: Int, serverName: String, listPriceMonthly: Decimal?) {
        self.store = store
        self.currency = currency
        self.serverNumber = serverNumber
        self.serverName = serverName
        self.listPriceMonthly = listPriceMonthly
        let existing = store.entries.first { $0.serverNumber == serverNumber }
        self.hadExistingOverride = existing != nil
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
                                Text(serverName)
                                    .bodyPrimary()
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("What you actually pay")
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
                            if let listPriceMonthly {
                                Text("List price: \(listPriceMonthly, format: .currency(code: currency)) — set what you actually pay.")
                                    .caption()
                            } else {
                                Text("Hetzner has no per-server real-price field — enter what your invoice shows.")
                                    .caption()
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                            SectionLabel("Note (optional)")
                            GlassCard {
                                TextField("e.g. grandfathered rate", text: $note)
                                    .textFieldStyle(.plain)
                                    .focused($focusedField, equals: .note)
                                    .submitLabel(.done)
                                    .onSubmit(save)
                            }
                        }

                        PrimaryCTA(title: hadExistingOverride ? "Save changes" : "Set price", action: save)
                            .frame(maxWidth: .infinity)
                            .disabled(!canSave)

                        if hadExistingOverride {
                            Button("Clear override", action: clearOverride)
                                .foregroundStyle(HetzlyColors.destructive)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .padding(Spacing.screenMargin)
                }
            }
            .navigationTitle(hadExistingOverride ? "Edit Price" : "Set Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                if !hadExistingOverride {
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

    private func clearOverride() {
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
        CloudServerPriceSheet(
            store: CloudServerPriceStore(),
            currency: "EUR",
            serverNumber: 12345,
            serverName: "web-01",
            listPriceMonthly: Decimal(string: "69.49")
        )
    }
}

#Preview("Editing") {
    let store = CloudServerPriceStore()
    store.setPrice(serverNumber: 12345, monthlyPrice: Decimal(string: "25.49") ?? 0, note: "Grandfathered CX21 rate")

    return ZStack {
        CanvasBackground()
    }
    .preferredColorScheme(.dark)
    .sheet(isPresented: .constant(true)) {
        CloudServerPriceSheet(
            store: store,
            currency: "EUR",
            serverNumber: 12345,
            serverName: "web-01",
            listPriceMonthly: Decimal(string: "69.49")
        )
    }
}
