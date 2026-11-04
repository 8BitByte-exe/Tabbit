import SwiftUI

// MARK: - Surfaces

/// A blurred stroke clipped to the inside of `shape`. It shows on the edge
/// *opposite* to `offset`: an offset toward the bottom-right lights or shades the
/// top-left inner edge. This is how inner shadows are drawn on iOS 16.
struct InnerEdge<S: Shape>: View {
    let shape: S
    let color: Color
    let offset: CGFloat

    var body: some View {
        shape
            .stroke(color, lineWidth: Theme.Inner.lineWidth)
            .blur(radius: Theme.Inner.blur)
            .offset(x: offset, y: offset)
            .mask { shape }
    }
}

/// The clay surface behind a card, button or field.
///
/// - `.raised`: puffy gradient, a thin highlight on the top-left inner edge, a soft
///   shade on the bottom-right inner edge, and two drop shadows (light to the
///   top-left, dark to the bottom-right).
/// - `.inset`: pressed into the background, with the inner shade on the top-left
///   and the highlight on the bottom-right.
///
/// With Reduce Transparency the blurred edges are dropped, and with Reduce
/// Transparency or Increase Contrast a visible outline is added, so edges never
/// depend on soft shadows alone.
struct ClayBackground<S: Shape>: View {
    enum Style {
        case raised
        case inset
    }

    let shape: S
    var style: Style = .raised
    var raisedFill: LinearGradient = Theme.Gradients.surface
    var insetFill: Color = Theme.Colors.inset
    var elevation: Theme.Elevation = Theme.Elevations.card

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        if style == .raised {
            raised
        } else {
            inset
        }
    }

    private var showsOutline: Bool {
        return reduceTransparency || contrast == .increased
    }

    private var raised: some View {
        ZStack {
            shape.fill(raisedFill)
            if !reduceTransparency {
                InnerEdge(shape: shape, color: Theme.Colors.highlight, offset: Theme.Inner.offset)
                InnerEdge(shape: shape, color: Theme.Colors.shade, offset: -Theme.Inner.offset)
            }
            if showsOutline {
                shape.stroke(Theme.Colors.outline, lineWidth: 1)
            }
        }
        .compositingGroup()
        .shadow(color: Theme.Colors.shade, radius: elevation.radius, x: elevation.offset, y: elevation.offset)
        .shadow(color: Theme.Colors.highlight, radius: elevation.radius, x: -elevation.offset, y: -elevation.offset)
    }

    private var inset: some View {
        ZStack {
            shape.fill(insetFill)
            if !reduceTransparency {
                InnerEdge(shape: shape, color: Theme.Colors.shade, offset: Theme.Inner.offset)
                InnerEdge(shape: shape, color: Theme.Colors.highlight, offset: -Theme.Inner.offset)
            }
            if showsOutline {
                shape.stroke(Theme.Colors.outline, lineWidth: 1)
            }
        }
    }
}

extension View {
    /// A raised clay surface behind this view.
    func clayRaised(cornerRadius: CGFloat = Theme.Radius.card,
                    elevation: Theme.Elevation = Theme.Elevations.card) -> some View {
        background {
            ClayBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                           style: .raised, elevation: elevation)
        }
    }

    /// A pressed-in clay well behind this view.
    func clayInset(cornerRadius: CGFloat = Theme.Radius.field) -> some View {
        background {
            ClayBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), style: .inset)
        }
    }

    /// The theme's screen background, edge to edge.
    func themedScreen() -> some View {
        background(Theme.Colors.background.ignoresSafeArea())
    }
}

// MARK: - Cards

/// A raised card with generous padding.
struct NeumorphicCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = Theme.Spacing.xl, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clayRaised()
    }
}

/// The inset variant: content sits in a well pressed into the background.
struct NeumorphicInsetCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = Theme.Spacing.l, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clayInset(cornerRadius: Theme.Radius.card)
    }
}

// MARK: - Buttons

/// Chunky capsule buttons. Primary = coral with dark text; secondary = surface color.
/// Pressed: switches to the inset look, scales to 0.97, soft haptic. Reduce Motion
/// turns off the scale animation.
struct NeumorphicButtonStyle: ButtonStyle {
    enum Prominence {
        case primary
        case secondary
    }

    var prominence: Prominence = .secondary
    var fullWidth: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        NeumorphicButtonBody(configuration: configuration, prominence: prominence, fullWidth: fullWidth)
    }
}

private struct NeumorphicButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominence: NeumorphicButtonStyle.Prominence
    let fullWidth: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed
        let isPrimary = prominence == .primary
        return configuration.label
            .font(Theme.Fonts.button)
            .foregroundColor(isPrimary ? Theme.Colors.onAccent : Theme.Colors.text)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.m)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Theme.Size.buttonHeight)
            .background {
                ClayBackground(
                    shape: Capsule(style: .continuous),
                    style: pressed ? .inset : .raised,
                    raisedFill: isPrimary ? Theme.Gradients.accent : Theme.Gradients.surface,
                    insetFill: isPrimary ? Theme.Colors.accentBottom : Theme.Colors.inset,
                    elevation: Theme.Elevations.control
                )
            }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(pressed && !reduceMotion ? Theme.Motion.pressedScale : 1)
            .animation(reduceMotion ? nil : Theme.Motion.press, value: pressed)
            .opacity(isEnabled ? 1 : 0.55)
            .onChange(of: pressed) { isPressed in
                if isPressed {
                    Haptics.soft()
                }
            }
    }
}

/// Round 48pt icon buttons (settings, delete, add).
struct NeumorphicIconButtonStyle: ButtonStyle {
    var tint: Color = Theme.Colors.text

    func makeBody(configuration: Configuration) -> some View {
        NeumorphicIconButtonBody(configuration: configuration, tint: tint)
    }
}

private struct NeumorphicIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(Theme.Fonts.headline)
            .foregroundColor(tint)
            .frame(minWidth: Theme.Size.tapTarget, minHeight: Theme.Size.tapTarget)
            .background {
                ClayBackground(shape: Circle(), style: pressed ? .inset : .raised,
                               elevation: Theme.Elevations.control)
            }
            .contentShape(Circle())
            .scaleEffect(pressed && !reduceMotion ? Theme.Motion.pressedScale : 1)
            .animation(reduceMotion ? nil : Theme.Motion.press, value: pressed)
            .onChange(of: pressed) { isPressed in
                if isPressed {
                    Haptics.soft()
                }
            }
    }
}

/// Makes a whole card tappable (used for receipt cards on the home screen).
struct NeumorphicCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NeumorphicCardButtonBody(configuration: configuration)
    }
}

private struct NeumorphicCardButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        return configuration.label
            .padding(Theme.Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ClayBackground(shape: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous),
                               style: pressed ? .inset : .raised)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .scaleEffect(pressed && !reduceMotion ? Theme.Motion.pressedScale : 1)
            .animation(reduceMotion ? nil : Theme.Motion.press, value: pressed)
            .onChange(of: pressed) { isPressed in
                if isPressed {
                    Haptics.soft()
                }
            }
    }
}

// MARK: - Fields and labels

extension View {
    /// An inset text-field well: 20pt corners, at least 48pt tall.
    func insetField() -> some View {
        self
            .font(Theme.Fonts.body)
            .foregroundColor(Theme.Colors.text)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(minHeight: Theme.Size.fieldHeight)
            .clayInset(cornerRadius: Theme.Radius.field)
    }
}

/// A small section title above or inside a card.
struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.Fonts.caption)
            .foregroundColor(Theme.Colors.secondaryText)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Whether a receipt's numbers add up, as an icon + label + color (never color alone).
struct StatusChip: View {
    enum Status {
        case addsUp
        case needsCheck
        case unknown
    }

    let status: Status

    var body: some View {
        Label {
            Text(title)
                .font(Theme.Fonts.caption)
        } icon: {
            Image(systemName: symbol)
                .font(Theme.Fonts.caption)
        }
        .foregroundColor(color)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .clayInset(cornerRadius: Theme.Radius.small)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch status {
        case .addsUp: return "Adds up"
        case .needsCheck: return "Check totals"
        case .unknown: return "Not checked"
        }
    }

    private var symbol: String {
        switch status {
        case .addsUp: return "checkmark.circle.fill"
        case .needsCheck: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var color: Color {
        switch status {
        case .addsUp: return Theme.Colors.success
        case .needsCheck: return Theme.Colors.warning
        case .unknown: return Theme.Colors.secondaryText
        }
    }
}

extension StatusChip.Status {
    /// Status from the receipt's arithmetic checks.
    init(receipt: Receipt) {
        let checks = ReceiptValidator.checks(for: receipt)
        if checks.isEmpty {
            self = .unknown
        } else if checks.allSatisfy({ check in check.passed }) {
            self = .addsUp
        } else {
            self = .needsCheck
        }
    }
}
