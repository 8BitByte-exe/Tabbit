import SwiftUI
import UIKit

/// Review or edit a receipt: merchant, date, category, who paid, items and who
/// shared them, tax, tip and total, with the split updating as you type.
/// Fields filled in by a scan are marked with sparkles; ones it couldn't read with a warning.
struct ReceiptEditorView: View {
    let session: EditorSession

    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var flow: ReceiptFlow
    @Environment(\.dismiss) private var dismiss

    @State private var form: ReceiptForm
    @State private var errorMessage: String?
    @State private var confirmDiscard = false
    @FocusState private var focus: EditorFocus?

    enum EditorFocus: Hashable {
        case merchant
        case itemName(UUID)
        case itemPrice(UUID)
        case tax
        case tip
        case total
    }

    init(session: EditorSession) {
        self.session = session
        _form = State(initialValue: ReceiptForm(session.record))
    }

    // MARK: - Derived

    private var people: [Person] {
        return store.people(for: session.record.groupID)
    }

    private var isShared: Bool {
        return people.count > 1
    }

    /// The receipt as it would be saved right now.
    private var preview: ReceiptRecord {
        return form.record(updating: session.record)
    }

    private var hasChanges: Bool {
        return session.isNew || form != ReceiptForm(session.record)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.xl) {
                    if session.isNew && session.record.source != .manual {
                        scanBanner
                    }
                    detailsCard
                    if isShared {
                        paidByCard
                    }
                    itemsCard
                    amountsCard
                    if isShared {
                        splitCard
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.top, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .themedScreen()
            .navigationTitle(session.isNew ? "New Receipt" : "Edit Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges {
                            confirmDiscard = true
                        } else {
                            dismiss()
                        }
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focus = nil
                    }
                    .font(Theme.Fonts.headline)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focus == nil {
                    saveBar
                }
            }
            .confirmationDialog("Discard this receipt?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button(session.isNew ? "Discard Receipt" : "Discard Changes", role: .destructive) {
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {
                }
            }
            .alert("Couldn't save", isPresented: errorBinding, actions: {
                Button("OK", role: .cancel) {
                }
            }, message: {
                Text(errorMessage ?? "")
            })
        }
        .tint(Theme.Colors.accentInk)
        .interactiveDismissDisabled(hasChanges)
        .presentationBackground(Theme.Colors.background)
        .presentationCornerRadius(Theme.Radius.card)
        .onAppear {
            if session.isNew && session.record.source == .manual {
                focus = .merchant
            }
        }
    }

    private var saveBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            if !form.isValid {
                Label("Fix the marked amounts to save.", systemImage: "exclamationmark.circle.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.danger)
            }
            Button(action: save) {
                Label(session.isNew ? "Save Receipt" : "Save Changes", systemImage: "checkmark")
            }
            .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
            .disabled(!form.isValid)
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.m)
        .padding(.bottom, Theme.Spacing.s)
        .background(Theme.Colors.background.opacity(0.96).ignoresSafeArea())
    }

    private func save() {
        focus = nil
        if let message = flow.save(form.record(updating: session.record), from: session) {
            errorMessage = message
        } else {
            dismiss()
        }
    }

    private var errorBinding: Binding<Bool> {
        return Binding(get: {
            errorMessage != nil
        }, set: { isShowing in
            if !isShowing {
                errorMessage = nil
            }
        })
    }

    // MARK: - Scan banner

    private var scanBanner: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            if let data = session.thumbnailJPEG, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "sparkles")
                    .font(Theme.Fonts.title3)
                    .foregroundStyle(Theme.Colors.accentInk)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Label("Filled in from your scan", systemImage: "sparkles")
                    .font(Theme.Fonts.headline)
                    .foregroundStyle(Theme.Colors.text)
                Text(bannerMessage)
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .clayInset(cornerRadius: Theme.Radius.tile)
        .accessibilityElement(children: .combine)
    }

    private var bannerMessage: String {
        let missing = ReceiptField.allCases.filter { field in session.record.unreadable.contains(field) }
        if missing.isEmpty {
            return "Check the marked fields against the paper receipt."
        }
        let names = missing.map { field in ReceiptEditorView.name(of: field) }
        let list = ListFormatter.localizedString(byJoining: names)
        let pronoun = missing.count == 1 && missing[0] != .items ? "it" : "them"
        return "Couldn't read the \(list). Add \(pronoun) if you can."
    }

    static func name(of field: ReceiptField) -> String {
        switch field {
        case .merchant: return "merchant"
        case .date: return "date"
        case .category: return "category"
        case .total: return "total"
        case .tax: return "tax"
        case .tip: return "tip"
        case .items: return "items"
        }
    }

    /// A section title with the field's scan mark.
    private func fieldLabel(_ title: String, _ field: ReceiptField?) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            SectionLabel(title: title)
            if let field = field, preview.unreadable.contains(field) {
                Label("Couldn't read", systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.warning)
            } else if let field = field, preview.autofilled.contains(field) {
                Image(systemName: "sparkles")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.accentInk)
                    .accessibilityLabel("Filled in from the scan")
            }
        }
    }

    // MARK: - Details

    private var detailsCard: some View {
        NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    fieldLabel("Merchant", .merchant)
                    TextField("Where was this?", text: $form.merchant)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focus, equals: .merchant)
                        .insetField()
                        .accessibilityLabel("Merchant")
                }
                HStack {
                    fieldLabel("Date", .date)
                    Spacer()
                    DatePicker("Date", selection: $form.date, displayedComponents: .date)
                        .labelsHidden()
                        .tint(Theme.Colors.accentInk)
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    fieldLabel("Category", .category)
                    categoryChips
                }
            }
        }
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(SpendCategory.allCases) { category in
                    Button(action: {
                        form.category = category
                    }, label: {
                        Label(category.title, systemImage: category.symbol)
                    })
                    .buttonStyle(ClayChipStyle(isSelected: form.category == category))
                    .accessibilityAddTraits(form.category == category ? [.isSelected] : [])
                }
            }
            .padding(.vertical, Theme.Spacing.s)
            .padding(.horizontal, Theme.Spacing.xxs)
        }
        .scrollClipDisabled()
    }

    // MARK: - Paid by

    private var paidByCard: some View {
        NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionLabel(title: "Paid by")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.s) {
                        ForEach(people) { person in
                            Button(action: {
                                form.paidBy = person.id
                            }, label: {
                                HStack(spacing: Theme.Spacing.xs) {
                                    AvatarView(person: person, size: 26)
                                    Text(people.displayName(person.id))
                                }
                            })
                            .buttonStyle(ClayChipStyle(isSelected: form.paidBy == person.id))
                            .accessibilityLabel("Paid by \(people.displayName(person.id))")
                            .accessibilityAddTraits(form.paidBy == person.id ? [.isSelected] : [])
                        }
                    }
                    .padding(.vertical, Theme.Spacing.s)
                    .padding(.horizontal, Theme.Spacing.xxs)
                }
                .scrollClipDisabled()
            }
        }
    }

    // MARK: - Items

    private var itemsCard: some View {
        NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                HStack {
                    fieldLabel("Items", .items)
                    Spacer()
                    Text(Money.string(preview.itemsSubtotal))
                        .font(Theme.Fonts.money)
                        .foregroundStyle(Theme.Colors.text)
                        .accessibilityLabel("Items total \(Money.string(preview.itemsSubtotal))")
                }
                if form.items.isEmpty {
                    Text(isShared
                         ? "No items: the total is split evenly between everyone."
                         : "No items needed. Add them to search for them later.")
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                ForEach(form.items) { item in
                    ItemEditorRow(item: itemBinding(item.id),
                                  people: people,
                                  isPriceInvalid: form.invalidFields.contains(.itemPrice(item.id)),
                                  focus: $focus,
                                  onRemove: {
                                      withAnimation(Theme.Motion.standard) {
                                          form.removeItem(item.id)
                                      }
                                  })
                }
                Button(action: {
                    var newID = UUID()
                    withAnimation(Theme.Motion.standard) {
                        newID = form.addItem()
                    }
                    focus = .itemName(newID)
                }, label: {
                    Label("Add Item", systemImage: "plus")
                })
                .buttonStyle(NeumorphicButtonStyle(prominence: .secondary, compact: true))
            }
        }
    }

    /// A binding to one item by ID, safe while items are being removed.
    private func itemBinding(_ id: UUID) -> Binding<ReceiptForm.Item> {
        return Binding(get: {
            form.items.first { item in item.id == id }
                ?? ReceiptForm.Item(id: id, name: "", priceText: "", assignees: [], confidence: nil)
        }, set: { newValue in
            if let index = form.items.firstIndex(where: { item in item.id == id }) {
                form.items[index] = newValue
            }
        })
    }

    // MARK: - Amounts

    private var amountsCard: some View {
        NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                amountField(title: "Tax", field: .tax, text: $form.taxText, focusValue: .tax,
                            invalid: form.invalidFields.contains(.tax))
                tipField
                amountField(title: "Total", field: .total, text: $form.totalText, focusValue: .total,
                            invalid: form.invalidFields.contains(.total),
                            placeholder: MoneyInput.editText(preview.computedTotal))
                if form.totalText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Empty means items + tax + tip.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                if let mismatch = preview.totalMismatch {
                    mismatchNote(mismatch)
                }
                if isShared {
                    Toggle(isOn: $form.includeFees) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                            Text("Share tax & tip")
                                .font(Theme.Fonts.body)
                                .foregroundStyle(Theme.Colors.text)
                            Text(form.includeFees
                                 ? "Split in proportion to what each person had."
                                 : "The payer covers tax, tip and any extras.")
                                .font(Theme.Fonts.caption)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }
                    .toggleStyle(ClayToggleStyle())
                }
            }
        }
    }

    private func amountField(title: String, field: ReceiptField, text: Binding<String>, focusValue: EditorFocus,
                             invalid: Bool, placeholder: String = "0.00") -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                fieldLabel(title, field)
                Spacer()
                TextField(placeholder, text: text)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focus, equals: focusValue)
                    .insetField()
                    .frame(width: 150)
                    .overlay {
                        if invalid {
                            RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                                .stroke(Theme.Colors.danger, lineWidth: 2)
                        }
                    }
                    .accessibilityLabel(title)
            }
            if invalid {
                Label("That doesn't look like an amount.", systemImage: "exclamationmark.circle.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.danger)
            }
        }
    }

    private var tipField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                fieldLabel("Tip", .tip)
                Spacer()
                ClaySegmentedPicker(selection: $form.tipIsPercent, options: [
                    ClaySegmentedPicker<Bool>.Option(value: false, title: Money.currencySymbol, symbol: nil,
                                                     accessibilityName: "Tip as an amount"),
                    ClaySegmentedPicker<Bool>.Option(value: true, title: "%", symbol: nil,
                                                     accessibilityName: "Tip as a percentage"),
                ])
                .frame(width: 112)
                TextField(form.tipIsPercent ? "15" : "0.00", text: $form.tipText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focus, equals: .tip)
                    .insetField()
                    .frame(width: 96)
                    .overlay {
                        if form.invalidFields.contains(.tip) {
                            RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                                .stroke(Theme.Colors.danger, lineWidth: 2)
                        }
                    }
                    .accessibilityLabel(form.tipIsPercent ? "Tip percentage" : "Tip")
            }
            if form.tipIsPercent && preview.tipAmount != 0 {
                Text("\(Money.string(preview.tipAmount)) on \(Money.string(preview.itemsSubtotal)) of items")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            if form.invalidFields.contains(.tip) {
                Label("Enter a tip of zero or more.", systemImage: "exclamationmark.circle.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.danger)
            }
        }
    }

    private func mismatchNote(_ mismatch: Decimal) -> some View {
        let computed = preview.computedTotal
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label("Items + tax + tip come to \(Money.string(computed)). The \(Money.string(abs(mismatch))) difference is shared like tax.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Colors.warning)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: {
                form.totalText = MoneyInput.editText(computed)
            }, label: {
                Text("Use \(Money.string(computed))")
            })
            .buttonStyle(NeumorphicButtonStyle(prominence: .secondary, fullWidth: false, compact: true))
        }
    }

    // MARK: - Split preview

    private var splitCard: some View {
        let split = SplitCalculator.split(preview, members: people.map { person in person.id })
        return NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionLabel(title: "Split")
                ForEach(split.shares, id: \.personID) { share in
                    HStack(spacing: Theme.Spacing.m) {
                        if let person = people.person(share.personID) {
                            AvatarView(person: person, size: 30)
                        }
                        Text(people.displayName(share.personID))
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Colors.text)
                        Spacer()
                        MoneyText(amount: share.total, font: Theme.Fonts.money)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// One item in the editor: name, price, remove, and who shared it.
struct ItemEditorRow: View {
    @Binding var item: ReceiptForm.Item
    let people: [Person]
    let isPriceInvalid: Bool
    let focus: FocusState<ReceiptEditorView.EditorFocus?>.Binding
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                TextField("Item", text: $item.name)
                    .focused(focus, equals: .itemName(item.id))
                    .insetField()
                    .accessibilityLabel("Item name")
                TextField("0.00", text: $item.priceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused(focus, equals: .itemPrice(item.id))
                    .insetField()
                    .frame(width: 104)
                    .overlay {
                        if isPriceInvalid {
                            RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                                .stroke(Theme.Colors.danger, lineWidth: 2)
                        }
                    }
                    .accessibilityLabel("Price of \(item.name.isEmpty ? "item" : item.name)")
                Button(action: onRemove) {
                    Image(systemName: "minus")
                }
                .buttonStyle(NeumorphicIconButtonStyle(tint: Theme.Colors.danger))
                .accessibilityLabel("Remove \(item.name.isEmpty ? "item" : item.name)")
            }
            if item.isUncertain {
                Label("The scan wasn't sure about this name", systemImage: "questionmark.circle.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }
            if isPriceInvalid {
                Label("Enter a price", systemImage: "exclamationmark.circle.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.danger)
            }
            if people.count > 1 {
                assigneeChips
            }
        }
    }

    private var assigneeChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.s) {
                Button(action: {
                    item.assignees = []
                }, label: {
                    Label("Everyone", systemImage: "person.3.fill")
                })
                .buttonStyle(ClayChipStyle(isSelected: item.assignees.isEmpty))
                .accessibilityLabel("Shared by everyone")
                .accessibilityAddTraits(item.assignees.isEmpty ? [.isSelected] : [])
                ForEach(people) { person in
                    let isSelected = item.assignees.contains(person.id)
                    Button(action: {
                        item.assignees = ReceiptForm.toggled(item.assignees, person: person.id,
                                                             members: people.map { member in member.id })
                    }, label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            AvatarView(person: person, size: 24)
                            Text(people.displayName(person.id))
                        }
                    })
                    .buttonStyle(ClayChipStyle(isSelected: isSelected))
                    .accessibilityLabel("Shared by \(people.displayName(person.id))")
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                }
            }
            .padding(.vertical, Theme.Spacing.xs + 2)
            .padding(.horizontal, Theme.Spacing.xxs)
        }
        .scrollClipDisabled()
    }
}
