import SwiftUI

// MARK: - Surfaces

/// A blurred stroke clipped to the inside of `shape`: an inner shadow on the
/// edge *opposite* to `offset`. Used only by inset wells (pressed look).
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

/// The clay surface behind a card, button or field. Matte, lit from the top-left.
///
/// - `.raised`: a subtle diagonal gradient, a crisp 1pt lit edge, and two soft
///   drop shadows (light to the top-left, dark to the bottom-right).
/// - `.accent`: the same, in mint-sage, with a green-tinted shadow so the color
///   stays clean (no grey shading on the color).
/// - `.inset` / `.accentInset`: pressed into the surface, with inner shadows.
///
/// Reduce Transparency drops the blurred inner shadows; Reduce Transparency or
/// Increase Contrast adds a visible outline, so edges never depend on shadows alone.
struct ClayBackground<S: Shape>: View {
    enum Style {
        case raised
        case accent
        case inset
        case accentInset
    }

    let shape: S
    var style: Style = .raised
    var elevation: Theme.Elevation = Theme.Elevations.card

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        switch style {
        case .raised:
            raised(fill: Theme.Gradients.surface, shade: Theme.Colors.shade)
        case .accent:
            raised(fill: Theme.Gradients.accent, shade: Theme.Colors.accentShade)
        case .inset:
            inset(fill: Theme.Colors.inset, shade: Theme.Colors.shade)
        case .accentInset:
            inset(fill: Theme.Colors.accentLow, shade: Theme.Colors.accentShade)
        }
    }

    private var showsOutline: Bool {
        return reduceTransparency || contrast == .increased
    }

    private func raised(fill: LinearGradient, shade: Color) -> some View {
        ZStack {
            shape.fill(fill)
            shape.stroke(Theme.Gradients.edge, lineWidth: 1)
            if showsOutline {
                shape.stroke(Theme.Colors.outline, lineWidth: 1)
            }
        }
        .compositingGroup()
        .shadow(color: shade, radius: elevation.radius, x: elevation.offset, y: elevation.offset)
        .shadow(color: Theme.Colors.highlight, radius: elevation.radius, x: -elevation.offset, y: -elevation.offset)
    }

    private func inset(fill: Color, shade: Color) -> some View {
        ZStack {
            shape.fill(fill)
            if !reduceTransparency {
                InnerEdge(shape: shape, color: shade, offset: Theme.Inner.offset)
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

    /// An inset text-field well.
    func insetField() -> some View {
        self
            .font(Theme.Fonts.body)
            .foregroundStyle(Theme.Colors.text)
            .tint(Theme.Colors.accentInk)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(minHeight: Theme.Size.fieldHeight)
            .clayInset(cornerRadius: Theme.Radius.field)
    }
}

// MARK: - Cards

/// A raised card with generous padding.
struct NeumorphicCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = Theme.Spacing.l + 4, @ViewBuilder content: () -> Content) {
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

/// The inset variant: content sits in a well pressed into the surface.
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
            .clayInset(cornerRadius: Theme.Radius.tile)
    }
}

// MARK: - Buttons

/// Chunky capsule buttons. Primary = mint-sage with dark text; secondary = surface;
/// destructive = surface with red text. Pressed: inset look, 0.97 scale, soft haptic.
struct NeumorphicButtonStyle: ButtonStyle {
    enum Prominence {
        case primary
        case secondary
        case destructive
    }

    var prominence: Prominence = .secondary
    var fullWidth: Bool = true
    var compact: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        NeumorphicButtonBody(configuration: configuration, prominence: prominence,
                             fullWidth: fullWidth, compact: compact)
    }
}

private struct NeumorphicButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominence: NeumorphicButtonStyle.Prominence
    let fullWidth: Bool
    let compact: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed
        let isPrimary = prominence == .primary
        let style: ClayBackground<Capsule>.Style = isPrimary
            ? (pressed ? .accentInset : .accent)
            : (pressed ? .inset : .raised)
        return configuration.label
            .font(compact ? Theme.Fonts.subheadline.weight(.bold) : Theme.Fonts.button)
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? Theme.Spacing.l : Theme.Spacing.xl)
            .padding(.vertical, compact ? Theme.Spacing.s : Theme.Spacing.m)
            .frame(maxWidth: fullWidth ? .infinity : nil,
                   minHeight: compact ? Theme.Size.compactButtonHeight : Theme.Size.buttonHeight)
            .background {
                ClayBackground(shape: Capsule(style: .continuous), style: style,
                               elevation: compact ? Theme.Elevations.small : Theme.Elevations.control)
            }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(pressed && !reduceMotion ? Theme.Motion.pressedScale : 1)
            .animation(reduceMotion ? nil : Theme.Motion.press, value: pressed)
            .opacity(isEnabled ? 1 : 0.5)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: pressed) { _, isDown in isDown }
    }

    private var foreground: Color {
        switch prominence {
        case .primary: return Theme.Colors.onAccent
        case .secondary: return Theme.Colors.text
        case .destructive: return Theme.Colors.danger
        }
    }
}

/// Round icon buttons. `.accent` is the green floating "add" button.
struct NeumorphicIconButtonStyle: ButtonStyle {
    enum Prominence {
        case plain
        case accent
    }

    var prominence: Prominence = .plain
    var size: CGFloat = Theme.Size.tapTarget
    var tint: Color = Theme.Colors.text

    func makeBody(configuration: Configuration) -> some View {
        NeumorphicIconButtonBody(configuration: configuration, prominence: prominence, size: size, tint: tint)
    }
}

private struct NeumorphicIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominence: NeumorphicIconButtonStyle.Prominence
    let size: CGFloat
    let tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        let isAccent = prominence == .accent
        let style: ClayBackground<Circle>.Style = isAccent
            ? (pressed ? .accentInset : .accent)
            : (pressed ? .inset : .raised)
        return configuration.label
            .font(size > 52 ? Theme.Fonts.title3.weight(.bold) : Theme.Fonts.headline)
            .foregroundStyle(isAccent ? Theme.Colors.onAccent : tint)
            .frame(width: size, height: size)
            .background {
                ClayBackground(shape: Circle(), style: style,
                               elevation: size > 52 ? Theme.Elevations.floating : Theme.Elevations.control)
            }
            .contentShape(Circle())
            .scaleEffect(pressed && !reduceMotion ? Theme.Motion.pressedScale : 1)
            .animation(reduceMotion ? nil : Theme.Motion.press, value: pressed)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: pressed) { _, isDown in isDown }
    }
}

/// Makes a whole card tappable: it sinks in while pressed.
struct NeumorphicCardButtonStyle: ButtonStyle {
    var padding: CGFloat = Theme.Spacing.l

    func makeBody(configuration: Configuration) -> some View {
        NeumorphicCardButtonBody(configuration: configuration, padding: padding)
    }
}

private struct NeumorphicCardButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let padding: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        return configuration.label
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ClayBackground(shape: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous),
                               style: pressed ? .inset : .raised)
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .scaleEffect(pressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : Theme.Motion.press, value: pressed)
    }
}

/// A small pill (filters, assignees, "Everyone").
struct ClayChipStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.text)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: 40)
            .background {
                ClayBackground(shape: Capsule(style: .continuous),
                               style: isSelected
                                   ? (configuration.isPressed ? .accentInset : .accent)
                                   : (configuration.isPressed ? .inset : .raised),
                               elevation: Theme.Elevations.small)
            }
            .contentShape(Capsule(style: .continuous))
            .sensoryFeedback(.selection, trigger: isSelected)
    }
}

// MARK: - Controls

/// A clay switch: inset track, raised knob; green when on.
struct ClayToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        ClayToggleBody(configuration: configuration)
    }
}

private struct ClayToggleBody: View {
    let configuration: ToggleStyleConfiguration

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: {
            if reduceMotion {
                configuration.isOn.toggle()
            } else {
                withAnimation(Theme.Motion.press) {
                    configuration.isOn.toggle()
                }
            }
        }, label: {
            HStack(spacing: Theme.Spacing.m) {
                configuration.label
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    ClayBackground(shape: Capsule(style: .continuous),
                                   style: configuration.isOn ? .accentInset : .inset)
                        .frame(width: 58, height: 34)
                    Circle()
                        .fill(Theme.Gradients.surface)
                        .overlay(Circle().stroke(Theme.Gradients.edge, lineWidth: 1))
                        .shadow(color: Theme.Colors.shade, radius: 3, x: 2, y: 2)
                        .frame(width: 26, height: 26)
                        .padding(4)
                }
            }
            .frame(minHeight: Theme.Size.tapTarget)
            .contentShape(Rectangle())
        })
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) {
                configuration.label
            }
        }
    }
}

/// A clay segmented control: an inset track with a raised thumb on the selection.
struct ClaySegmentedPicker<Value: Hashable>: View {
    struct Option {
        let value: Value
        let title: String?
        let symbol: String?
        let accessibilityName: String
    }

    @Binding var selection: Value
    let options: [Option]

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(options.indices, id: \.self) { index in
                segment(options[index])
            }
        }
        .padding(Theme.Spacing.xs)
        .clayInset(cornerRadius: 22)
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return Button(action: {
            if reduceMotion {
                selection = option.value
            } else {
                withAnimation(Theme.Motion.standard) {
                    selection = option.value
                }
            }
        }, label: {
            HStack(spacing: Theme.Spacing.xs) {
                if let symbol = option.symbol {
                    Image(systemName: symbol)
                }
                if let title = option.title {
                    Text(title)
                }
            }
            .font(Theme.Fonts.subheadline.weight(.bold))
            .foregroundStyle(isSelected ? Theme.Colors.accentInk : Theme.Colors.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
                if isSelected {
                    ClayBackground(shape: Capsule(style: .continuous), style: .raised,
                                   elevation: Theme.Elevations.small)
                        .matchedGeometryEffect(id: "thumb", in: namespace)
                }
            }
            .contentShape(Capsule(style: .continuous))
        })
        .buttonStyle(.plain)
        .accessibilityLabel(option.accessibilityName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// A search well with a magnifying glass and a clear button.
struct ClaySearchField: View {
    @Binding var text: String
    var prompt: String = "Search"

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.secondaryText)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }, label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .frame(width: 32, height: 32)
                })
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .insetField()
    }
}

// MARK: - Labels and badges

/// A small section title.
struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.Fonts.caption)
            .foregroundStyle(Theme.Colors.secondaryText)
            .textCase(.uppercase)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A person's initials on a pastel circle.
struct AvatarView: View {
    let person: Person
    var size: CGFloat = 36

    var body: some View {
        Text(person.initials)
            .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
            .foregroundStyle(Theme.onPastel.color)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.pastel(person.colorIndex)))
            .overlay(Circle().stroke(Theme.Colors.edge, lineWidth: 1))
            .accessibilityLabel(person.name)
    }
}

/// Overlapping avatars with a "+N" for the rest.
struct AvatarStack: View {
    let people: [Person]
    var size: CGFloat = 28
    var limit: Int = 4

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(people.prefix(limit))) { person in
                AvatarView(person: person, size: size)
                    .overlay(Circle().stroke(Theme.Colors.surfaceHigh, lineWidth: 2))
            }
            if people.count > limit {
                Text("+\(people.count - limit)")
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Theme.Colors.inset))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(people.count) people")
    }
}

/// A category icon on a pastel tile.
struct CategoryBadge: View {
    let symbol: String
    let colorIndex: Int
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.onPastel.color)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(Theme.pastel(colorIndex))
            )
            .accessibilityHidden(true)
    }
}

/// An icon + label + color chip (never color alone).
struct StatusChip: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
        }
        .font(Theme.Fonts.caption)
        .foregroundStyle(tint)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .clayInset(cornerRadius: Theme.Radius.small)
        .accessibilityElement(children: .combine)
    }
}

/// A friendly empty state: an icon in a well, a title and one line of text.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.accentInk)
                .frame(width: 96, height: 96)
                .clayInset(cornerRadius: 48)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.Fonts.title3)
                .foregroundStyle(Theme.Colors.text)
            Text(message)
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .accessibilityElement(children: .combine)
    }
}

/// A big money figure that rolls smoothly when it changes.
struct MoneyText: View {
    let amount: Decimal
    var font: Font = Theme.Fonts.money
    var color: Color = Theme.Colors.text

    var body: some View {
        Text(Money.string(amount))
            .font(font)
            .foregroundStyle(color)
            .contentTransition(.numericText())
    }
}
