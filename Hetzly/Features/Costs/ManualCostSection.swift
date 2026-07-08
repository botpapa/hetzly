import SwiftUI

/// The "Dedicated & Manual" section of the Costs tab: user-entered fixed
/// monthly costs (dedicated servers until Robot support lands in M3), each
/// row swipeable to reveal Edit/Delete, plus the "Add fixed cost" entry
/// point.
///
/// The Costs screen is a `ScrollView` (not a `List`), so the system
/// `.swipeActions` API isn't available here — rows use a lightweight
/// drag-to-reveal implementation instead (`SwipeRevealRow`) that snaps with
/// `.snappy` and respects the same leading-edge-cancel gesture users expect.
struct ManualCostSection: View {
    let entries: [ManualCostEntry]
    let currency: String
    let onAdd: () -> Void
    let onEdit: (ManualCostEntry) -> Void
    let onDelete: (ManualCostEntry) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.unit * 3) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Dedicated & Manual")
                Spacer()
                if !entries.isEmpty {
                    Text(total, format: .currency(code: currency))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(HetzlyColors.textSecondary)
                }
            }

            GlassCard {
                VStack(alignment: .leading, spacing: Spacing.unit * 3) {
                    if entries.isEmpty {
                        Text("Dedicated servers aren't visible to the Cloud API. Add their fixed monthly prices here so they count toward your total.")
                            .caption()
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(entries) { entry in
                            SwipeRevealRow(
                                onEdit: { onEdit(entry) },
                                onDelete: { onDelete(entry) }
                            ) {
                                row(entry)
                            }
                        }
                    }

                    Button(action: onAdd) {
                        Label("Add fixed cost", systemImage: "plus.circle.fill")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(HetzlyColors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var total: Decimal {
        entries.reduce(0) { $0 + $1.monthlyPrice }
    }

    private func row(_ entry: ManualCostEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.unit * 2) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(HetzlyColors.textPrimary)
                    .lineLimit(1)
                if let note = entry.note, !note.isEmpty {
                    Text(note)
                        .caption()
                        .lineLimit(1)
                }
            }

            Spacer(minLength: Spacing.unit * 2)

            Text("\(entry.monthlyPrice, format: .currency(code: currency))/mo")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(HetzlyColors.textPrimary)
        }
        .padding(.vertical, Spacing.unit)
        .contentShape(Rectangle())
    }
}

/// Drag-left-to-reveal Edit/Delete actions for rows living outside a `List`.
/// Snaps open/closed with `.snappy`; tapping the content while open closes
/// it. Actions are also mirrored in an accessibility custom-action pair so
/// VoiceOver users aren't forced through the drag gesture.
struct SwipeRevealRow<Content: View>: View {
    let onEdit: () -> Void
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var isOpen = false
    @GestureState private var isDragging = false

    private let actionsWidth: CGFloat = 128

    var body: some View {
        ZStack(alignment: .trailing) {
            actions
                .opacity(offset < -8 ? 1 : 0)

            content()
                .background(Color.black.opacity(0.001)) // keep hit-testing over the actions while closed
                .offset(x: offset)
                .simultaneousGesture(dragGesture)
                .onTapGesture {
                    if isOpen {
                        close()
                    }
                }
        }
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityCustomContent("Actions", "Edit or delete")
        .accessibilityAction(named: "Edit") { onEdit() }
        .accessibilityAction(named: "Delete") { onDelete() }
    }

    private var actions: some View {
        HStack(spacing: Spacing.unit * 2) {
            Button {
                close()
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textPrimary)
                    .frame(width: 52, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
            }
            .buttonStyle(.plain)

            Button {
                close()
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(HetzlyColors.textPrimary)
                    .frame(width: 52, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                            .fill(HetzlyColors.destructive.opacity(0.85))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                // Only track predominantly-horizontal drags so vertical
                // scrolling stays fluid.
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let base: CGFloat = isOpen ? -actionsWidth : 0
                offset = min(0, max(-actionsWidth - 24, base + value.translation.width))
            }
            .onEnded { value in
                let shouldOpen = offset < -actionsWidth / 2 || value.predictedEndTranslation.width < -actionsWidth
                withAnimation(.snappy) {
                    isOpen = shouldOpen
                    offset = shouldOpen ? -actionsWidth : 0
                }
            }
    }

    private func close() {
        withAnimation(.snappy) {
            isOpen = false
            offset = 0
        }
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        ScrollView {
            VStack(spacing: Spacing.unit * 6) {
                ManualCostSection(
                    entries: [
                        ManualCostEntry(name: "AX42 dedicated", monthlyPrice: Decimal(string: "39.00") ?? 0, note: "FSN1-DC14"),
                        ManualCostEntry(name: "SX65 storage", monthlyPrice: Decimal(string: "104.00") ?? 0, note: nil),
                    ],
                    currency: "EUR",
                    onAdd: {},
                    onEdit: { _ in },
                    onDelete: { _ in }
                )

                ManualCostSection(
                    entries: [],
                    currency: "EUR",
                    onAdd: {},
                    onEdit: { _ in },
                    onDelete: { _ in }
                )
            }
            .padding(Spacing.screenMargin)
        }
    }
    .preferredColorScheme(.dark)
}
