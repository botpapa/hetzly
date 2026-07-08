import SwiftUI

/// One order transaction row: date, product name, status chip, and the
/// assigned server number once Hetzner has provisioned it.
struct TransactionRow: View {
    let transaction: TransactionSummary

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Spacing.unit * 2) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transaction.productName)
                            .bodyPrimary()
                            .fontWeight(.semibold)
                        Text(transaction.date, style: .date)
                            .caption()
                    }
                    Spacer(minLength: Spacing.unit * 3)
                    statusChip
                }

                if let serverNumber = transaction.serverNumber {
                    HStack(spacing: Spacing.unit) {
                        Image(systemName: "server.rack").font(.system(size: 11))
                        Text("Server #\(serverNumber)").hetzlyMonoNumbers()
                    }
                    .foregroundStyle(HetzlyColors.textSecondary)
                } else if transaction.status == .inProcess {
                    Text("Server number is assigned once provisioning finishes.")
                        .caption()
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusChip: some View {
        HStack(spacing: Spacing.unit) {
            StatusDot(transaction.status.resourceStatus)
            Text(transaction.status.displayText)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(HetzlyColors.textSecondary)
    }
}

#Preview {
    ZStack {
        CanvasBackground()
        VStack(spacing: Spacing.unit * 3) {
            ForEach(OrderPreviewFixtures.transactions) { transaction in
                TransactionRow(transaction: transaction)
            }
        }
        .padding(Spacing.screenMargin)
    }
    .preferredColorScheme(.dark)
}
