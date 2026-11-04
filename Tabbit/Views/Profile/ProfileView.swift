import Charts
import SwiftUI

/// The Profile tab: me, this month's spending, where it went, the last six
/// months, and what I'm owed or owe across groups.
struct ProfileView: View {
    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var router: AppRouter

    @State private var editingProfile = false

    var body: some View {
        let stats = SpendingStats.compute(receipts: store.receipts, groups: store.groups)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                MonthCard(stats: stats)
                CategoryRingCard(stats: stats)
                MonthsChartCard(stats: stats)
                balancesRow(stats)
                quickStats(stats)
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .themedScreen()
        .toolbar(.hidden, for: .navigationBar)
        .tabBarClearance()
        .sheet(isPresented: $editingProfile) {
            ProfileEditSheet()
                .environmentObject(store)
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button(action: {
                editingProfile = true
            }, label: {
                HStack(spacing: Theme.Spacing.m) {
                    AvatarView(person: store.me, size: 56)
                        .padding(Theme.Spacing.xs)
                        .clayRaised(cornerRadius: 32, elevation: Theme.Elevations.control)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(store.me.name)
                            .font(Theme.Fonts.title)
                            .foregroundStyle(Theme.Colors.text)
                            .lineLimit(1)
                        Label("Edit profile", systemImage: "pencil")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.accentInk)
                    }
                }
            })
            .buttonStyle(.plain)
            .accessibilityLabel("\(store.me.name), edit profile")
            Spacer()
            Button(action: {
                router.push(.settings)
            }, label: {
                Image(systemName: "gearshape.fill")
            })
            .buttonStyle(NeumorphicIconButtonStyle())
            .accessibilityLabel("Settings")
        }
        .padding(.top, Theme.Spacing.s)
    }

    private func balancesRow(_ stats: SpendingStats) -> some View {
        OverviewCard(owedToMeCents: stats.owedToMeCents, iOweCents: stats.iOweCents)
    }

    private func quickStats(_ stats: SpendingStats) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            statTile(title: "Receipts", value: "\(stats.receiptCount)", symbol: "doc.text.fill")
            statTile(title: "Average", value: Money.string(Money.fromCents(stats.averageCents)),
                     symbol: "divide.circle.fill")
            statTile(title: "Groups", value: "\(store.groups.count)", symbol: "person.3.fill")
        }
    }

    private func statTile(title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Image(systemName: symbol)
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Colors.accentInk)
                .accessibilityHidden(true)
            Text(value)
                .font(Theme.Fonts.headline.monospacedDigit())
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .clayRaised(cornerRadius: Theme.Radius.tile)
        .accessibilityElement(children: .combine)
    }
}

/// "Spent this month": my share, compared with last month.
struct MonthCard: View {
    let stats: SpendingStats

    var body: some View {
        NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Spent this month")
                    .font(Theme.Fonts.subheadline)
                    .foregroundStyle(Theme.Colors.secondaryText)
                MoneyText(amount: Money.fromCents(stats.thisMonthCents), font: Theme.Fonts.bigMoney)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                change
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var change: some View {
        if let change = stats.monthChange {
            let percent = Int((abs(change) * 100).rounded())
            if percent == 0 {
                StatusChip(title: "Same as last month", symbol: "equal.circle.fill", tint: Theme.Colors.secondaryText)
            } else if change > 0 {
                StatusChip(title: "\(percent)% more than last month", symbol: "arrow.up.right.circle.fill",
                           tint: Theme.Colors.warning)
            } else {
                StatusChip(title: "\(percent)% less than last month", symbol: "arrow.down.right.circle.fill",
                           tint: Theme.Colors.accentInk)
            }
        } else {
            Text("Your share of group receipts, plus your own.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
        }
    }
}

/// A ring of this month's spending by category, with a legend.
struct CategoryRingCard: View {
    let stats: SpendingStats

    var body: some View {
        NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                SectionLabel(title: "Where it went")
                HStack(alignment: .center, spacing: Theme.Spacing.xl) {
                    ring
                        .frame(width: 140, height: 140)
                    legend
                }
            }
        }
    }

    @ViewBuilder
    private var ring: some View {
        if stats.categories.isEmpty {
            Circle()
                .stroke(Theme.Colors.inset, lineWidth: 22)
                .padding(11)
                .overlay {
                    Text("No spending\nyet")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
        } else {
            Chart(stats.categories) { total in
                SectorMark(angle: .value("Amount", total.cents), innerRadius: .ratio(0.64), angularInset: 2)
                    .cornerRadius(5)
                    .foregroundStyle(Theme.pastel(total.category.colorIndex))
            }
            .chartLegend(.hidden)
            .overlay {
                VStack(spacing: 0) {
                    Text(Money.wholeString(Money.fromCents(stats.thisMonthCents)))
                        .font(Theme.Fonts.headline.monospacedDigit())
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(stats.categories.count == 1 ? "1 category" : "\(stats.categories.count) categories")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .padding(Theme.Spacing.xl)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
        }
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if stats.categories.isEmpty {
                Text("Add receipts to see your spending by category.")
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            ForEach(stats.categories.prefix(5)) { total in
                HStack(spacing: Theme.Spacing.s) {
                    Circle()
                        .fill(Theme.pastel(total.category.colorIndex))
                        .frame(width: 12, height: 12)
                        .accessibilityHidden(true)
                    Text(total.category.title)
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.text)
                        .lineLimit(1)
                    Spacer(minLength: Theme.Spacing.xs)
                    Text(percentText(total.cents))
                        .font(Theme.Fonts.caption.monospacedDigit())
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
    }

    private func percentText(_ cents: Int) -> String {
        guard stats.thisMonthCents > 0 else {
            return ""
        }
        let percent = Int((Double(cents) / Double(stats.thisMonthCents) * 100).rounded())
        return "\(percent)%"
    }

    private var accessibilitySummary: String {
        let parts = stats.categories.map { total in
            "\(total.category.title) \(Money.string(total.amount))"
        }
        return "Spending by category: " + parts.joined(separator: ", ")
    }
}

/// Bars for the last six months; this month in green.
struct MonthsChartCard: View {
    let stats: SpendingStats

    var body: some View {
        NeumorphicCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                SectionLabel(title: "Last 6 months")
                Chart(stats.months) { month in
                    BarMark(x: .value("Month", label(month.month)),
                            y: .value("Spent", Double(month.cents) / 100),
                            width: .ratio(0.55))
                        .cornerRadius(8)
                        .foregroundStyle(style(for: month))
                }
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                }
                .frame(height: 150)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilitySummary)
            }
        }
    }

    private func label(_ month: Date) -> String {
        return month.formatted(.dateTime.month(.abbreviated))
    }

    /// Solid colors: Swift Charts stretches gradients over the whole plot, and
    /// translucent fills turn muddy on the dark card.
    private func style(for month: SpendingStats.MonthTotal) -> Color {
        if month.id == stats.months.last?.id {
            return Theme.Colors.chartHighlight
        }
        return Theme.Colors.chartMuted
    }

    private var accessibilitySummary: String {
        let parts = stats.months.map { month in
            "\(label(month.month)) \(Money.wholeString(month.amount))"
        }
        return "Spending in the last six months: " + parts.joined(separator: ", ")
    }
}

/// Edit my name and avatar color.
struct ProfileEditSheet: View {
    @EnvironmentObject private var store: TabbitStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var colorIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SheetHeader(title: "Your profile", onClose: {
                dismiss()
            })
            HStack {
                Spacer()
                AvatarView(person: Person(id: Person.meID, name: name.isEmpty ? "Me" : name, colorIndex: colorIndex),
                           size: 88)
                    .padding(Theme.Spacing.s)
                    .clayRaised(cornerRadius: 52, elevation: Theme.Elevations.control)
                Spacer()
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionLabel(title: "Name")
                TextField("Your name", text: $name)
                    .textInputAutocapitalization(.words)
                    .insetField()
                    .accessibilityLabel("Your name")
                Text("Shown to friends when you share a Settle Up summary.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                SectionLabel(title: "Color")
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(Theme.pastels.indices, id: \.self) { index in
                        Button(action: {
                            colorIndex = index
                        }, label: {
                            Circle()
                                .fill(Theme.pastel(index))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if index == colorIndex {
                                        Image(systemName: "checkmark")
                                            .font(Theme.Fonts.caption.weight(.heavy))
                                            .foregroundStyle(Theme.onPastel.color)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: Theme.Size.tapTarget)
                                .contentShape(Rectangle())
                        })
                        .buttonStyle(.plain)
                        .accessibilityLabel("Color \(index + 1)")
                        .accessibilityAddTraits(index == colorIndex ? [.isSelected] : [])
                    }
                }
            }
            Button(action: {
                store.updateMe(name: name, colorIndex: colorIndex)
                Haptics.success()
                dismiss()
            }, label: {
                Label("Save", systemImage: "checkmark")
            })
            .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.xl)
        .themedScreen()
        .presentationDetents([.large])
        .claySheet()
        .onAppear {
            name = store.me.name == "Me" ? "" : store.me.name
            colorIndex = store.me.colorIndex
        }
    }
}
