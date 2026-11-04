import SwiftUI

/// "Add a receipt": scan with the camera, choose photos, or type it in.
struct AddReceiptSheet: View {
    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var flow: ReceiptFlow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SheetHeader(title: "Add a receipt", onClose: {
                flow.isChoosingSource = false
            })

            if let group = store.group(flow.targetGroupID) {
                Label("Goes into \(group.displayName)", systemImage: group.category.symbol)
                    .font(Theme.Fonts.subheadline)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }

            HStack(spacing: Theme.Spacing.m) {
                tile(symbol: "camera.viewfinder", title: "Scan", hint: "Use the camera", source: .camera)
                tile(symbol: "photo.on.rectangle.angled", title: "Photo", hint: "Choose from Photos", source: .photos)
                tile(symbol: "square.and.pencil", title: "Type", hint: "Enter it yourself", source: .manual)
            }

            Label("Text is read on this iPhone. Nothing is uploaded.", systemImage: "lock.fill")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .themedScreen()
        .presentationDetents([.height(360), .medium])
        .claySheet()
    }

    private func tile(symbol: String, title: String, hint: String, source: ReceiptFlow.Source) -> some View {
        Button(action: {
            flow.choose(source)
        }, label: {
            VStack(spacing: Theme.Spacing.s) {
                IconBadge(symbol: symbol, tone: source == .camera ? .positive : .neutral, size: 60)
                Text(title)
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(Theme.Colors.text)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.s)
        })
        .buttonStyle(NeumorphicCardButtonStyle(padding: Theme.Spacing.m, showsChevron: false))
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}
