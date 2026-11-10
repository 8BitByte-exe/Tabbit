import SwiftUI

/// Create or edit a group: name, category and people.
struct GroupEditorView: View {
    let target: GroupEditorTarget

    @EnvironmentObject private var store: TabbitStore
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var category: GroupCategory
    @State private var members: [Person]
    @State private var newPersonName = ""
    @State private var dialog: ClayDialog?
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name
        case newPerson
    }

    init(target: GroupEditorTarget) {
        self.target = target
        switch target {
        case .new:
            _name = State(initialValue: "")
            _category = State(initialValue: .trip)
            _members = State(initialValue: [])
        case .edit(let group):
            _name = State(initialValue: group.name)
            _category = State(initialValue: group.category)
            _members = State(initialValue: group.members.filter { person in !person.isMe })
        }
    }

    private var existingGroup: SplitGroup? {
        if case .edit(let group) = target {
            return store.group(group.id) ?? group
        }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                SheetHeader(title: existingGroup == nil ? "New Group" : "Edit Group", onClose: {
                    dismiss()
                })

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionLabel(title: "Name")
                    TextField("Lisbon trip, Flat 4B…", text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.next)
                        .focused($focus, equals: .name)
                        .onSubmit {
                            focus = .newPerson
                        }
                        .insetField()
                        .accessibilityLabel("Group name")
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionLabel(title: "Type")
                    categoryGrid
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    SectionLabel(title: "People")
                    peopleCard
                }

                Button(action: save) {
                    Label(existingGroup == nil ? "Create Group" : "Save Changes", systemImage: "checkmark")
                }
                .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
                .disabled(trimmedName.isEmpty)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.vertical, Theme.Spacing.xl)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedScreen()
        .claySheet()
        .onAppear {
            if existingGroup == nil {
                focus = .name
            }
        }
        .clayDialog($dialog)
    }

    // MARK: - Category

    private var categoryGrid: some View {
        FlowLayout {
            ForEach(GroupCategory.allCases) { option in
                Button(action: {
                    withAnimation(Theme.Motion.standard) {
                        category = option
                    }
                }, label: {
                    Label(option.title, systemImage: option.symbol)
                })
                .buttonStyle(ClayChipStyle(isSelected: category == option))
                .accessibilityAddTraits(category == option ? [.isSelected] : [])
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    // MARK: - People

    private var peopleCard: some View {
        VStack(spacing: Theme.Spacing.m) {
            personRow(store.me, removable: false)
            ForEach(members) { person in
                personRow(person, removable: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            HStack(spacing: Theme.Spacing.s) {
                TextField("Add a person", text: $newPersonName)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .focused($focus, equals: .newPerson)
                    .onSubmit {
                        addPerson()
                    }
                    .insetField()
                    .accessibilityLabel("New person's name")
                Button(action: addPerson) {
                    Image(systemName: "person.badge.plus")
                }
                .buttonStyle(NeumorphicIconButtonStyle(prominence: .accent))
                .disabled(trimmedNewPerson.isEmpty)
                .accessibilityLabel("Add person")
            }
        }
        .padding(Theme.Spacing.l)
        .clayPlate()
    }

    private func personRow(_ person: Person, removable: Bool) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            AvatarView(person: person, size: 40)
            Text(person.isMe ? "\(person.name) (you)" : person.name)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.text)
            Spacer()
            if removable {
                Button(action: {
                    askToRemove(person)
                }, label: {
                    Image(systemName: "minus")
                })
                .buttonStyle(NeumorphicIconButtonStyle(prominence: .destructive))
                .accessibilityLabel("Remove \(person.name)")
            }
        }
        .frame(minHeight: Theme.Size.tapTarget)
    }

    private var trimmedName: String {
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedNewPerson: String {
        return newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addPerson() {
        let personName = trimmedNewPerson
        guard !personName.isEmpty else {
            focus = nil
            return
        }
        let used = ([store.me] + members).map { person in person.colorIndex }
        let colorIndex = (0..<Theme.pastels.count).first { index in !used.contains(index) }
            ?? (members.count + 1) % Theme.pastels.count
        withAnimation(Theme.Motion.standard) {
            members.append(Person(id: UUID(), name: personName, colorIndex: colorIndex))
        }
        newPersonName = ""
        focus = .newPerson
        Haptics.soft()
    }

    private func askToRemove(_ person: Person) {
        guard let group = existingGroup else {
            members.removeAll { member in member.id == person.id }
            return
        }
        let hasPayments = group.settlements.contains { settlement in
            settlement.from == person.id || settlement.to == person.id
        }
        if hasPayments {
            dialog = ClayDialog(title: "Can't remove \(person.name) yet",
                                message: "\(person.name) has recorded payments in this group. Undo them in Settle Up first.",
                                actions: [], cancelTitle: "OK")
        } else if store.isReferenced(person.id, in: group.id) {
            dialog = ClayDialog(
                title: "Remove \(person.name)?",
                message: "\(person.name) is on receipts in this group. Items they shared go back to everyone, and receipts they paid move to you.",
                actions: [
                    ClayDialog.Action(title: "Remove \(person.name)", symbol: "person.badge.minus", kind: .destructive) {
                        withAnimation(Theme.Motion.standard) {
                            members.removeAll { member in member.id == person.id }
                        }
                    },
                ]
            )
        } else {
            withAnimation(Theme.Motion.standard) {
                members.removeAll { member in member.id == person.id }
            }
        }
    }

    private func save() {
        let people = [store.me] + members
        if var group = existingGroup {
            group.name = trimmedName
            group.category = category
            group.members = people
            store.save(group)
        } else {
            store.save(SplitGroup(name: trimmedName, category: category, members: people))
        }
        Haptics.success()
        dismiss()
    }
}
