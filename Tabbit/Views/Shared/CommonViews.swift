import SwiftUI
import UIKit

// MARK: - Screen headers

extension View {
    /// Keeps the last rows of a tab's first screen clear of the floating tab bar.
    func tabBarClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: Theme.Size.tabBarHeight + Theme.Spacing.xl)
        }
    }
}

/// A tab's large title with an optional subtitle and trailing buttons.
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

/// The top bar of a pushed screen: a clay back button, the title, and clay buttons
/// on the right. Replaces the system navigation bar (and its glass buttons).
struct NavHeader<Trailing: View>: View {
    let title: String
    var titleInset: CGFloat = 64
    let onBack: () -> Void
    let trailing: Trailing

    var body: some View {
        ZStack {
            Text(title)
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Colors.text)
                .lineLimit(1)
                .padding(.horizontal, titleInset)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: Theme.Spacing.s) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .accessibilityLabel("Back")
                Spacer(minLength: 0)
                trailing
            }
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.vertical, Theme.Spacing.s)
        .frame(minHeight: Theme.Size.headerHeight)
        .background(Theme.Colors.background.ignoresSafeArea(edges: .top))
    }
}

private struct ClayNavigationModifier<Trailing: View>: ViewModifier {
    let title: String
    let titleInset: CGFloat
    let trailing: Trailing

    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                NavHeader(title: title, titleInset: titleInset, onBack: {
                    dismiss()
                }, trailing: trailing)
            }
    }
}

extension View {
    /// Gives a pushed screen the clay header (back button, title, trailing buttons).
    func clayNavigation<Trailing: View>(_ title: String, titleInset: CGFloat = 64,
                                        @ViewBuilder trailing: () -> Trailing) -> some View {
        modifier(ClayNavigationModifier(title: title, titleInset: titleInset, trailing: trailing()))
    }

    func clayNavigation(_ title: String) -> some View {
        clayNavigation(title, trailing: { EmptyView() })
    }
}

/// Keeps the edge swipe-back gesture working with the system navigation bar hidden.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1
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

/// "You're owed $12.00" (mint), "You owe $8.00" (amber) or "Settled up" (grey), always with an icon.
struct BalancePill: View {
    /// My balance in cents: positive means others owe me.
    let cents: Int

    var body: some View {
        if cents > 0 {
            StatusPill(title: "You're owed \(Money.string(Money.fromCents(cents)))",
                       symbol: "arrow.down.left", tone: .positive)
        } else if cents < 0 {
            StatusPill(title: "You owe \(Money.string(Money.fromCents(-cents)))",
                       symbol: "arrow.up.right", tone: .caution)
        } else {
            StatusPill(title: "Settled up", symbol: "checkmark", tone: .neutral)
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

/// Pick a day: a wheel in a clay sheet, instead of the system's compact date button.
struct DatePickerSheet: View {
    @Binding var date: Date

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            SheetHeader(title: "Date", onClose: {
                dismiss()
            })
            DatePicker("Date", selection: $date, displayedComponents: .date)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            Button(action: {
                dismiss()
            }, label: {
                Label("Done", systemImage: "checkmark")
            })
            .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .themedScreen()
        .presentationDetents([.height(440), .large])
        .claySheet()
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
                HStack(spacing: Theme.Spacing.s) {
                    IconBadge(symbol: "checkmark", tone: .positive, size: 26)
                    Text(message)
                        .font(Theme.Fonts.subheadline.weight(.bold))
                        .foregroundStyle(Theme.Colors.text)
                }
                .padding(.leading, Theme.Spacing.s)
                .padding(.trailing, Theme.Spacing.l)
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

/// A sheet's title row with a clay close button.
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

// MARK: - Dialogs

/// A question or a set of choices, shown as a clay bottom sheet instead of the
/// system's alert or action sheet.
struct ClayDialog: Identifiable {
    struct Action: Identifiable {
        enum Kind {
            case primary
            case normal
            case destructive
        }

        let id = UUID()
        let title: String
        var symbol: String?
        var kind: Kind = .normal
        let handler: () -> Void
    }

    let id = UUID()
    let title: String
    var message: String?
    let actions: [Action]
    var cancelTitle: String = "Cancel"
}

struct ClayDialogView: View {
    let dialog: ClayDialog

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text(dialog.title)
                .font(Theme.Fonts.title3)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let message = dialog.message {
                Text(message)
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: Theme.Spacing.m) {
                ForEach(dialog.actions) { action in
                    Button(action: {
                        dismiss()
                        // Run once the sheet has gone, so the action can present something else.
                        Task {
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            action.handler()
                        }
                    }, label: {
                        if let symbol = action.symbol {
                            Label(action.title, systemImage: symbol)
                        } else {
                            Text(action.title)
                        }
                    })
                    .buttonStyle(NeumorphicButtonStyle(prominence: prominence(of: action)))
                }
                Button(action: {
                    dismiss()
                }, label: {
                    Text(dialog.cancelTitle)
                })
                .buttonStyle(NeumorphicButtonStyle(prominence: .secondary))
            }
            .padding(.top, Theme.Spacing.s)
        }
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .themedScreen()
        .presentationDetents([.height(height), .large])
        .claySheet()
    }

    private var height: CGFloat {
        let messageHeight: CGFloat = dialog.message == nil ? 0 : 64
        return 120 + messageHeight + CGFloat(dialog.actions.count + 1) * 68
    }

    private func prominence(of action: ClayDialog.Action) -> NeumorphicButtonStyle.Prominence {
        switch action.kind {
        case .primary: return .primary
        case .normal: return .secondary
        case .destructive: return .destructive
        }
    }
}

extension View {
    /// Shows a ClayDialog as a bottom sheet while `dialog` is set.
    func clayDialog(_ dialog: Binding<ClayDialog?>) -> some View {
        sheet(item: dialog) { item in
            ClayDialogView(dialog: item)
        }
    }
}
