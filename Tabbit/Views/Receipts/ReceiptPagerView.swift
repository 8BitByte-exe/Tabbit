import SwiftUI
import UIKit

/// A receipt's details. Swipe sideways for the other receipts in the same group
/// (or My Receipts).
struct ReceiptPagerView: View {
    let startID: UUID
    let groupID: UUID?

    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var flow: ReceiptFlow
    @Environment(\.dismiss) private var dismiss

    @State private var selection: UUID
    @State private var moving: ReceiptRecord?
    @State private var deleting: ReceiptRecord?
    @State private var shareFile: ShareFile?
    @State private var toast: String?

    init(startID: UUID, groupID: UUID?) {
        self.startID = startID
        self.groupID = groupID
        _selection = State(initialValue: startID)
    }

    private var receipts: [ReceiptRecord] {
        return store.receipts(in: groupID)
    }

    private var current: ReceiptRecord? {
        return store.receipt(selection)
    }

    var body: some View {
        let list = receipts
        return TabView(selection: $selection) {
            ForEach(list) { receipt in
                ReceiptDetailPage(receipt: receipt)
                    .tag(receipt.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .themedScreen()
        .navigationTitle(positionText(in: list))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if let receipt = current {
                    Button(action: {
                        flow.edit(receipt)
                    }, label: {
                        Image(systemName: "pencil")
                    })
                    .accessibilityLabel("Edit receipt")
                    moreMenu(receipt)
                }
            }
        }
        .onChange(of: list.map { receipt in receipt.id }) { _, ids in
            if !ids.contains(selection) {
                if let first = ids.first {
                    selection = first
                } else {
                    dismiss()
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .toast($toast)
        .sheet(item: $moving) { receipt in
            MoveReceiptSheet(receiptID: receipt.id, onMoved: { name in
                toast = "Moved to \(name)"
            })
            .environmentObject(store)
        }
        .sheet(item: $shareFile) { file in
            ActivityView(items: [file.url])
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Delete this receipt?", isPresented: deletingBinding, titleVisibility: .visible,
                            presenting: deleting, actions: { receipt in
            Button("Delete Receipt", role: .destructive) {
                store.delete(receipt.id)
            }
            Button("Cancel", role: .cancel) {
            }
        }, message: { receipt in
            Text("“\(receipt.displayTitle)” and its photos will be deleted from this iPhone.")
        })
    }

    private func moreMenu(_ receipt: ReceiptRecord) -> some View {
        Menu {
            Button(action: {
                moving = receipt
            }, label: {
                Label("Move to…", systemImage: "folder")
            })
            if receipt.scan != nil {
                Button(action: {
                    if let url = ScanProcessor.writeExport(for: receipt) {
                        shareFile = ShareFile(url: url)
                    }
                }, label: {
                    Label("Export Scan Data", systemImage: "square.and.arrow.up")
                })
            }
            Button(role: .destructive, action: {
                deleting = receipt
            }, label: {
                Label("Delete", systemImage: "trash")
            })
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("More")
    }

    private func positionText(in list: [ReceiptRecord]) -> String {
        guard let index = list.firstIndex(where: { receipt in receipt.id == selection }), list.count > 1 else {
            return "Receipt"
        }
        return "\(index + 1) of \(list.count)"
    }

    private var deletingBinding: Binding<Bool> {
        return Binding(get: {
            deleting != nil
        }, set: { isShowing in
            if !isShowing {
                deleting = nil
            }
        })
    }
}

/// One receipt: the total and photo, who owes what, the items, and the parser's notes.
struct ReceiptDetailPage: View {
    let receipt: ReceiptRecord

    @EnvironmentObject private var store: TabbitStore
    @State private var expanded: Set<UUID> = []
    @State private var showsPhotos = false

    private var people: [Person] {
        return store.people(for: receipt.groupID)
    }

    private var isShared: Bool {
        return people.count > 1
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                hero
                if isShared {
                    owesCard
                }
                itemsCard
                if let notes = receipt.parsed?.notes, !notes.isEmpty {
                    notesCard(notes)
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .fullScreenCover(isPresented: $showsPhotos) {
            PhotoViewer(receiptID: receipt.id)
                .environmentObject(store)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        NeumorphicCard {
            HStack(alignment: .top, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.m) {
                        CategoryBadge(symbol: receipt.category.symbol, colorIndex: receipt.category.colorIndex)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text(receipt.displayTitle)
                                .font(Theme.Fonts.title3)
                                .foregroundStyle(Theme.Colors.text)
                            Text(receipt.category.title)
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    MoneyText(amount: receipt.effectiveTotal, font: Theme.Fonts.bigMoney)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Label(DateText.long(receipt.date), systemImage: "calendar")
                        if isShared {
                            Label("Paid by \(payerName)", systemImage: "creditcard.fill")
                        }
                    }
                    .font(Theme.Fonts.subheadline)
                    .foregroundStyle(Theme.Colors.secondaryText)
                }
                Spacer(minLength: 0)
                photoButton
            }
        }
    }

    private var payerName: String {
        let name = people.displayName(receipt.paidBy)
        return name == "You" ? "you" : name
    }

    private var photoButton: some View {
        Button(action: {
            showsPhotos = true
        }, label: {
            Group {
                if receipt.pageImageCount > 0, let image = store.thumbnail(for: receipt.id) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(Theme.Fonts.title3)
                        .foregroundStyle(Theme.Colors.accentInk)
                        .frame(width: 72, height: 96)
                        .clayInset(cornerRadius: Theme.Radius.small)
                }
            }
        })
        .buttonStyle(.plain)
        .accessibilityLabel(receipt.pageImageCount > 0 ? "Show photo" : "Add a photo")
    }

    // MARK: - Who owes what

    private var owesCard: some View {
        let split = store.split(receipt)
        return NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionLabel(title: "Who owes what")
                ForEach(split.shares, id: \.personID) { share in
                    shareRow(share)
                }
            }
        }
    }

    private func shareRow(_ share: PersonShare) -> some View {
        let isOpen = expanded.contains(share.personID)
        let name = people.displayName(share.personID)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Button(action: {
                withAnimation(Theme.Motion.standard) {
                    if isOpen {
                        expanded.remove(share.personID)
                    } else {
                        expanded.insert(share.personID)
                    }
                }
            }, label: {
                HStack(spacing: Theme.Spacing.m) {
                    if let person = people.person(share.personID) {
                        AvatarView(person: person, size: 36)
                    }
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(name)
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Colors.text)
                        Text(statusText(for: share))
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(share.personID == receipt.paidBy
                                             ? Theme.Colors.accentInk : Theme.Colors.secondaryText)
                    }
                    Spacer()
                    MoneyText(amount: share.total, font: Theme.Fonts.money)
                    Image(systemName: "chevron.down")
                        .font(Theme.Fonts.caption.weight(.bold))
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .frame(minHeight: Theme.Size.tapTarget)
                .contentShape(Rectangle())
            })
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint(isOpen ? "Hides the breakdown" : "Shows the breakdown")

            if isOpen {
                ShareBreakdown(share: share)
            }
        }
    }

    private func statusText(for share: PersonShare) -> String {
        if share.personID == receipt.paidBy {
            return "Paid \(Money.string(receipt.effectiveTotal))"
        }
        if share.totalCents == 0 {
            return "Nothing to pay"
        }
        return "Owes \(payerName)"
    }

    // MARK: - Items

    private var itemsCard: some View {
        NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionLabel(title: receipt.items.isEmpty ? "Amounts" : "Items")
                ForEach(receipt.items) { item in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Text(item.name)
                                    .font(Theme.Fonts.body)
                                    .foregroundStyle(Theme.Colors.text)
                                if item.isUncertain {
                                    Image(systemName: "questionmark.circle.fill")
                                        .font(Theme.Fonts.caption)
                                        .foregroundStyle(Theme.Colors.warning)
                                        .accessibilityLabel("Name may be misread")
                                }
                            }
                            if isShared {
                                Text(assigneeText(item))
                                    .font(Theme.Fonts.caption)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                        Spacer()
                        Text(Money.string(item.price))
                            .font(Theme.Fonts.money)
                            .foregroundStyle(Theme.Colors.text)
                    }
                    .accessibilityElement(children: .combine)
                }
                VStack(spacing: Theme.Spacing.s) {
                    if !receipt.items.isEmpty {
                        AmountRow(title: "Items", amount: receipt.itemsSubtotal)
                    }
                    if let tax = receipt.tax {
                        AmountRow(title: "Tax", amount: tax)
                    }
                    if receipt.tip != nil {
                        AmountRow(title: tipTitle, amount: receipt.tipAmount)
                    }
                    AmountRow(title: "Total", amount: receipt.effectiveTotal, emphasized: true)
                }
                .padding(Theme.Spacing.m)
                .clayInset(cornerRadius: Theme.Radius.tile)
                if let mismatch = receipt.totalMismatch {
                    Label(mismatchText(mismatch), systemImage: "exclamationmark.triangle.fill")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func mismatchText(_ mismatch: Decimal) -> String {
        let direction = mismatch > 0 ? "more" : "less"
        return "The printed total is \(Money.string(abs(mismatch))) \(direction) than items + tax + tip. "
            + "The difference is shared like tax."
    }

    private var tipTitle: String {
        if case .some(.percent(let percent)) = receipt.tip {
            return "Tip (\(NSDecimalNumber(decimal: percent).stringValue)%)"
        }
        return "Tip"
    }

    private func assigneeText(_ item: SplitItem) -> String {
        let valid = SplitCalculator.validAssignees(item.assignees, everyone: people.map { person in person.id })
        if valid.count == people.count {
            return "Everyone"
        }
        return valid.map { id in people.displayName(id) }.joined(separator: ", ")
    }

    // MARK: - Notes

    private func notesCard(_ notes: [String]) -> some View {
        NeumorphicInsetCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Label("From the scan", systemImage: "text.viewfinder")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                ForEach(notes, id: \.self) { note in
                    Text(note)
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// One person's items and fee share on a receipt.
struct ShareBreakdown: View {
    let share: PersonShare

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if share.items.isEmpty && share.feeCents == 0 {
                Text("Nothing on this receipt.")
            }
            ForEach(share.items, id: \.itemID) { item in
                HStack {
                    Text(item.splitWays > 1 ? "\(item.name) (÷\(item.splitWays))" : item.name)
                    Spacer()
                    Text(Money.string(Money.fromCents(item.cents)))
                        .monospacedDigit()
                }
            }
            if share.feeCents != 0 {
                HStack {
                    Text(share.items.isEmpty ? "Even share" : "Tax & tip share")
                    Spacer()
                    Text(Money.string(Money.fromCents(share.feeCents)))
                        .monospacedDigit()
                }
            }
        }
        .font(Theme.Fonts.caption)
        .foregroundStyle(Theme.Colors.secondaryText)
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clayInset(cornerRadius: Theme.Radius.small)
    }
}
