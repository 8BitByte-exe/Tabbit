import SwiftUI

/// Moves a receipt to another group or to My Receipts.
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

    private func destination(name: String, symbol: String, colorIndex: Int, groupID: UUID?) -> some View {
        let isCurrent = currentGroupID == groupID
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
                    Label("Here now", systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.Colors.accentInk)
                }
            }
        })
        .buttonStyle(NeumorphicCardButtonStyle(padding: Theme.Spacing.m))
        .disabled(isCurrent)
        .accessibilityLabel(isCurrent ? "\(name), current place" : name)
    }
}
