import SwiftUI
import UIKit

// MARK: - Surfaces
//
// The surface tells you what you can do with something:
// - raised clay (soft shadows, lit edge): you can press it — buttons, chips, tappable cards;
// - flat plate (no shadow, hairline edge): information you read;
// - inset well (pressed in): something you type into or switch.

/// Soft inner shading for pressed and inset surfaces: shade on the top-left, light on
/// the bottom-right. Each side is a gradient that fades out before the middle, so the
/// lit side never picks up a dark line.
struct InnerShading<S: Shape>: View {
    let shape: S
    let dark: Color
    let light: Color

    var body: some View {
        ZStack {
            shape
                .stroke(LinearGradient(colors: [dark, dark.opacity(0)], startPoint: .topLeading,
                                       endPoint: UnitPoint(x: 0.55, y: 0.55)),
                        lineWidth: Theme.Inner.lineWidth)
                .blur(radius: Theme.Inner.blur)
                .offset(x: Theme.Inner.offset, y: Theme.Inner.offset)
            shape
                .stroke(LinearGradient(colors: [light.opacity(0), light], startPoint: UnitPoint(x: 0.45, y: 0.45),
                                       endPoint: .bottomTrailing),
                        lineWidth: Theme.Inner.lineWidth)
                .blur(radius: Theme.Inner.blur)
                .offset(x: -Theme.Inner.offset, y: -Theme.Inner.offset)
        }
        .mask { shape }
    }
}

/// The clay surface behind a card, button or field, lit from the top-left.
///
/// `.raised` and `.accent` sink into the surface while `pressed` is true; the raised
/// and pressed looks crossfade, so pressing feels smooth rather than snapping.
/// Reduce Transparency drops the blurred shading; Reduce Transparency or Increase
/// Contrast adds a visible outline, so edges never depend on shadows alone.
struct ClayBackground<S: Shape>: View {
    enum Style {
        /// Pressable: soft drop shadows and a lit edge.
        case raised
        /// Pressable, in mint.
        case accent
        /// A well pressed into the surface (fields, tracks).
        case inset
        /// A mint well (a switch that's on).
        case accentInset
        /// Flat information panel: no shadow, a hairline edge.
        case plate
    }

    let shape: S
    var style: Style = .raised
    var elevation: Theme.Elevation = Theme.Elevations.card
    var pressed: Bool = false

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        switch style {
        case .raised:
            pressable(fill: Theme.Gradients.surface, shade: Theme.Colors.shade,
                      pressedFill: Theme.Colors.inset, pressedShade: Theme.Colors.shade,
                      pressedLight: Theme.Colors.highlight)
        case .accent:
            pressable(fill: Theme.Gradients.accent, shade: Theme.Colors.accentShade,
                      pressedFill: Theme.Colors.accentLow, pressedShade: Theme.Colors.accentShade,
                      pressedLight: Theme.Colors.accentHigh)
        case .inset:
            well(fill: Theme.Colors.inset, dark: Theme.Colors.shade, light: Theme.Colors.highlight)
        case .accentInset:
            well(fill: Theme.Colors.accentLow, dark: Theme.Colors.accentShade, light: Theme.Colors.accentHigh)
        case .plate:
            ZStack {
                shape.fill(Theme.Colors.plate)
                shape.stroke(showsOutline ? Theme.Colors.outline : Theme.Colors.hairline, lineWidth: 1)
            }
        }
    }

    private var showsOutline: Bool {
        return reduceTransparency || contrast == .increased
    }

    private func pressable(fill: LinearGradient, shade: Color, pressedFill: Color, pressedShade: Color,
                           pressedLight: Color) -> some View {
        ZStack {
            raised(fill: fill, shade: shade)
                .opacity(pressed ? 0 : 1)
            well(fill: pressedFill, dark: pressedShade, light: pressedLight)
                .opacity(pressed ? 1 : 0)
        }
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

    private func well(fill: Color, dark: Color, light: Color) -> some View {
        ZStack {
            shape.fill(fill)
            if !reduceTransparency {
                InnerShading(shape: shape, dark: dark, light: light)
            }
            if showsOutline {
                shape.stroke(Theme.Colors.outline, lineWidth: 1)
            }
        }
    }
}

extension View {
    /// A raised clay surface behind this view (for things you can press).
    func clayRaised(cornerRadius: CGFloat = Theme.Radius.card,
                    elevation: Theme.Elevation = Theme.Elevations.card) -> some View {
        background {
            ClayBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                           style: .raised, elevation: elevation)
        }
    }

    /// A pressed-in clay well behind this view (for inputs).
    func clayInset(cornerRadius: CGFloat = Theme.Radius.field) -> some View {
        background {
            ClayBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), style: .inset)
        }
    }

    /// A flat plate behind this view (for information).
    func clayPlate(cornerRadius: CGFloat = Theme.Radius.card) -> some View {
        background {
            ClayBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), style: .plate)
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
            .tint(Theme.Colors.text)
            .padding(.horizontal, Theme.Spacing.l)
            .frame(minHeight: Theme.Size.fieldHeight)
            .clayInset(cornerRadius: Theme.Radius.field)
    }
}

// MARK: - Cards

/// Information: a flat plate with generous padding. Never looks pressable.
struct InfoCard<Content: View>: View {
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
            .clayPlate()
    }
}

/// A well pressed into the page, for grouped details inside a card.
struct InsetCard<Content: View>: View {
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

/// Chunky capsule buttons. Primary = mint with dark text; secondary = clay;
/// destructive = clay with red text. Pressed: sinks in, scales to 0.97, soft haptic.
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
        return configuration.label
            .font(compact ? Theme.Fonts.subheadline.weight(.bold) : Theme.Fonts.button)
            .foregroundStyle(foreground)
            .padding(.horizontal, compact ? Theme.Spacing.l : Theme.Spacing.xl)
            .padding(.vertical, compact ? Theme.Spacing.s : Theme.Spacing.m)
            .frame(maxWidth: fullWidth ? .infinity : nil,
                   minHeight: compact ? Theme.Size.compactButtonHeight : Theme.Size.buttonHeight)
            .background {
                ClayBackground(shape: Capsule(style: .continuous),
                               style: prominence == .primary ? .accent : .raised,
                               elevation: compact ? Theme.Elevations.small : Theme.Elevations.control,
                               pressed: pressed)
            }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(pressed && !reduceMotion ? Theme.Motion.pressedScale : 1)
            .animation(Theme.Motion.press, value: pressed)
            .opacity(isEnabled ? 1 : 0.45)
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

/// Round clay icon buttons. `.accent` is the mint "add" button; `.destructive` has a red icon.
struct NeumorphicIconButtonStyle: ButtonStyle {
    enum Prominence {
        case plain
        case accent
        case destructive
    }

    var prominence: Prominence = .plain
    var size: CGFloat = Theme.Size.tapTarget

    func makeBody(configuration: Configuration) -> some View {
        NeumorphicIconButtonBody(configuration: configuration, prominence: prominence, size: size)
    }
}

private struct NeumorphicIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominence: NeumorphicIconButtonStyle.Prominence
    let size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let pressed = configuration.isPressed
        return configuration.label
            .font(size > 52 ? Theme.Fonts.title3.weight(.bold) : Theme.Fonts.headline)
            .foregroundStyle(foreground)
            .frame(width: size, height: size)
            .background {
                ClayBackground(shape: Circle(), style: prominence == .accent ? .accent : .raised,
                               elevation: size > 52 ? Theme.Elevations.floating : Theme.Elevations.control,
                               pressed: pressed)
            }
            .contentShape(Circle())
            .scaleEffect(pressed && !reduceMotion ? Theme.Motion.pressedScale : 1)
            .animation(Theme.Motion.press, value: pressed)
            .opacity(isEnabled ? 1 : 0.45)
            .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.6), trigger: pressed) { _, isDown in isDown }
    }

    private var foreground: Color {
        switch prominence {
        case .plain: return Theme.Colors.text
        case .accent: return Theme.Colors.onAccent
        case .destructive: return Theme.Colors.danger
        }
    }
}

/// Makes a whole card tappable: raised clay with a small chevron at the end, so it
/// reads as something to open. It sinks in while pressed.
struct NeumorphicCardButtonStyle: ButtonStyle {
    var padding: CGFloat = Theme.Spacing.l
    var showsChevron: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        NeumorphicCardButtonBody(configuration: configuration, padding: padding, showsChevron: showsChevron)
    }
}

private struct NeumorphicCardButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let padding: CGFloat
    let showsChevron: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        return HStack(spacing: Theme.Spacing.m) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                ChevronAffordance()
            }
        }
        .padding(padding)
        .background {
            ClayBackground(shape: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous),
                           style: .raised, pressed: pressed)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .scaleEffect(pressed && !reduceMotion ? 0.985 : 1)
        .animation(Theme.Motion.press, value: pressed)
    }
}

/// The small chevron on tappable cards.
struct ChevronAffordance: View {
    var symbol: String = "chevron.right"

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.Colors.secondaryText)
            .frame(width: 26, height: 26)
            .clayInset(cornerRadius: 13)
            .accessibilityHidden(true)
    }
}

/// A small pill (filters, people, categories). Selected chips are mint.
struct ClayChipStyle: ButtonStyle {
    var isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Fonts.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.text)
            .lineLimit(1)
            .padding(.horizontal, Theme.Spacing.m)
            .frame(minHeight: 40)
            .background {
                ClayBackground(shape: Capsule(style: .continuous), style: isSelected ? .accent : .raised,
                               elevation: Theme.Elevations.small, pressed: configuration.isPressed)
            }
            .contentShape(Capsule(style: .continuous))
            .animation(Theme.Motion.press, value: configuration.isPressed)
            .sensoryFeedback(.selection, trigger: isSelected)
    }
}

// MARK: - Controls

/// A clay switch: inset track (mint when on) and a raised knob.
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
            withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
                configuration.isOn.toggle()
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
                        .compositingGroup()
                        .shadow(color: Theme.Colors.shade, radius: 3, x: 1.5, y: 1.5)
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

/// A clay segmented control: an inset track with a raised mint thumb on the selection.
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
        .clayInset(cornerRadius: 24)
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option.value == selection
        return Button(action: {
            withAnimation(reduceMotion ? nil : Theme.Motion.standard) {
                selection = option.value
            }
        }, label: {
            HStack(spacing: Theme.Spacing.xs) {
                if let symbol = option.symbol {
                    Image(systemName: symbol)
                }
                if let title = option.title {
                    Text(title)
                        .lineLimit(1)
                }
            }
            .font(Theme.Fonts.subheadline.weight(.bold))
            .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.secondaryText)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background {
                if isSelected {
                    ClayBackground(shape: Capsule(style: .continuous), style: .accent,
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
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                })
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .insetField()
    }
}

// MARK: - Layout

/// Lays chips out left to right and wraps onto new lines, so they always stay
/// inside their card instead of scrolling off the side.
struct FlowLayout: Layout {
    var spacing: CGFloat = Theme.Spacing.s
    var lineSpacing: CGFloat = Theme.Spacing.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = measure(subview, maxWidth: maxWidth)
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            widest = max(widest, x + size.width)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        let width = proposal.width ?? widest
        return CGSize(width: width.isFinite ? width : widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = measure(subview, maxWidth: bounds.width)
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + lineSpacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }

    private func measure(_ subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        if ideal.width <= maxWidth {
            return ideal
        }
        return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
    }
}

// MARK: - Drop-downs

/// A header that opens to show more below it. The content's height is measured and
/// animated smoothly, so the card grows in place instead of jumping.
struct Expandable<Header: View, Content: View>: View {
    @Binding var isExpanded: Bool
    private let header: Header
    private let content: Content

    @State private var contentHeight: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(isExpanded: Binding<Bool>, @ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self._isExpanded = isExpanded
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: {
                withAnimation(reduceMotion ? nil : Theme.Motion.expand) {
                    isExpanded.toggle()
                }
            }, label: {
                HStack(spacing: Theme.Spacing.m) {
                    header
                        .frame(maxWidth: .infinity, alignment: .leading)
                    ChevronAffordance(symbol: "chevron.down")
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(Rectangle())
            })
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Hides the details" : "Shows the details")

            content
                .fixedSize(horizontal: false, vertical: true)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(key: ExpandableHeightKey.self, value: proxy.size.height)
                    }
                }
                .frame(height: isExpanded ? contentHeight : 0, alignment: .top)
                .clipped()
                .opacity(isExpanded ? 1 : 0)
                .accessibilityHidden(!isExpanded)
        }
        .onPreferenceChange(ExpandableHeightKey.self) { height in
            contentHeight = height
        }
    }
}

private struct ExpandableHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Swipe actions

/// A button revealed by swiping a row to the left.
struct SwipeAction: Identifiable {
    let id: String
    let symbol: String
    let label: String
    var isDestructive: Bool = false
    let action: () -> Void
}

/// A row that slides left to reveal round clay buttons (edit, move, delete), in the
/// app's own style rather than the system's colored swipe buttons. Only one row is
/// open at a time (`openRow`). VoiceOver users get the same actions as accessibility actions.
struct SwipeRow<Content: View>: View {
    let id: UUID
    @Binding var openRow: UUID?
    let actions: [SwipeAction]
    private let content: Content

    @State private var drag: CGFloat = 0
    @State private var isHorizontal: Bool?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let buttonSize: CGFloat = 52

    init(id: UUID, openRow: Binding<UUID?>, actions: [SwipeAction], @ViewBuilder content: () -> Content) {
        self.id = id
        self._openRow = openRow
        self.actions = actions
        self.content = content()
    }

    private var revealWidth: CGFloat {
        return CGFloat(actions.count) * (buttonSize + Theme.Spacing.m) + Theme.Spacing.xs
    }

    var body: some View {
        let isOpen = openRow == id
        let base: CGFloat = isOpen ? -revealWidth : 0
        let raw = base + drag
        // Gentle resistance past the buttons; none to the right of closed.
        let offset = raw < -revealWidth ? -revealWidth + (raw + revealWidth) * 0.3 : min(raw, 0)
        let progress = min(max(-offset / revealWidth, 0), 1)

        return ZStack(alignment: .trailing) {
            HStack(spacing: Theme.Spacing.m) {
                ForEach(actions) { action in
                    Button(action: {
                        close()
                        action.action()
                    }, label: {
                        Image(systemName: action.symbol)
                    })
                    .buttonStyle(NeumorphicIconButtonStyle(prominence: action.isDestructive ? .destructive : .plain,
                                                           size: buttonSize))
                    .accessibilityLabel(action.label)
                }
            }
            .padding(.trailing, Theme.Spacing.xs)
            .opacity(Double(progress))
            .scaleEffect(reduceMotion ? 1 : 0.85 + 0.15 * progress, anchor: .trailing)
            .allowsHitTesting(isOpen)
            .accessibilityHidden(true)

            content
                .offset(x: offset)
        }
        .simultaneousGesture(dragGesture(base: base))
        .accessibilityActions {
            ForEach(actions) { action in
                Button(action.label, action: action.action)
            }
        }
    }

    private func dragGesture(base: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                if isHorizontal == nil {
                    isHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.3
                    if isHorizontal == true && openRow != id && openRow != nil {
                        withAnimation(Theme.Motion.standard) {
                            openRow = nil
                        }
                    }
                }
                guard isHorizontal == true else {
                    return
                }
                drag = value.translation.width
            }
            .onEnded { value in
                defer {
                    isHorizontal = nil
                }
                guard isHorizontal == true else {
                    return
                }
                let projected = base + value.predictedEndTranslation.width
                withAnimation(Theme.Motion.standard) {
                    if projected < -revealWidth / 2 {
                        openRow = id
                    } else if openRow == id {
                        openRow = nil
                    }
                    drag = 0
                }
                if projected < -revealWidth / 2 {
                    Haptics.soft()
                }
            }
    }

    private func close() {
        withAnimation(Theme.Motion.standard) {
            openRow = nil
            drag = 0
        }
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
            .foregroundStyle(Theme.Colors.onPastel)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.pastel(person.colorIndex)))
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
                    .overlay(Circle().stroke(Theme.Colors.plate, lineWidth: 2))
            }
            if people.count > limit {
                Text("+\(people.count - limit)")
                    .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .frame(width: size, height: size)
                    .background(Circle().fill(Theme.Colors.inset))
                    .overlay(Circle().stroke(Theme.Colors.plate, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(people.count) people")
    }
}

/// A category icon on a flat pastel tile.
struct CategoryBadge: View {
    let symbol: String
    let colorIndex: Int
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.Colors.onPastel)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .fill(Theme.pastel(colorIndex))
            )
            .accessibilityHidden(true)
    }
}

/// The tone of a badge or status pill.
enum StatusTone {
    /// Mint: good news, owed to you, done.
    case positive
    /// Soft amber: you owe, check this.
    case caution
    /// Soft rose: problems.
    case danger
    /// Grey: nothing to do.
    case neutral

    var fill: Color {
        switch self {
        case .positive: return Theme.Colors.accentHigh
        case .caution: return Theme.Colors.cautionFill
        case .danger: return Theme.Colors.dangerFill
        case .neutral: return Theme.Colors.inset
        }
    }

    var foreground: Color {
        switch self {
        case .positive: return Theme.Colors.onAccent
        case .caution, .danger: return Theme.Colors.onPastel
        case .neutral: return Theme.Colors.secondaryText
        }
    }
}

/// An icon on a flat colored circle. Decorative: the brand mint shows up here
/// (and in fills), never as thin green text.
struct IconBadge: View {
    let symbol: String
    var tone: StatusTone = .positive
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
            .foregroundStyle(tone.foreground)
            .frame(width: size, height: size)
            .background(Circle().fill(tone.fill))
            .accessibilityHidden(true)
    }
}

/// A flat pill with an icon and a label (never color alone).
struct StatusPill: View {
    let title: String
    let symbol: String
    var tone: StatusTone = .positive

    var body: some View {
        Label {
            Text(title)
                .lineLimit(1)
        } icon: {
            Image(systemName: symbol)
        }
        .font(Theme.Fonts.caption)
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.xs + 2)
        .background(Capsule(style: .continuous).fill(tone.fill))
        .accessibilityElement(children: .combine)
    }
}

/// A friendly empty state: an icon on a mint circle, a title and one line of text.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            IconBadge(symbol: symbol, tone: .positive, size: 88)
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

/// A money figure that rolls smoothly when it changes.
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

// MARK: - Receipt icon

/// A paper receipt with a torn bottom edge. Uses the SF Symbol when this iOS has
/// one, otherwise draws its own.
struct ReceiptIcon: View {
    var size: CGFloat = 20

    private static let systemSymbol: String? = {
        for name in ["receipt.fill", "receipt"] where UIImage(systemName: name) != nil {
            return name
        }
        return nil
    }()

    var body: some View {
        if let symbol = ReceiptIcon.systemSymbol {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold, design: .rounded))
        } else {
            ReceiptShape()
                .fill(style: FillStyle(eoFill: true))
                .frame(width: size * 0.82, height: size)
        }
    }
}

/// The fallback receipt glyph: rounded top, zig-zag bottom, three printed lines cut out.
struct ReceiptShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width * 0.18
        let teeth = 4
        let toothWidth = rect.width / CGFloat(teeth)
        let toothHeight = rect.height * 0.1
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        for index in 0..<teeth {
            let right = rect.maxX - CGFloat(index) * toothWidth
            path.addLine(to: CGPoint(x: right - toothWidth / 2, y: rect.maxY - toothHeight))
            path.addLine(to: CGPoint(x: right - toothWidth, y: rect.maxY))
        }
        path.closeSubpath()
        // Printed lines, cut out with even-odd filling.
        let lineHeight = rect.height * 0.08
        let left = rect.minX + rect.width * 0.24
        for (index, widthFactor) in [0.52, 0.52, 0.32].enumerated() {
            let top = rect.minY + rect.height * (0.24 + 0.18 * CGFloat(index))
            path.addRoundedRect(in: CGRect(x: left, y: top, width: rect.width * CGFloat(widthFactor), height: lineHeight),
                                cornerSize: CGSize(width: lineHeight / 2, height: lineHeight / 2))
        }
        return path
    }
}
