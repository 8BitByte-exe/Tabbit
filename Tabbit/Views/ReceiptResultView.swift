import SwiftUI

/// Shows a processed scan: the parsed receipt, or the raw OCR text,
/// plus Export and Scan Again buttons.
struct ReceiptResultView: View {
    let processed: ProcessedScan
    let onScanAgain: () -> Void

    @State private var showsRawText: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $showsRawText) {
                Text("Receipt").tag(false)
                Text("Raw text").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            if showsRawText {
                rawTextView
            } else {
                receiptList
            }

            Divider()
            HStack(spacing: 12) {
                if let url = processed.exportURL {
                    ShareLink(item: url) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                ScanButton(title: "Scan Again", action: onScanAgain)
            }
            .padding()
        }
    }

    // MARK: - Parsed receipt

    private var receiptList: some View {
        let receipt = processed.receipt
        let checks = ReceiptValidator.checks(for: receipt)
        return List {
            Section {
                LabeledContent("Merchant", value: receipt.merchant ?? "Not found")
                LabeledContent("Date", value: dateText(receipt.date))
            }

            Section {
                if receipt.lineItems.isEmpty {
                    Text("No line items found")
                        .foregroundColor(Color.secondary)
                } else {
                    ForEach(receipt.lineItems.indices, id: \.self) { index in
                        itemRow(receipt.lineItems[index])
                    }
                }
            } header: {
                Text("Items (\(receipt.lineItems.count))")
            } footer: {
                if receipt.lineItems.contains(where: { item in item.isUncertain }) {
                    Text("Names marked with a question mark were hard to read. Check them against the receipt.")
                }
            }

            Section {
                amountRow(title: "Subtotal", amount: receipt.subtotal, emphasized: false)
                amountRow(title: "Tax", amount: receipt.tax, emphasized: false)
                amountRow(title: "Total", amount: receipt.total, emphasized: true)
            } header: {
                Text("Totals")
            }

            if !checks.isEmpty {
                Section {
                    ForEach(checks.indices, id: \.self) { index in
                        checkRow(checks[index])
                    }
                } header: {
                    Text("Checks")
                }
            }

            Section {
                LabeledContent("Parsed with", value: receipt.parser.displayName)
                ForEach(receipt.notes.indices, id: \.self) { index in
                    Text(receipt.notes[index])
                        .font(.footnote)
                        .foregroundColor(Color.secondary)
                }
            } footer: {
                Text("Scanning, text recognition and parsing all happen on this iPhone. Nothing is uploaded.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func itemRow(_ item: ReceiptLineItem) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(item.name)
            if item.isUncertain {
                Image(systemName: "questionmark.circle")
                    .foregroundColor(Color.orange)
                    .accessibilityLabel("Hard to read")
            }
            Spacer(minLength: 12)
            Text(MoneyFormatter.string(from: item.amount))
                .font(.body.monospacedDigit())
        }
    }

    private func amountRow(title: String, amount: Decimal?, emphasized: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .fontWeight(emphasized ? .semibold : .regular)
            Spacer(minLength: 12)
            if let amount = amount {
                Text(MoneyFormatter.string(from: amount))
                    .font(.body.monospacedDigit())
                    .fontWeight(emphasized ? .semibold : .regular)
            } else {
                Text("Not found")
                    .foregroundColor(Color.secondary)
            }
        }
    }

    private func checkRow(_ check: ReceiptCheck) -> some View {
        Label {
            Text(checkText(check))
        } icon: {
            Image(systemName: check.passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(check.passed ? Color.green : Color.orange)
        }
    }

    private func checkText(_ check: ReceiptCheck) -> String {
        let printed = MoneyFormatter.string(from: check.printed)
        let computed = MoneyFormatter.string(from: check.computed)
        switch check.kind {
        case .itemsMatchSubtotal:
            return check.passed
                ? "Items add up to the subtotal."
                : "Items add up to \(computed), but the subtotal is \(printed)."
        case .subtotalPlusTaxMatchesTotal:
            return check.passed
                ? "Subtotal + tax matches the total."
                : "Subtotal + tax is \(computed), but the total is \(printed)."
        case .itemsPlusTaxMatchesTotal:
            return check.passed
                ? "Items + tax match the total."
                : "Items + tax are \(computed), but the total is \(printed)."
        }
    }

    private func dateText(_ date: CalendarDate?) -> String {
        guard let date = date else {
            return "Not found"
        }
        var components = DateComponents()
        components.year = date.year
        components.month = date.month
        components.day = date.day
        guard let value = Calendar.current.date(from: components) else {
            return date.isoString
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: value)
    }

    // MARK: - Raw OCR text

    private var rawTextView: some View {
        let scan = processed.scan
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(summary(for: scan))
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                if scan.blocks.isEmpty {
                    Text("No text was found. Try again with the receipt flat and well lit.")
                        .foregroundColor(Color.secondary)
                } else {
                    Text(scan.plainText)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private func summary(for scan: ScanResult) -> String {
        let pages = scan.pageCount == 1 ? "1 page" : "\(scan.pageCount) pages"
        let blocks = scan.blocks.count == 1 ? "1 text block" : "\(scan.blocks.count) text blocks"
        return "\(pages) · \(blocks)"
    }
}

/// Formats amounts as plain numbers with two decimals ("1,234.56" in the US).
/// No currency symbol, because the receipt's currency isn't known yet.
enum MoneyFormatter {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()

    static func string(from amount: Decimal) -> String {
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}
