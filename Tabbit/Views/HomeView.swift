import SwiftUI

/// The landing page: scan button and saved receipts, newest first.
struct HomeView: View {
    @EnvironmentObject private var store: ReceiptStore
    @EnvironmentObject private var scanner: ScanViewModel

    @State private var isShowingSettings: Bool = false
    @State private var pendingDelete: SavedReceipt?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                scanButton
                if store.receipts.isEmpty {
                    EmptyStateCard()
                } else {
                    receiptList
                }
                if store.unreadableCount > 0 {
                    Label("\(store.unreadableCount) saved receipt(s) couldn't be opened.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.warning)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .themedScreen()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .confirmationDialog(
            "Delete this receipt?",
            isPresented: isConfirmingDelete,
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { saved in
            Button("Delete \(saved.displayTitle)", role: .destructive) {
                store.delete(id: saved.id)
            }
        } message: { _ in
            Text("Its photo and fields are removed from this iPhone.")
        }
        .onAppear {
            #if DEBUG
            if DemoMode.screen == "settings" {
                isShowingSettings = true
            }
            #endif
        }
    }

    private var isConfirmingDelete: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDelete = nil
                }
            }
        )
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.l) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(appName)
                    .font(Theme.Fonts.largeTitle)
                    .foregroundColor(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(Theme.Fonts.callout)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            Spacer(minLength: 0)
            Button(action: {
                isShowingSettings = true
            }, label: {
                Image(systemName: "gearshape")
            })
            .buttonStyle(NeumorphicIconButtonStyle())
            .accessibilityLabel("Settings")
        }
    }

    private var subtitle: String {
        switch store.receipts.count {
        case 0: return "Your receipts, kept on this iPhone"
        case 1: return "1 receipt saved"
        default: return "\(store.receipts.count) receipts saved"
        }
    }

    private var scanButton: some View {
        Button(action: {
            scanner.startScan()
        }, label: {
            Label("Scan Receipt", systemImage: "camera.viewfinder")
        })
        .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
        .accessibilityHint("Opens the camera to scan a paper receipt")
    }

    private var receiptList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            SectionLabel(title: "Saved")
            LazyVStack(spacing: Theme.Spacing.xl) {
                ForEach(store.receipts) { saved in
                    NavigationLink(value: saved.id) {
                        ReceiptCardContent(saved: saved, thumbnail: store.thumbnail(for: saved.id))
                    }
                    .buttonStyle(NeumorphicCardButtonStyle())
                    .accessibilityHint("Opens the receipt")
                    .contextMenu {
                        Button(role: .destructive, action: {
                            pendingDelete = saved
                        }, label: {
                            Label("Delete", systemImage: "trash")
                        })
                    }
                }
            }
        }
    }

    private var appName: String {
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        return displayName ?? "Tabbit"
    }
}

/// One saved receipt on the home screen.
struct ReceiptCardContent: View {
    let saved: SavedReceipt
    let thumbnail: UIImage?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    details
                    amount
                }
            } else {
                HStack(alignment: .center, spacing: Theme.Spacing.l) {
                    ReceiptThumbnail(image: thumbnail)
                    details
                    Spacer(minLength: Theme.Spacing.s)
                    amount
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(saved.displayTitle)
                .font(Theme.Fonts.headline)
                .foregroundColor(Theme.Colors.text)
                .lineLimit(2)
            Text(subtitle)
                .font(Theme.Fonts.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            StatusChip(status: StatusChip.Status(receipt: saved.receipt))
        }
    }

    private var amount: some View {
        VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
            Text(saved.receipt.total.map { total in MoneyFormatter.string(from: total) } ?? "–")
                .font(Theme.Fonts.money)
                .foregroundColor(Theme.Colors.text)
                .accessibilityLabel(totalAccessibilityLabel)
            if saved.isEdited {
                Label("Edited", systemImage: "pencil")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
    }

    private var totalAccessibilityLabel: String {
        guard let total = saved.receipt.total else {
            return "No total"
        }
        return "Total " + MoneyFormatter.string(from: total)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let date = saved.receipt.date {
            parts.append(DateText.medium(date))
        } else {
            parts.append(DateText.medium(saved.createdAt))
        }
        let count = saved.receipt.lineItems.count
        parts.append(count == 1 ? "1 item" : "\(count) items")
        return parts.joined(separator: " · ")
    }
}

/// The small photo on a receipt card, in an inset frame. A receipt icon when there's no photo.
struct ReceiptThumbnail: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small - 4, style: .continuous))
            } else {
                Image(systemName: "doc.text")
                    .font(Theme.Fonts.title)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
        .frame(width: 60, height: 76)
        .clayInset(cornerRadius: Theme.Radius.small)
        .accessibilityHidden(true)
    }
}

/// Shown when nothing has been saved yet.
struct EmptyStateCard: View {
    var body: some View {
        NeumorphicCard {
            VStack(spacing: Theme.Spacing.l) {
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundColor(Theme.Colors.accentInk)
                    .frame(width: 96, height: 96)
                    .clayInset(cornerRadius: 48)
                    .accessibilityHidden(true)
                Text("No receipts yet")
                    .font(Theme.Fonts.title)
                    .foregroundColor(Theme.Colors.text)
                Text("Scan a receipt and it's saved here, with its photo and every line item. Everything stays on this iPhone.")
                    .font(Theme.Fonts.callout)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
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

/// Dates for display.
enum DateText {
    static func medium(_ date: CalendarDate) -> String {
        guard let value = date.dateValue else {
            return date.isoString
        }
        return medium(value)
    }

    static func medium(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

extension CalendarDate {
    /// Midnight of this day in the current calendar.
    var dateValue: Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }

    init(_ date: Date) {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 2000, month: components.month ?? 1, day: components.day ?? 1)
    }
}
