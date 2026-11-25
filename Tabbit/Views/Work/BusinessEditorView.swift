import SwiftUI

/// Set up or edit a business: its name, freelance or business, and an optional tax set-aside.
struct BusinessEditorView: View {
    let target: BusinessEditorTarget

    @EnvironmentObject private var store: TabbitStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var kind: BusinessKind
    @State private var setAsideText: String
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name
        case setAside
    }

    init(target: BusinessEditorTarget) {
        self.target = target
        switch target {
        case .new:
            _name = State(initialValue: "")
            _kind = State(initialValue: .freelance)
            _setAsideText = State(initialValue: "")
        case .edit(let business):
            _name = State(initialValue: business.name)
            _kind = State(initialValue: business.kind)
            _setAsideText = State(initialValue: business.taxSetAsidePercent.map { value in
                NSDecimalNumber(decimal: value).stringValue
            } ?? "")
        }
    }

    private var existing: Business? {
        if case .edit(let business) = target {
            return store.business(business.id) ?? business
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                SheetHeader(title: existing == nil ? "Set Up Work" : "Edit Business", onClose: {
                    dismiss()
                })

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionLabel(title: "How you work")
                    ClaySegmentedPicker(selection: $kind, options: BusinessKind.allCases.map { option in
                        ClaySegmentedPicker<BusinessKind>.Option(value: option, title: option.title, symbol: option.symbol,
                                                                 accessibilityName: option.title)
                    })
                    Text(kind == .freelance
                         ? "Working for yourself, under your own name or a trading name."
                         : "A company or business with its own name.")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionLabel(title: "Name")
                    TextField(kind == .freelance ? "Freelance, or your name" : "Your business's name", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focus, equals: .name)
                        .insetField()
                        .accessibilityLabel("Name")
                    if kind == .freelance {
                        FlowLayout {
                            ForEach(nameSuggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    name = suggestion
                                }
                                .buttonStyle(ClayChipStyle(isSelected: trimmedName == suggestion))
                                .accessibilityLabel("Use \(suggestion)")
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionLabel(title: "Put aside for tax (optional)")
                    HStack(spacing: Theme.Spacing.s) {
                        TextField("25", text: $setAsideText)
                            .keyboardType(.decimalPad)
                            .focused($focus, equals: .setAside)
                            .insetField()
                            .accessibilityLabel("Percent of profit to put aside for tax")
                        Text("% of profit")
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    if setAsideIsInvalid {
                        Label("Enter a percentage between 0 and 100.", systemImage: "exclamationmark.circle.fill")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.danger)
                    } else {
                        Text("Tabbit shows how much of the year's profit to keep for your tax bill.")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }

                Button(action: save) {
                    Label(existing == nil ? "Create" : "Save Changes", systemImage: "checkmark")
                }
                .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
                .disabled(setAsideIsInvalid)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedScreen()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focus == .setAside {
                KeyboardDoneBar {
                    focus = nil
                }
            }
        }
        .claySheet()
    }

    private var nameSuggestions: [String] {
        var suggestions = ["Freelance"]
        let myName = store.me.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !myName.isEmpty && myName != "Me" {
            suggestions.append(myName)
        }
        return suggestions
    }

    private var trimmedName: String {
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var setAsidePercent: Decimal? {
        return MoneyInput.parse(setAsideText.replacingOccurrences(of: "%", with: ""))
    }

    private var setAsideIsInvalid: Bool {
        let trimmed = setAsideText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return false
        }
        guard let value = setAsidePercent else {
            return true
        }
        return value < 0 || value > 100
    }

    private func save() {
        let percent = setAsidePercent.flatMap { value in value > 0 ? value : nil }
        let finalName = trimmedName.isEmpty ? kind.title : trimmedName
        if var business = existing {
            business.name = finalName
            business.kind = kind
            business.taxSetAsidePercent = percent
            store.save(business)
        } else {
            let colorIndex = (6 + store.businesses.count * 3) % Theme.pastels.count
            store.save(Business(name: finalName, kind: kind, colorIndex: colorIndex, taxSetAsidePercent: percent))
        }
        Haptics.success()
        dismiss()
    }
}

/// Opens the job editor for a new job or an existing one.
struct JobEditorTarget: Identifiable {
    let businessID: UUID
    let job: Job?

    var id: String {
        return job?.id.uuidString ?? "new-\(businessID.uuidString)"
    }
}

/// Add or edit a job: what it is, who it's for, and when it started.
struct JobEditorView: View {
    let target: JobEditorTarget

    @EnvironmentObject private var store: TabbitStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var client: String
    @State private var startDate: Date
    @State private var choosingDate = false
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name
        case client
    }

    init(target: JobEditorTarget) {
        self.target = target
        _name = State(initialValue: target.job?.name ?? "")
        _client = State(initialValue: target.job?.client ?? "")
        _startDate = State(initialValue: target.job?.startDate ?? Calendar.current.startOfDay(for: Date()))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                SheetHeader(title: target.job == nil ? "New Job" : "Edit Job", onClose: {
                    dismiss()
                })

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionLabel(title: "Job")
                    TextField("Website redesign, kitchen fit-out…", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.next)
                        .focused($focus, equals: .name)
                        .onSubmit {
                            focus = .client
                        }
                        .insetField()
                        .accessibilityLabel("Job name")
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionLabel(title: "Client")
                    TextField("Who it's for", text: $client)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($focus, equals: .client)
                        .insetField()
                        .accessibilityLabel("Client")
                    if !clientSuggestions.isEmpty {
                        FlowLayout {
                            ForEach(clientSuggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    client = suggestion
                                }
                                .buttonStyle(ClayChipStyle(isSelected: client == suggestion))
                                .accessibilityLabel("Client, \(suggestion)")
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionLabel(title: "Started")
                    DateRowButton(symbol: "calendar", text: DateText.long(startDate)) {
                        focus = nil
                        choosingDate = true
                    }
                    .accessibilityLabel("Started, \(DateText.long(startDate))")
                }

                Button(action: save) {
                    Label(target.job == nil ? "Add Job" : "Save Changes", systemImage: "checkmark")
                }
                .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedScreen()
        .claySheet()
        .sheet(isPresented: $choosingDate) {
            DatePickerSheet(date: $startDate)
        }
        .onAppear {
            if target.job == nil {
                focus = .name
            }
        }
    }

    /// Clients from this business's other jobs, so repeat clients are one tap.
    private var clientSuggestions: [String] {
        guard let business = store.business(target.businessID) else {
            return []
        }
        var seen: Set<String> = []
        var result: [String] = []
        for job in business.jobs {
            let name = job.client.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty && !seen.contains(name.lowercased()) {
                seen.insert(name.lowercased())
                result.append(name)
            }
        }
        return Array(result.prefix(6))
    }

    private func save() {
        var job = target.job ?? Job(name: "")
        job.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        job.client = client.trimmingCharacters(in: .whitespacesAndNewlines)
        job.startDate = Calendar.current.startOfDay(for: startDate)
        store.save(job, in: target.businessID)
        Haptics.success()
        dismiss()
    }
}

/// A tappable row that shows a date (or a prompt) and opens a picker.
struct DateRowButton: View {
    let symbol: String
    let text: String
    var isPlaceholder: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(Theme.Colors.secondaryText)
                Text(text)
                    .foregroundStyle(isPlaceholder ? Theme.Colors.secondaryText : Theme.Colors.text)
                Spacer()
            }
            .font(Theme.Fonts.body)
        }
        .buttonStyle(NeumorphicCardButtonStyle(padding: Theme.Spacing.m))
    }
}

/// The clay Done bar shown above a number keyboard (which has no return key).
struct KeyboardDoneBar: View {
    let onDone: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: onDone) {
                Label("Done", systemImage: "keyboard.chevron.compact.down")
            }
            .buttonStyle(NeumorphicButtonStyle(prominence: .secondary, fullWidth: false, compact: true))
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.vertical, Theme.Spacing.s)
        .background(Theme.Colors.background.ignoresSafeArea())
    }
}
