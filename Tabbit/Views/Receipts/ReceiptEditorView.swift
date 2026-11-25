import SwiftUI
import UIKit

/// Review or edit a receipt: merchant, date, category, who paid, items and who
/// shared them, tax, tip and total, with the split updating as you type.
/// Fields filled in by a scan carry a mint sparkle; ones it couldn't read, a warning.
struct ReceiptEditorView: View {
    let session: EditorSession

    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var flow: ReceiptFlow
    @Environment(\.dismiss) private var dismiss

    @State private var form: ReceiptForm
    @State private var errorMessage: String?
    @State private var dialog: ClayDialog?
    @State private var choosingCategory = false
    @State private var choosingDate = false
    @State private var choosingTime = false
    @AppStorage(MapSettings.enabledKey) private var mapEnabled = false
    @FocusState private var focus: EditorFocus?

    enum EditorFocus: Hashable {
        case merchant
        case location
        case payment
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
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                SheetHeader(title: session.isNew ? "New Receipt" : "Edit Receipt", onClose: close)
                if session.isNew && session.record.source != .manual {
                    scanBanner
                }
                expensePicker
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
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedScreen()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focus == nil {
                saveBar
            } else {
                keyboardBar
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .presentationBackground(Theme.Colors.background)
        .presentationCornerRadius(Theme.Radius.card)
        .clayDialog($dialog)
        .sheet(isPresented: $choosingCategory) {
            CategoryPickerSheet(selection: $form.category)
        }
        .sheet(isPresented: $choosingDate) {
            DatePickerSheet(date: $form.date)
        }
        .sheet(isPresented: $choosingTime) {
            TimePickerSheet(time: $form.time)
        }
        .onAppear {
            if session.isNew && session.record.source == .manual {
                focus = .merchant
            }
        }
        .task {
            #if DEBUG
            if DemoMode.screen == "category" {
                try? await Task.sleep(nanoseconds: 800_000_000)
                choosingCategory = true
            }
            #endif
        }
    }

    private func close() {
        focus = nil
        guard hasChanges else {
            dismiss()
            return
        }
        dialog = ClayDialog(
            title: session.isNew ? "Discard this receipt?" : "Discard your changes?",
            message: session.isNew ? "It hasn't been saved yet." : "The receipt stays as it was.",
            actions: [
                ClayDialog.Action(title: session.isNew ? "Discard Receipt" : "Discard Changes", symbol: "trash",
                                  kind: .destructive) {
                    dismiss()
                },
            ],
            cancelTitle: "Keep Editing"
        )
    }

    private var saveBar: some View {
        VStack(spacing: Theme.Spacing.s) {
            if let errorMessage = errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.danger)
            } else if !form.isValid {
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
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    /// Shown above the keyboard instead of the system's keyboard toolbar.
    private var keyboardBar: some View {
        HStack {
            Spacer()
            Button(action: {
                focus = nil
            }, label: {
                Label("Done", systemImage: "keyboard.chevron.compact.down")
            })
            .buttonStyle(NeumorphicButtonStyle(prominence: .secondary, fullWidth: false, compact: true))
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.vertical, Theme.Spacing.s)
        .background(Theme.Colors.background.ignoresSafeArea())
    }

    private func save() {
        focus = nil
        if let message = flow.save(form.record(updating: session.record), from: session) {
            errorMessage = message
        } else {
            dismiss()
        }
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
                IconBadge(symbol: "sparkles", tone: .positive, size: 44)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.s) {
                    IconBadge(symbol: "sparkles", tone: .positive, size: 22)
                    Text("Filled in from your scan")
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.Colors.text)
                }
                Text(bannerMessage)
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.l)
        .clayPlate(cornerRadius: Theme.Radius.tile)
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
        return "Couldn't find the \(list). Add \(pronoun) if the receipt shows \(pronoun)."
    }

    static func name(of field: ReceiptField) -> String {
        switch field {
        case .merchant: return "merchant"
        case .location: return "store location"
        case .date: return "date"
        case .time: return "time"
        case .category: return "category"
        case .payment: return "payment method"
        case .total: return "total"
        case .tax: return "tax"
        case .tip: return "tip"
        case .items: return "items"
        }
    }

    /// A section title with the field's scan mark, and why to check it when Tabbit isn't sure.
    private func fieldLabel(_ title: String, _ field: ReceiptField?) -> some View {
        let check = field.flatMap { field in preview.checks.first { check in check.field == field } }
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                SectionLabel(title: title)
                if let field = field, preview.unreadable.contains(field) {
                    StatusPill(title: "Couldn't read", symbol: "exclamationmark.triangle.fill", tone: .caution)
                } else if check != nil {
                    StatusPill(title: "Check", symbol: "eye.fill", tone: .caution)
                } else if let field = field, preview.autofilled.contains(field) {
                    IconBadge(symbol: "sparkles", tone: .positive, size: 20)
                        .accessibilityElement()
                        .accessibilityLabel("Filled in from the scan")
                }
            }
            if let check = check, let field = field, !preview.unreadable.contains(field) {
                Label(check.reason, systemImage: "info.circle.fill")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Details

    /// Personal or business: one tap, right where a scan lands.
    private var expensePicker: some View {
        ClaySegmentedPicker(selection: $form.expense, options: ExpenseKind.allCases.map { kind in
            ClaySegmentedPicker<ExpenseKind>.Option(value: kind, title: kind.title, symbol: kind.symbol,
                                                    accessibilityName: "\(kind.title) expense")
        })
    }

    private var detailsCard: some View {
        InfoCard {
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
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    fieldLabel("Location", .location)
                    TextField("Store address", text: $form.location)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focus, equals: .location)
                        .insetField()
                        .accessibilityLabel("Location")
                    if mapEnabled && ReceiptMap.status(of: preview) == .notFound {
                        Label("Apple Maps couldn't find this address. Add the street and city to pin it on the map.",
                              systemImage: "mappin.slash")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    fieldLabel("Date", .date)
                    Button(action: {
                        focus = nil
                        choosingDate = true
                    }, label: {
                        HStack {
                            Image(systemName: "calendar")
                                .foregroundStyle(Theme.Colors.secondaryText)
                            Text(DateText.long(form.date))
                                .foregroundStyle(Theme.Colors.text)
                            Spacer()
                        }
                        .font(Theme.Fonts.body)
                    })
                    .buttonStyle(NeumorphicCardButtonStyle(padding: Theme.Spacing.m))
                    .accessibilityLabel("Date, \(DateText.long(form.date))")
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    fieldLabel("Time", .time)
                    Button(action: {
                        focus = nil
                        choosingTime = true
                    }, label: {
                        HStack {
                            Image(systemName: "clock")
                                .foregroundStyle(Theme.Colors.secondaryText)
                            Text(form.time.map { time in DateText.time(time) } ?? "Add a time")
                                .foregroundStyle(form.time == nil ? Theme.Colors.secondaryText : Theme.Colors.text)
                            Spacer()
                        }
                        .font(Theme.Fonts.body)
                    })
                    .buttonStyle(NeumorphicCardButtonStyle(padding: Theme.Spacing.m))
                    .accessibilityLabel(form.time.map { time in "Time, \(DateText.time(time))" } ?? "Add a time")
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    fieldLabel("Category", .category)
                    Button(action: {
                        focus = nil
                        choosingCategory = true
                    }, label: {
                        HStack(spacing: Theme.Spacing.m) {
                            CategoryBadge(symbol: form.category.symbol, colorIndex: form.category.colorIndex, size: 32)
                            Text(form.category.title)
                                .font(Theme.Fonts.body)
                                .foregroundStyle(Theme.Colors.text)
                            Spacer()
                        }
                    })
                    .buttonStyle(NeumorphicCardButtonStyle(padding: Theme.Spacing.m))
                    .accessibilityLabel("Category, \(form.category.title)")
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    fieldLabel("Paid with", .payment)
                    TextField("Card, cash…", text: $form.paymentMethod)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focus, equals: .payment)
                        .insetField()
                        .accessibilityLabel("Paid with")
                }
            }
        }
    }

    // MARK: - Paid by

    private var paidByCard: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionLabel(title: "Paid by")
                FlowLayout {
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
            }
        }
    }

    // MARK: - Items

    private var itemsCard: some View {
        InfoCard {
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
        InfoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                amountField(title: "Tax", field: .tax, text: $form.taxText, focusValue: .tax,
                            invalid: form.invalidFields.contains(.tax))
                if let included = session.record.parsed?.includedTax, included > 0,
                   form.taxText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Label("The prices already include \(Money.string(included)) tax.", systemImage: "info.circle")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
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
                    .frame(width: 140)
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
                .frame(width: 108)
                TextField(form.tipIsPercent ? "15" : "0.00", text: $form.tipText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focus, equals: .tip)
                    .insetField()
                    .frame(width: 92)
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
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                IconBadge(symbol: "exclamationmark", tone: .caution, size: 22)
                Text("Items + tax + tip come to \(Money.string(computed)). The \(Money.string(abs(mismatch))) difference is shared like tax.")
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: {
                form.totalText = MoneyInput.editText(computed)
            }, label: {
                Text("Use \(Money.string(computed))")
            })
            .buttonStyle(NeumorphicButtonStyle(prominence: .secondary, fullWidth: false, compact: true))
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
            .fill(Theme.Colors.cautionFill.opacity(0.35)))
    }

    // MARK: - Split preview

    private var splitCard: some View {
        let split = SplitCalculator.split(preview, members: people.map { person in person.id })
        return InfoCard {
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
                    .frame(width: 100)
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
                .buttonStyle(NeumorphicIconButtonStyle(prominence: .destructive))
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
        .padding(.bottom, Theme.Spacing.xs)
    }

    private var assigneeChips: some View {
        FlowLayout {
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
        .padding(.vertical, Theme.Spacing.xs)
    }
}

/// All spending categories as a grid of tiles.
struct CategoryPickerSheet: View {
    @Binding var selection: SpendCategory

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: Theme.Spacing.m)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                SheetHeader(title: "Category", onClose: {
                    dismiss()
                })
                LazyVGrid(columns: columns, spacing: Theme.Spacing.m) {
                    ForEach(SpendCategory.allCases) { category in
                        tile(category)
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

    private func tile(_ category: SpendCategory) -> some View {
        let isSelected = category == selection
        return Button(action: {
            selection = category
            Haptics.selection()
            dismiss()
        }, label: {
            VStack(spacing: Theme.Spacing.s) {
                CategoryBadge(symbol: category.symbol, colorIndex: category.colorIndex, size: 44)
                Text(category.title)
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 92)
            .background {
                ClayBackground(shape: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous),
                               style: isSelected ? .accent : .raised, elevation: Theme.Elevations.small)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        })
        .buttonStyle(.plain)
        .accessibilityLabel(category.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
