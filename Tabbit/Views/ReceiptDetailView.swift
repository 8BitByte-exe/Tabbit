import SwiftUI
import UIKit

/// One saved receipt: photo, fields (editable), checks, raw text, export and delete.
struct ReceiptDetailView: View {
    let receiptID: UUID

    @EnvironmentObject private var store: ReceiptStore
    @Environment(\.dismiss) private var dismiss

    /// The editable copy while editing; nil when just viewing.
    @State private var draft: ReceiptDraft?
    @State private var firstPage: UIImage?
    @State private var isShowingPhotos: Bool = false
    @State private var showsRawText: Bool = false
    @State private var isConfirmingDelete: Bool = false
    @State private var exportURL: URL?
    @State private var message: String?

    var body: some View {
        Group {
            if let saved = store.receipt(id: receiptID) {
                content(saved)
            } else {
                Text("This receipt was deleted.")
                    .font(Theme.Fonts.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .themedScreen()
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(editButtonTitle) {
                    toggleEditing()
                }
                .font(Theme.Fonts.headline)
            }
        }
        .onDisappear {
            // Leaving while editing still keeps the changes.
            if let draft = draft, let saved = store.receipt(id: receiptID) {
                save(draft, over: saved)
            }
        }
    }

    private static let bottomID = "bottom"

    private var navigationTitleText: String {
        return draft == nil ? "Receipt" : "Edit Receipt"
    }

    private var editButtonTitle: String {
        return draft == nil ? "Edit" : "Done"
    }

    // MARK: - Layout

    private func content(_ saved: SavedReceipt) -> some View {
        let shown = draft?.receipt ?? saved.receipt
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    summaryCard(saved, shown: shown)
                    if saved.pageImageCount > 0 {
                        photoCard(saved)
                    }
                    itemsCard(shown)
                    totalsCard(shown)
                    checksCard(shown)
                    aboutCard(saved)
                    rawTextCard(saved)
                    actions(saved)
                        .id(ReceiptDetailView.bottomID)
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.xl)
            }
            .onAppear {
                #if DEBUG
                if DemoMode.screen == "detail-bottom" {
                    proxy.scrollTo(ReceiptDetailView.bottomID, anchor: .bottom)
                }
                #endif
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: saved.updatedAt) {
            exportURL = ScanProcessor.writeExport(for: saved)
        }
        .task(id: receiptID) {
            firstPage = store.pageImage(for: receiptID, page: 0)
            #if DEBUG
            if DemoMode.screen == "edit" && draft == nil {
                draft = ReceiptDraft(saved.receipt)
            }
            #endif
        }
        .fullScreenCover(isPresented: $isShowingPhotos) {
            PhotoViewer(receiptID: receiptID, pageCount: saved.pageImageCount)
                .environmentObject(store)
        }
        .confirmationDialog("Delete this receipt?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
            Button("Delete Receipt", role: .destructive) {
                draft = nil
                store.delete(id: receiptID)
                dismiss()
            }
        } message: {
            Text("Its photo and fields are removed from this iPhone.")
        }
    }

    // MARK: - Summary

    private func summaryCard(_ saved: SavedReceipt, shown: Receipt) -> some View {
        NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                if draft != nil {
                    SectionLabel(title: "Merchant")
                    TextField("Store name", text: draftBinding(\.merchant, default: ""))
                        .textInputAutocapitalization(.words)
                        .insetField()
                    SectionLabel(title: "Date")
                    dateEditor
                } else {
                    Text(saved.displayTitle)
                        .font(Theme.Fonts.title)
                        .foregroundColor(Theme.Colors.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(shown.date.map { date in DateText.medium(date) } ?? "No date found")
                        .font(Theme.Fonts.callout)
                        .foregroundColor(Theme.Colors.secondaryText)
                    HStack(alignment: .firstTextBaseline) {
                        Text(shown.total.map { total in MoneyFormatter.string(from: total) } ?? "No total")
                            .font(Theme.Fonts.bigMoney)
                            .foregroundColor(Theme.Colors.text)
                        Spacer(minLength: Theme.Spacing.s)
                        StatusChip(status: StatusChip.Status(receipt: shown))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var dateEditor: some View {
        if let date = draft?.date {
            HStack(spacing: Theme.Spacing.m) {
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { date.dateValue ?? Date() },
                        set: { newValue in draft?.date = CalendarDate(newValue) }
                    ),
                    displayedComponents: .date
                )
                .labelsHidden()
                .tint(Theme.Colors.accentInk)
                Spacer(minLength: 0)
                Button(action: {
                    draft?.date = nil
                }, label: {
                    Image(systemName: "xmark")
                })
                .buttonStyle(NeumorphicIconButtonStyle(tint: Theme.Colors.secondaryText))
                .accessibilityLabel("Remove date")
            }
        } else {
            Button(action: {
                draft?.date = CalendarDate(Date())
            }, label: {
                Label("Add date", systemImage: "calendar.badge.plus")
            })
            .buttonStyle(NeumorphicButtonStyle(prominence: .secondary, fullWidth: false))
        }
    }

    // MARK: - Photo

    private func photoCard(_ saved: SavedReceipt) -> some View {
        Button(action: {
            isShowingPhotos = true
        }, label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionLabel(title: saved.pageImageCount == 1 ? "Photo" : "Photos (\(saved.pageImageCount) pages)")
                ZStack {
                    if let image = firstPage {
                        // Fill the width and show the top of the receipt (merchant, date).
                        Color.clear
                            .frame(height: 220)
                            .frame(maxWidth: .infinity)
                            .overlay(alignment: .top) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous))
                    } else {
                        ProgressView()
                            .frame(height: 220)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(Theme.Spacing.s)
                .clayInset(cornerRadius: Theme.Radius.field + Theme.Spacing.s)
                Label("Tap to view full size", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        })
        .buttonStyle(NeumorphicCardButtonStyle())
        .accessibilityLabel("Receipt photo")
        .accessibilityHint("Opens the photo full screen")
    }

    // MARK: - Items

    private func itemsCard(_ shown: Receipt) -> some View {
        NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionLabel(title: "Items (\(draft?.items.count ?? shown.lineItems.count))")
                if let draft = draft {
                    ForEach(draft.items) { item in
                        itemEditor(item)
                    }
                    Button(action: {
                        self.draft?.addItem()
                    }, label: {
                        Label("Add item", systemImage: "plus")
                    })
                    .buttonStyle(NeumorphicButtonStyle(prominence: .secondary))
                } else if shown.lineItems.isEmpty {
                    Text("No line items found. Tap Edit to add them.")
                        .font(Theme.Fonts.callout)
                        .foregroundColor(Theme.Colors.secondaryText)
                } else {
                    ForEach(shown.lineItems.indices, id: \.self) { index in
                        itemRow(shown.lineItems[index])
                    }
                    if shown.lineItems.contains(where: { item in item.isUncertain }) {
                        Label("Names with a question mark were hard to read.", systemImage: "questionmark.circle")
                            .font(Theme.Fonts.caption)
                            .foregroundColor(Theme.Colors.secondaryText)
                    }
                }
            }
        }
    }

    private func itemRow(_ item: ReceiptLineItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
            Text(item.name)
                .font(Theme.Fonts.body)
                .foregroundColor(Theme.Colors.text)
            if item.isUncertain {
                Image(systemName: "questionmark.circle")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.warning)
                    .accessibilityLabel("Hard to read")
            }
            Spacer(minLength: Theme.Spacing.m)
            Text(MoneyFormatter.string(from: item.amount))
                .font(Theme.Fonts.money)
                .foregroundColor(Theme.Colors.text)
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func itemEditor(_ item: ReceiptDraft.Item) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            TextField("Item name", text: itemBinding(item.id, \.name))
                .textInputAutocapitalization(.words)
                .insetField()
            HStack(spacing: Theme.Spacing.m) {
                AmountField(placeholder: "0.00", text: itemBinding(item.id, \.amountText),
                            label: "Amount for \(item.name)")
                    .frame(maxWidth: 160)
                Spacer(minLength: 0)
                Button(action: {
                    draft?.removeItem(id: item.id)
                }, label: {
                    Image(systemName: "minus")
                })
                .buttonStyle(NeumorphicIconButtonStyle(tint: Theme.Colors.accentInk))
                .accessibilityLabel("Remove \(item.name.isEmpty ? "item" : item.name)")
            }
        }
        .padding(.bottom, Theme.Spacing.s)
    }

    // MARK: - Totals

    private func totalsCard(_ shown: Receipt) -> some View {
        NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionLabel(title: "Totals")
                if draft != nil {
                    totalEditor("Subtotal", text: draftBinding(\.subtotalText, default: ""))
                    totalEditor("Tax", text: draftBinding(\.taxText, default: ""))
                    totalEditor("Total", text: draftBinding(\.totalText, default: ""))
                } else {
                    totalRow("Subtotal", shown.subtotal, emphasized: false)
                    totalRow("Tax", shown.tax, emphasized: false)
                    totalRow("Total", shown.total, emphasized: true)
                }
            }
        }
    }

    private func totalRow(_ title: String, _ amount: Decimal?, emphasized: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(emphasized ? Theme.Fonts.headline : Theme.Fonts.body)
                .foregroundColor(Theme.Colors.text)
            Spacer(minLength: Theme.Spacing.m)
            if let amount = amount {
                Text(MoneyFormatter.string(from: amount))
                    .font(emphasized ? Theme.Fonts.headline.monospacedDigit() : Theme.Fonts.money)
                    .foregroundColor(Theme.Colors.text)
            } else {
                Text("Not found")
                    .font(Theme.Fonts.callout)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private func totalEditor(_ title: String, text: Binding<String>) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(title)
                .font(Theme.Fonts.body)
                .foregroundColor(Theme.Colors.text)
            Spacer(minLength: Theme.Spacing.m)
            AmountField(placeholder: "–", text: text, label: title)
                .frame(width: 140)
        }
    }

    // MARK: - Checks and notes

    private func checksCard(_ shown: Receipt) -> some View {
        let checks = ReceiptValidator.checks(for: shown)
        return NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionLabel(title: "Checks")
                if checks.isEmpty {
                    Label("Add a subtotal or total to check the math.", systemImage: "questionmark.circle")
                        .font(Theme.Fonts.callout)
                        .foregroundColor(Theme.Colors.secondaryText)
                } else {
                    ForEach(checks.indices, id: \.self) { index in
                        checkRow(checks[index])
                    }
                }
            }
        }
    }

    private func checkRow(_ check: ReceiptCheck) -> some View {
        Label {
            Text(CheckText.describe(check))
                .font(Theme.Fonts.callout)
                .foregroundColor(Theme.Colors.text)
        } icon: {
            Image(systemName: check.passed ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(check.passed ? Theme.Colors.success : Theme.Colors.warning)
        }
        .accessibilityElement(children: .combine)
    }

    private func aboutCard(_ saved: SavedReceipt) -> some View {
        NeumorphicInsetCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Label("Parsed with \(saved.parsed.parser.displayName)", systemImage: "cpu")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                ForEach(saved.parsed.notes.indices, id: \.self) { index in
                    Text(saved.parsed.notes[index])
                        .font(Theme.Fonts.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                if saved.isEdited && draft == nil {
                    Button(action: {
                        var restored = saved
                        restored.receipt = saved.parsed
                        persist(restored)
                    }, label: {
                        Label("Undo my edits", systemImage: "arrow.uturn.backward")
                            .font(Theme.Fonts.caption)
                            .foregroundColor(Theme.Colors.accentInk)
                            .frame(minHeight: Theme.Size.tapTarget)
                    })
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Raw text

    private func rawTextCard(_ saved: SavedReceipt) -> some View {
        NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Button(action: {
                    showsRawText.toggle()
                }, label: {
                    HStack {
                        Label("Recognized text", systemImage: "text.alignleft")
                            .font(Theme.Fonts.headline)
                            .foregroundColor(Theme.Colors.text)
                        Spacer()
                        Image(systemName: showsRawText ? "chevron.up" : "chevron.down")
                            .font(Theme.Fonts.headline)
                            .foregroundColor(Theme.Colors.accentInk)
                    }
                    .frame(minHeight: Theme.Size.tapTarget)
                    .contentShape(Rectangle())
                })
                .buttonStyle(.plain)
                .accessibilityValue(showsRawText ? "Shown" : "Hidden")
                if showsRawText {
                    Text(saved.scan.plainText.isEmpty ? "No text was recognized." : saved.scan.plainText)
                        .font(Theme.Fonts.mono)
                        .foregroundColor(Theme.Colors.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.l)
                        .clayInset(cornerRadius: Theme.Radius.field)
                }
            }
        }
    }

    // MARK: - Actions

    private func actions(_ saved: SavedReceipt) -> some View {
        VStack(spacing: Theme.Spacing.l) {
            if let message = message {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Fonts.callout)
                    .foregroundColor(Theme.Colors.warning)
            }
            if let url = exportURL {
                ShareLink(item: url) {
                    Label("Export scan", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(NeumorphicButtonStyle(prominence: .secondary))
            }
            Button(action: {
                isConfirmingDelete = true
            }, label: {
                Label("Delete Receipt", systemImage: "trash")
                    .foregroundColor(Theme.Colors.accentInk)
            })
            .buttonStyle(NeumorphicButtonStyle(prominence: .secondary))
        }
    }

    // MARK: - Editing

    private func toggleEditing() {
        guard let saved = store.receipt(id: receiptID) else {
            return
        }
        if let current = draft {
            if current.hasInvalidAmounts {
                message = "Some amounts aren't numbers. Fix the fields marked with a warning, then tap Done."
                return
            }
            save(current, over: saved)
            draft = nil
        } else {
            message = nil
            draft = ReceiptDraft(saved.receipt)
        }
    }

    private func save(_ draft: ReceiptDraft, over saved: SavedReceipt) {
        var updated = saved
        updated.receipt = draft.receipt
        guard updated.receipt != saved.receipt else {
            return
        }
        persist(updated)
    }

    private func persist(_ updated: SavedReceipt) {
        do {
            try store.update(updated)
            message = nil
            Haptics.success()
        } catch {
            message = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private func draftBinding(_ keyPath: WritableKeyPath<ReceiptDraft, String>, default fallback: String) -> Binding<String> {
        Binding(
            get: { draft?[keyPath: keyPath] ?? fallback },
            set: { newValue in draft?[keyPath: keyPath] = newValue }
        )
    }

    private func itemBinding(_ id: UUID, _ keyPath: WritableKeyPath<ReceiptDraft.Item, String>) -> Binding<String> {
        Binding(
            get: {
                guard let item = draft?.items.first(where: { candidate in candidate.id == id }) else {
                    return ""
                }
                return item[keyPath: keyPath]
            },
            set: { newValue in
                guard let index = draft?.items.firstIndex(where: { candidate in candidate.id == id }) else {
                    return
                }
                draft?.items[index][keyPath: keyPath] = newValue
            }
        )
    }
}

/// An inset field for an amount: right-aligned digits, a keyboard with a minus key,
/// and a warning icon + outline when the text isn't a number.
struct AmountField: View {
    let placeholder: String
    @Binding var text: String
    let label: String

    var body: some View {
        let isValid = ReceiptDraft.isValid(text)
        return HStack(spacing: Theme.Spacing.xs) {
            if !isValid {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundColor(Theme.Colors.warning)
                    .accessibilityHidden(true)
            }
            TextField(placeholder, text: $text)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .font(Theme.Fonts.money)
        }
        .insetField()
        .overlay {
            if !isValid {
                RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                    .stroke(Theme.Colors.warning, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
        .accessibilityValue(isValid ? text : "\(text), not a number")
    }
}

/// Plain-language descriptions of the arithmetic checks.
enum CheckText {
    static func describe(_ check: ReceiptCheck) -> String {
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
}
