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

/// The Groups tab: search, what everyone owes overall, and a card per group.
struct GroupsView: View {
    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var router: AppRouter

    @State private var query = ""
    @State private var editing: GroupEditorTarget?
    @State private var dialog: ClayDialog?
    @State private var openRow: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.l) {
                ScreenHeader(title: "Groups", subtitle: subtitle) {
                    Button(action: {
                        editing = .new
                    }, label: {
                        Image(systemName: "plus")
                    })
                    .buttonStyle(NeumorphicIconButtonStyle())
                    .accessibilityLabel("New group")
                }

                if store.groups.isEmpty {
                    emptyState
                } else {
                    ClaySearchField(text: $query, prompt: "Search groups or people")
                    if query.isEmpty {
                        OverviewCard(owedToMeCents: totals.owedToMe, iOweCents: totals.iOwe)
                    }
                    if filtered.isEmpty {
                        EmptyStateView(symbol: "magnifyingglass", title: "No matches",
                                       message: "No group or person matches “\(query)”.")
                    }
                    ForEach(filtered) { group in
                        row(group)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .scrollDismissesKeyboard(.immediately)
        .themedScreen()
        .toolbar(.hidden, for: .navigationBar)
        .tabBarClearance()
        .sheet(item: $editing) { target in
            GroupEditorView(target: target)
                .environmentObject(store)
        }
        .clayDialog($dialog)
        .task {
            #if DEBUG
            if DemoMode.screen == "dialog", let first = store.groups.first {
                try? await Task.sleep(nanoseconds: 600_000_000)
                askToDelete(first)
            }
            #endif
        }
    }

    private func row(_ group: SplitGroup) -> some View {
        SwipeRow(id: group.id, openRow: $openRow, actions: [
            SwipeAction(id: "edit", symbol: "pencil", label: "Edit", action: {
                editing = .edit(group)
            }),
            SwipeAction(id: "delete", symbol: "trash", label: "Delete", isDestructive: true, action: {
                askToDelete(group)
            }),
        ]) {
            Button(action: {
                if openRow != nil {
                    withAnimation(Theme.Motion.standard) {
                        openRow = nil
                    }
                } else {
                    router.push(.group(group.id))
                }
            }, label: {
                GroupCard(group: group,
                          total: store.total(of: group),
                          receiptCount: store.receipts(in: group.id).count,
                          myBalanceCents: store.balances(in: group)[Person.meID] ?? 0)
            })
            .buttonStyle(NeumorphicCardButtonStyle())
        }
    }

    private func askToDelete(_ group: SplitGroup) {
        dialog = ClayDialog(
            title: "Delete “\(group.displayName)”?",
            message: "The group and its balances are removed from this iPhone.",
            actions: [
                ClayDialog.Action(title: "Delete Group and Receipts", symbol: "trash", kind: .destructive) {
                    withAnimation(Theme.Motion.standard) {
                        store.deleteGroup(group.id, keepReceipts: false)
                    }
                },
                ClayDialog.Action(title: "Keep Receipts in My Receipts", symbol: "tray.and.arrow.down") {
                    withAnimation(Theme.Motion.standard) {
                        store.deleteGroup(group.id, keepReceipts: true)
                    }
                },
            ]
        )
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
}

/// "You're owed" and "You owe", across all groups. Information, so flat plates.
struct OverviewCard: View {
    let owedToMeCents: Int
    let iOweCents: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            figure(title: "You're owed", cents: owedToMeCents, symbol: "arrow.down.left", tone: .positive)
            figure(title: "You owe", cents: iOweCents, symbol: "arrow.up.right", tone: .caution)
        }
    }

    private func figure(title: String, cents: Int, symbol: String, tone: StatusTone) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                IconBadge(symbol: symbol, tone: cents > 0 ? tone : .neutral, size: 26)
                Text(title)
                    .font(Theme.Fonts.subheadline)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(1)
            }
            MoneyText(amount: Money.fromCents(cents), font: Theme.Fonts.mediumMoney)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clayPlate(cornerRadius: Theme.Radius.tile)
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
                CategoryBadge(symbol: group.category.symbol, colorIndex: group.category.colorIndex, size: 48)
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
                BalancePill(cents: myBalanceCents)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var countsText: String {
        let receipts = receiptCount == 1 ? "1 receipt" : "\(receiptCount) receipts"
        let people = group.members.count == 1 ? "1 person" : "\(group.members.count) people"
        return "\(receipts) · \(people)"
    }
}
