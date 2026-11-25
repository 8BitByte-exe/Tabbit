import SwiftUI

/// Moves a receipt to another group, to My Receipts, or to a business (Work).
struct MoveReceiptSheet: View {
    let receiptID: UUID
    var onMoved: (String) -> Void = { _ in }

    @EnvironmentObject private var store: TabbitStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                SheetHeader(title: "Move to…", onClose: {
                    dismiss()
                })
                Text("People who aren't in the new group are taken off this receipt.")
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)

                destination(name: "My Receipts", symbol: "person.fill", colorIndex: 0, groupID: nil)
                ForEach(store.groups) { group in
                    destination(name: group.displayName, symbol: group.category.symbol,
                                colorIndex: group.category.colorIndex, groupID: group.id)
                }
                if !store.businesses.isEmpty {
                    SectionLabel(title: "Work")
                        .padding(.top, Theme.Spacing.s)
                    ForEach(store.businesses) { business in
                        businessDestination(business)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .themedScreen()
        .presentationDetents([.medium, .large])
        .claySheet()
    }

    private var currentGroupID: UUID? {
        return store.receipt(receiptID)?.groupID
    }

    private var currentBusinessID: UUID? {
        return store.receipt(receiptID)?.businessID
    }

    private func businessDestination(_ business: Business) -> some View {
        let isCurrent = currentBusinessID == business.id
        return Button(action: {
            store.moveToBusiness(receiptID, businessID: business.id)
            Haptics.success()
            onMoved(business.displayName)
            dismiss()
        }, label: {
            HStack(spacing: Theme.Spacing.m) {
                CategoryBadge(symbol: business.kind.symbol, colorIndex: business.colorIndex, size: 40)
                Text(business.displayName)
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(Theme.Colors.text)
                Spacer()
                if isCurrent {
                    IconBadge(symbol: "checkmark", tone: .positive, size: 28)
                }
            }
        })
        .buttonStyle(NeumorphicCardButtonStyle(padding: Theme.Spacing.m, showsChevron: !isCurrent))
        .disabled(isCurrent)
        .accessibilityLabel(isCurrent ? "\(business.displayName), current place" : "\(business.displayName), an expense")
    }

    private func destination(name: String, symbol: String, colorIndex: Int, groupID: UUID?) -> some View {
        let isCurrent = currentGroupID == groupID && currentBusinessID == nil
        return Button(action: {
            store.move(receiptID, to: groupID)
            Haptics.success()
            onMoved(name)
            dismiss()
        }, label: {
            HStack(spacing: Theme.Spacing.m) {
                CategoryBadge(symbol: symbol, colorIndex: colorIndex, size: 40)
                Text(name)
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(Theme.Colors.text)
                Spacer()
                if isCurrent {
                    IconBadge(symbol: "checkmark", tone: .positive, size: 28)
                }
            }
        })
        .buttonStyle(NeumorphicCardButtonStyle(padding: Theme.Spacing.m, showsChevron: !isCurrent))
        .disabled(isCurrent)
        .accessibilityLabel(isCurrent ? "\(name), current place" : name)
    }
}
