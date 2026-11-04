import SwiftUI
import UIKit

// MARK: - Lists of clay cards

extension View {
    /// A List row that shows only its clay card: no separator, clear background,
    /// screen-side margins and room for the card's shadow.
    func clayRow(top: CGFloat = Theme.Spacing.s, bottom: CGFloat = Theme.Spacing.s) -> some View {
        self
            .listRowInsets(EdgeInsets(top: top, leading: Theme.Spacing.screen,
                                      bottom: bottom, trailing: Theme.Spacing.screen))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// A plain List on the theme background (List gives us swipe actions).
    func clayList() -> some View {
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .background(Theme.Colors.background.ignoresSafeArea())
    }

    /// Keeps the last rows of a tab's first screen clear of the floating tab bar.
    func tabBarClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: Theme.Size.tabBarHeight + Theme.Spacing.xl)
        }
    }
}

/// A screen's large title with an optional subtitle and trailing buttons.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    private let trailing: Trailing

    init(title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Fonts.largeTitle)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(Theme.Fonts.subheadline)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, Theme.Spacing.s)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() })
    }
}

/// A round clay label for Menus (which can't take our button styles).
struct ClayIconLabel: View {
    let symbol: String
    var size: CGFloat = Theme.Size.tapTarget

    var body: some View {
        Image(systemName: symbol)
            .font(Theme.Fonts.headline)
            .foregroundStyle(Theme.Colors.text)
            .frame(width: size, height: size)
            .background {
                ClayBackground(shape: Circle(), style: .raised, elevation: Theme.Elevations.control)
            }
            .contentShape(Circle())
    }
}

/// The big green "+" that floats at the bottom right.
struct FloatingAddButton: View {
    let accessibilityName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
        }
        .buttonStyle(NeumorphicIconButtonStyle(prominence: .accent, size: 64))
        .accessibilityLabel(accessibilityName)
    }
}

// MARK: - Money and balances

/// "You're owed $12.00", "You owe $8.00" or "Settled up", always with an icon.
struct BalanceChip: View {
    /// My balance in cents: positive means others owe me.
    let cents: Int

    var body: some View {
        if cents > 0 {
            StatusChip(title: "You're owed \(Money.string(Money.fromCents(cents)))",
                       symbol: "arrow.down.left.circle.fill", tint: Theme.Colors.accentInk)
        } else if cents < 0 {
            StatusChip(title: "You owe \(Money.string(Money.fromCents(-cents)))",
                       symbol: "arrow.up.right.circle.fill", tint: Theme.Colors.warning)
        } else {
            StatusChip(title: "Settled up", symbol: "checkmark.circle.fill", tint: Theme.Colors.secondaryText)
        }
    }
}

/// A label + value row for amounts (subtotal, tax, tip…).
struct AmountRow: View {
    let title: String
    let amount: Decimal
    var emphasized: Bool = false

    var body: some View {
        HStack {
            Text(title)
                .font(emphasized ? Theme.Fonts.headline : Theme.Fonts.callout)
                .foregroundStyle(emphasized ? Theme.Colors.text : Theme.Colors.secondaryText)
            Spacer()
            Text(Money.string(amount))
                .font(emphasized ? Theme.Fonts.headline.monospacedDigit() : Theme.Fonts.money)
                .foregroundStyle(Theme.Colors.text)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Dates

enum DateText {
    /// "Nov 3", or "Nov 3, 2025" outside this year.
    static func short(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, equalTo: Date(), toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    /// "Monday, Nov 3, 2026"
    static func long(_ date: Date) -> String {
        return date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
    }
}

// MARK: - Toast

/// A short message that floats in and fades away ("Copied", "Saved to Photos").
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let message = message {
                Label(message, systemImage: "checkmark.circle.fill")
                    .font(Theme.Fonts.subheadline.weight(.bold))
                    .foregroundStyle(Theme.Colors.text)
                    .padding(.horizontal, Theme.Spacing.l)
                    .frame(minHeight: Theme.Size.compactButtonHeight)
                    .clayRaised(cornerRadius: 22, elevation: Theme.Elevations.floating)
                    .padding(.top, Theme.Spacing.s)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .task(id: message) {
                        UIAccessibility.post(notification: .announcement, argument: message)
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        withAnimation(Theme.Motion.standard) {
                            self.message = nil
                        }
                    }
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.bouncy, value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View {
        modifier(ToastModifier(message: message))
    }
}

// MARK: - Sharing

/// A file to share with the system share sheet.
struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

/// The system share sheet, for files made on demand (CSV, scan exports).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
    }
}

// MARK: - Sheets

extension View {
    /// The theme's look for bottom sheets: background, rounded top and a grabber.
    func claySheet() -> some View {
        self
            .presentationBackground(Theme.Colors.background)
            .presentationCornerRadius(Theme.Radius.card)
            .presentationDragIndicator(.visible)
    }
}

/// A sheet's title row with a close button.
struct SheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.Fonts.title)
                .foregroundStyle(Theme.Colors.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(NeumorphicIconButtonStyle())
            .accessibilityLabel("Close")
        }
    }
}
