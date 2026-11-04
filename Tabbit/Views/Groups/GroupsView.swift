import SwiftUI

/// Opens the group editor for a new group or an existing one.
enum GroupEditorTarget: Identifiable {
    case new
    case edit(SplitGroup)

    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let group): return group.id.uuidString
        }
    }
}

/// The Groups tab: what everyone owes overall, search, and a card per group.
struct GroupsView: View {
    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var router: AppRouter

    @State private var query = ""
    @State private var editing: GroupEditorTarget?
    @State private var deleting: SplitGroup?

    var body: some View {
        List {
            ScreenHeader(title: "Groups", subtitle: subtitle) {
                Button(action: {
                    editing = .new
                }, label: {
                    Image(systemName: "plus")
                })
                .buttonStyle(NeumorphicIconButtonStyle())
                .accessibilityLabel("New group")
            }
            .clayRow(top: Theme.Spacing.l)

            if store.groups.isEmpty {
                emptyState
                    .clayRow()
            } else {
                OverviewCard(owedToMeCents: totals.owedToMe, iOweCents: totals.iOwe)
                    .clayRow()
                ClaySearchField(text: $query, prompt: "Search groups or people")
                    .clayRow(top: Theme.Spacing.m)

                if filtered.isEmpty {
                    EmptyStateView(symbol: "magnifyingglass", title: "No matches",
                                   message: "No group or person matches “\(query)”.")
                        .clayRow()
                }
                ForEach(filtered) { group in
                    groupRow(group)
                }
            }
        }
        .clayList()
        .toolbar(.hidden, for: .navigationBar)
        .tabBarClearance()
        .sheet(item: $editing) { target in
            GroupEditorView(target: target)
                .environmentObject(store)
        }
        .confirmationDialog("Delete this group?", isPresented: deletingBinding, titleVisibility: .visible,
                            presenting: deleting, actions: { group in
            Button("Delete Group and Receipts", role: .destructive) {
                store.deleteGroup(group.id, keepReceipts: false)
            }
            Button("Keep Receipts in My Receipts") {
                store.deleteGroup(group.id, keepReceipts: true)
            }
            Button("Cancel", role: .cancel) {
            }
        }, message: { group in
            Text("“\(group.displayName)” and its balances will be removed from this iPhone.")
        })
    }

    private func groupRow(_ group: SplitGroup) -> some View {
        Button(action: {
            router.push(.group(group.id))
        }, label: {
            GroupCard(group: group,
                      total: store.total(of: group),
                      receiptCount: store.receipts(in: group.id).count,
                      myBalanceCents: store.balances(in: group)[Person.meID] ?? 0)
        })
        .buttonStyle(NeumorphicCardButtonStyle())
        .clayRow()
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(action: {
                deleting = group
            }, label: {
                Label("Delete", systemImage: "trash")
            })
            .tint(Theme.Colors.swipeDelete)
            Button(action: {
                editing = .edit(group)
            }, label: {
                Label("Edit", systemImage: "pencil")
            })
            .tint(Theme.Colors.swipeEdit)
        }
        .accessibilityAction(named: "Edit") {
            editing = .edit(group)
        }
        .accessibilityAction(named: "Delete") {
            deleting = group
        }
    }

    private var subtitle: String {
        let count = store.groups.count
        if count == 0 {
            return "Split costs with the people you're with"
        }
        return count == 1 ? "1 group" : "\(count) groups"
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.l) {
            EmptyStateView(symbol: "person.3.fill", title: "No groups yet",
                           message: "Make a group for a trip, a dinner or your home, then add receipts and split them.")
            Button(action: {
                editing = .new
            }, label: {
                Label("New Group", systemImage: "plus")
            })
            .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
        }
        .padding(.top, Theme.Spacing.xl)
    }

    private var filtered: [SplitGroup] {
        let words = query.lowercased().split(separator: " ").map { word in String(word) }
        guard !words.isEmpty else {
            return store.groups
        }
        return store.groups.filter { group in
            let text = ([group.name, group.category.title] + group.members.map { person in person.name })
                .joined(separator: " ")
                .lowercased()
            return words.allSatisfy { word in text.contains(word) }
        }
    }

    private var totals: (owedToMe: Int, iOwe: Int) {
        var owedToMe = 0
        var iOwe = 0
        for group in store.groups {
            let mine = store.balances(in: group)[Person.meID] ?? 0
            if mine > 0 {
                owedToMe += mine
            } else {
                iOwe -= mine
            }
        }
        return (owedToMe: owedToMe, iOwe: iOwe)
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

/// "You're owed" and "You owe", across all groups.
struct OverviewCard: View {
    let owedToMeCents: Int
    let iOweCents: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            figure(title: "You're owed", cents: owedToMeCents, symbol: "arrow.down.left",
                   tint: Theme.Colors.accentInk)
            figure(title: "You owe", cents: iOweCents, symbol: "arrow.up.right", tint: Theme.Colors.warning)
        }
    }

    private func figure(title: String, cents: Int, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: symbol)
                    .font(Theme.Fonts.caption.weight(.heavy))
                    .foregroundStyle(tint)
            }
            .font(Theme.Fonts.subheadline)
            .foregroundStyle(Theme.Colors.secondaryText)
            MoneyText(amount: Money.fromCents(cents), font: Theme.Fonts.mediumMoney,
                      color: cents > 0 ? tint : Theme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clayRaised(cornerRadius: Theme.Radius.card)
        .accessibilityElement(children: .combine)
    }
}

/// A group in the list: badge, name, counts, people, total and my balance.
struct GroupCard: View {
    let group: SplitGroup
    let total: Decimal
    let receiptCount: Int
    let myBalanceCents: Int

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.m))
            layout {
                CategoryBadge(symbol: group.category.symbol, colorIndex: group.category.colorIndex, size: 52)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(group.displayName)
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(2)
                    Text(countsText)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: Theme.Spacing.s)
                }
                MoneyText(amount: total, font: Theme.Fonts.headline.monospacedDigit())
            }
            HStack {
                AvatarStack(people: group.members)
                Spacer(minLength: Theme.Spacing.s)
                BalanceChip(cents: myBalanceCents)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var countsText: String {
        let receipts = receiptCount == 1 ? "1 receipt" : "\(receiptCount) receipts"
        let people = group.members.count == 1 ? "1 person" : "\(group.members.count) people"
        return "\(group.category.title) · \(receipts) · \(people)"
    }
}
