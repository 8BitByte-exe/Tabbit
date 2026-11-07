import MapKit
import SwiftUI

/// Receipts on a map: the Map tab (every receipt) or one group's map (a trip).
///
/// Each pin is a store, placed from the address printed on its receipts. Apple Maps finds
/// each address once (`PlaceFinder`) and the place is kept with the receipt. The map is off
/// until the person turns it on, because the store's name and address go to Apple Maps and
/// the map itself comes from Apple Maps; until then no map is drawn at all. Receipts without
/// a place are listed, so an address can be typed in.
struct ReceiptMapView: View {
    /// Nil for every receipt (the Map tab), or one group's receipts.
    let groupID: UUID?

    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var places: PlaceFinder

    @AppStorage(MapSettings.enabledKey) private var isEnabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedPinID: String?
    @State private var showsUnplaced = false

    private var isTab: Bool {
        return groupID == nil
    }

    /// The tab's map is only drawn while the tab shows (tabs stay alive in the background).
    private var isVisible: Bool {
        return !isTab || router.tab == .map
    }

    private var receipts: [ReceiptRecord] {
        guard let groupID = groupID else {
            return store.receipts
        }
        return store.receipts(in: groupID)
    }

    var body: some View {
        let receipts = self.receipts
        let pins = ReceiptMap.pins(for: receipts)
        let waiting = ReceiptMap.waiting(receipts).count
        return screen(receipts: receipts, pins: pins, waiting: waiting)
            .onAppear {
                startFinding()
            }
            .onChange(of: waiting) { _, _ in
                startFinding()
            }
            .onChange(of: router.tab) { _, _ in
                startFinding()
            }
            .onChange(of: isEnabled) { _, enabled in
                if enabled {
                    startFinding()
                } else {
                    places.stop()
                    selectedPinID = nil
                }
            }
            .sheet(isPresented: $showsUnplaced) {
                UnplacedReceiptsSheet(groupID: groupID)
                    .environmentObject(store)
                    .environmentObject(places)
            }
            .task {
                #if DEBUG
                await showDemoState()
                #endif
            }
    }

    // MARK: - Layout

    @ViewBuilder
    private func screen(receipts: [ReceiptRecord], pins: [ReceiptMap.Pin], waiting: Int) -> some View {
        if isTab {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                ScreenHeader(title: "Map", subtitle: subtitle(receipts: receipts, pins: pins)) {
                    if isEnabled && !pins.isEmpty {
                        showAllButton
                    }
                }
                .padding(.horizontal, Theme.Spacing.screen)
                content(receipts: receipts, pins: pins, waiting: waiting)
            }
            .padding(.top, Theme.Spacing.l)
            .padding(.bottom, Theme.Size.tabBarHeight + Theme.Spacing.l + Theme.Spacing.s)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .themedScreen()
            .toolbar(.hidden, for: .navigationBar)
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                content(receipts: receipts, pins: pins, waiting: waiting)
            }
            .padding(.top, Theme.Spacing.s)
            .padding(.bottom, Theme.Spacing.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .themedScreen()
            .clayNavigation(store.group(groupID)?.displayName ?? "Map") {
                if isEnabled && !pins.isEmpty {
                    showAllButton
                }
            }
        }
    }

    @ViewBuilder
    private func content(receipts: [ReceiptRecord], pins: [ReceiptMap.Pin], waiting: Int) -> some View {
        if isEnabled {
            statusRow(unplaced: ReceiptMap.unplaced(receipts).count)
                .padding(.horizontal, Theme.Spacing.screen)
            mapCard(pins: pins, waiting: waiting)
                .padding(.horizontal, Theme.Spacing.screen)
            if let pin = pins.first(where: { candidate in candidate.id == selectedPinID }) {
                PinCard(pin: pin, receipts: pin.receiptIDs.compactMap { id in store.receipt(id) },
                        people: { receipt in store.people(for: receipt.groupID) },
                        onOpen: { receipt in
                            router.push(.receipt(receipt.id, inGroup: receipt.groupID))
                        },
                        onClose: {
                            selectedPinID = nil
                        })
                    .padding(.horizontal, Theme.Spacing.screen)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        } else {
            ScrollView {
                MapIntroCard(onTurnOn: {
                    Haptics.success()
                    isEnabled = true
                })
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.s)
            }
        }
    }

    private func subtitle(receipts: [ReceiptRecord], pins: [ReceiptMap.Pin]) -> String {
        guard isEnabled else {
            return "Where you spent"
        }
        let placed = pins.reduce(0) { sum, pin in sum + pin.receiptIDs.count }
        if placed == 0 {
            return "No places yet"
        }
        let receiptsText = placed == 1 ? "1 receipt" : "\(placed) receipts"
        let placesText = pins.count == 1 ? "1 place" : "\(pins.count) places"
        return "\(receiptsText) · \(placesText)"
    }

    private var showAllButton: some View {
        Button(action: {
            selectedPinID = nil
            if reduceMotion {
                position = .automatic
            } else {
                withAnimation(Theme.Motion.standard) {
                    position = .automatic
                }
            }
        }, label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
        })
        .buttonStyle(NeumorphicIconButtonStyle())
        .accessibilityLabel("Show all places")
    }

    // MARK: - Status

    @ViewBuilder
    private func statusRow(unplaced: Int) -> some View {
        if places.phase != .idle || unplaced > 0 {
            FlowLayout(spacing: Theme.Spacing.s, lineSpacing: Theme.Spacing.s) {
                switch places.phase {
                case .idle:
                    EmptyView()
                case .finding(let done, let total):
                    StatusPill(title: "Finding places… \(min(done + 1, total)) of \(total)",
                               symbol: "magnifyingglass", tone: .neutral)
                case .unreachable:
                    StatusPill(title: "Couldn't reach Apple Maps", symbol: "wifi.exclamationmark", tone: .caution)
                    Button(action: {
                        places.start(in: store)
                    }, label: {
                        Label("Try Again", systemImage: "arrow.clockwise")
                    })
                    .buttonStyle(NeumorphicButtonStyle(prominence: .secondary, fullWidth: false, compact: true))
                }
                if unplaced > 0 {
                    Button(action: {
                        showsUnplaced = true
                    }, label: {
                        Label(unplaced == 1 ? "1 receipt not on the map" : "\(unplaced) receipts not on the map",
                              systemImage: "mappin.slash")
                    })
                    .buttonStyle(NeumorphicButtonStyle(prominence: .secondary, fullWidth: false, compact: true))
                }
            }
        }
    }

    // MARK: - Map

    private func mapCard(pins: [ReceiptMap.Pin], waiting: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
        return ZStack {
            if isVisible {
                Map(position: $position, interactionModes: [.pan, .zoom]) {
                    ForEach(pins) { pin in
                        Annotation(pin.title, coordinate: pin.coordinate, anchor: .bottom) {
                            MapPinButton(pin: pin, isSelected: pin.id == selectedPinID, action: {
                                select(pin)
                            })
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControls {
                }
            } else {
                Theme.Colors.inset
            }
            if pins.isEmpty {
                noPlacesNote(waiting: waiting)
                    .padding(Theme.Spacing.l)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(shape)
        .overlay(shape.stroke(Theme.Colors.hairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Map")
    }

    private func noPlacesNote(waiting: Int) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            IconBadge(symbol: "mappin.and.ellipse", tone: .positive, size: 52)
            Text(waiting > 0 ? "Finding your stores…" : "No places yet")
                .font(Theme.Fonts.headline)
                .foregroundStyle(Theme.Colors.text)
            Text("Receipts with a store address get a pin here.")
                .font(Theme.Fonts.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: 280)
        .clayPlate()
        .accessibilityElement(children: .combine)
    }

    private func select(_ pin: ReceiptMap.Pin) {
        Haptics.selection()
        let newSelection: String? = selectedPinID == pin.id ? nil : pin.id
        if reduceMotion {
            selectedPinID = newSelection
        } else {
            withAnimation(Theme.Motion.standard) {
                selectedPinID = newSelection
            }
        }
    }

    private func startFinding() {
        guard isEnabled, isVisible else {
            return
        }
        places.start(in: store)
    }

    #if DEBUG
    /// Screenshot states: a selected pin, or the list of receipts without a place.
    private func showDemoState() async {
        guard isTab, let screen = DemoMode.screen else {
            return
        }
        if screen == "mappin" {
            try? await Task.sleep(nanoseconds: 800_000_000)
            selectedPinID = ReceiptMap.pins(for: receipts).first { pin in
                pin.receiptIDs.contains(DemoMode.timeOutID)
            }?.id
        } else if screen == "mapfix" {
            try? await Task.sleep(nanoseconds: 800_000_000)
            showsUnplaced = true
        }
    }
    #endif
}

// MARK: - Pins

/// A store on the map: its category on a pastel circle, with a count when several
/// receipts share it. The selected pin grows and gets a mint ring.
private struct MapPinButton: View {
    let pin: ReceiptMap.Pin
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: -1) {
                Image(systemName: pin.category.symbol)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.onPastel)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(Theme.pastel(pin.category.colorIndex)))
                    .overlay(Circle().stroke(ring, lineWidth: 3))
                    .overlay(alignment: .topTrailing) {
                        if pin.receiptIDs.count > 1 {
                            Text("\(pin.receiptIDs.count)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.Colors.onAccent)
                                .padding(.horizontal, 5)
                                .frame(minWidth: 20, minHeight: 20)
                                .background(Capsule(style: .continuous).fill(Theme.Colors.accentHigh))
                                .overlay(Capsule(style: .continuous).stroke(Theme.Colors.plate, lineWidth: 2))
                                .offset(x: 8, y: -8)
                        }
                    }
                PinTail()
                    .fill(ring)
                    .frame(width: 14, height: 8)
            }
            .scaleEffect(isSelected && !reduceMotion ? 1.18 : 1, anchor: .bottom)
            .frame(minWidth: Theme.Size.tapTarget, minHeight: Theme.Size.tapTarget, alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var ring: Color {
        return isSelected ? Theme.Colors.accentLow : Theme.Colors.plate
    }

    private var accessibilityText: String {
        let count = pin.receiptIDs.count
        return count == 1 ? pin.title : "\(pin.title), \(count) receipts"
    }
}

/// The point under a pin.
private struct PinTail: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// The selected pin's receipts, under the map. Each one opens the receipt.
private struct PinCard: View {
    let pin: ReceiptMap.Pin
    let receipts: [ReceiptRecord]
    let people: (ReceiptRecord) -> [Person]
    let onOpen: (ReceiptRecord) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(pin.title)
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.Colors.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if !pin.address.isEmpty {
                        Label(pin.address, systemImage: "mappin.and.ellipse")
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .lineLimit(2)
                    }
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(NeumorphicIconButtonStyle())
                .accessibilityLabel("Close")
            }
            if receipts.count > 2 {
                ScrollView {
                    rows
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.vertical, Theme.Spacing.s)
                }
                .frame(height: 232)
                .padding(.horizontal, -Theme.Spacing.l)
            } else {
                rows
            }
        }
        .padding(Theme.Spacing.l)
        .clayPlate()
    }

    private var rows: some View {
        VStack(spacing: Theme.Spacing.m) {
            ForEach(receipts) { receipt in
                Button(action: {
                    onOpen(receipt)
                }, label: {
                    ReceiptRow(receipt: receipt, people: people(receipt))
                })
                .buttonStyle(NeumorphicCardButtonStyle(padding: Theme.Spacing.m))
            }
        }
    }
}

// MARK: - Turning it on

/// Shown instead of the map until it's turned on: what it does and what leaves the phone.
private struct MapIntroCard: View {
    let onTurnOn: () -> Void

    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                IconBadge(symbol: "map.fill", tone: .positive, size: 64)
                Text("See where you spent")
                    .font(Theme.Fonts.title3)
                    .foregroundStyle(Theme.Colors.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Pins every receipt's store on a map, from the address printed on it. Tap a pin to see what you bought there. Each group has its own map too, for trips.")
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    Label("Apple Maps gets each store's name and address once, to find it, and draws the map.",
                          systemImage: "map")
                    Label("Items, amounts, people and photos never leave your iPhone.", systemImage: "lock.fill")
                    Label("Places are kept with your receipts, on this iPhone only.", systemImage: "iphone")
                }
                .font(Theme.Fonts.callout)
                .foregroundStyle(Theme.Colors.text)
                .fixedSize(horizontal: false, vertical: true)
                Button(action: onTurnOn) {
                    Label("Turn On Map", systemImage: "map.fill")
                }
                .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
                Text("You can turn it off any time in Settings.")
                    .font(Theme.Fonts.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Receipts without a place

/// Receipts that aren't on the map, each with a field to type the store's address.
struct UnplacedReceiptsSheet: View {
    let groupID: UUID?

    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var places: PlaceFinder
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: UUID?

    var body: some View {
        let receipts = groupID == nil ? store.receipts : store.receipts(in: groupID)
        let unplaced = ReceiptMap.unplaced(receipts)
        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                SheetHeader(title: "Not on the Map", onClose: {
                    focus = nil
                    dismiss()
                })
                Text("Type the store's street and city, the way you'd search for it in Maps. Tabbit finds it once and pins it.")
                    .font(Theme.Fonts.callout)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if unplaced.isEmpty {
                    EmptyStateView(symbol: "checkmark", title: "All on the map",
                                   message: "Every receipt with an address has a pin.")
                }
                ForEach(unplaced) { receipt in
                    AddressRow(receipt: receipt, focus: $focus, onFind: { address in
                        focus = nil
                        store.setLocation(address, for: receipt.id)
                        places.start(in: store)
                    })
                }
            }
            .padding(.horizontal, Theme.Spacing.screen)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.xxl)
        }
        .scrollDismissesKeyboard(.interactively)
        .themedScreen()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if focus != nil {
                HStack {
                    Spacer()
                    Button(action: {
                        focus = nil
                    }, label: {
                        Label("Done", systemImage: "keyboard.chevron.compact.down")
                    })
                    .buttonStyle(NeumorphicButtonStyle(prominence: .secondary, fullWidth: false, compact: true))
                }
                .padding(.horizontal, Theme.Spacing.screen)
                .padding(.vertical, Theme.Spacing.s)
                .background(Theme.Colors.background.ignoresSafeArea())
            }
        }
        .presentationDetents([.large])
        .claySheet()
    }
}

/// One receipt without a place: why, and a field for its address.
private struct AddressRow: View {
    let receipt: ReceiptRecord
    let focus: FocusState<UUID?>.Binding
    let onFind: (String) -> Void

    @State private var text: String

    init(receipt: ReceiptRecord, focus: FocusState<UUID?>.Binding, onFind: @escaping (String) -> Void) {
        self.receipt = receipt
        self.focus = focus
        self.onFind = onFind
        _text = State(initialValue: receipt.location)
    }

    private var trimmed: String {
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isNotFound: Bool {
        return ReceiptMap.status(of: receipt) == .notFound
    }

    var body: some View {
        InfoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.m) {
                    CategoryBadge(symbol: receipt.category.symbol, colorIndex: receipt.category.colorIndex, size: 40)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        Text(receipt.displayTitle)
                            .font(Theme.Fonts.headline)
                            .foregroundStyle(Theme.Colors.text)
                        Text(DateText.short(receipt.date))
                            .font(Theme.Fonts.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                if isNotFound {
                    StatusPill(title: "Apple Maps couldn't find this address", symbol: "mappin.slash", tone: .caution)
                } else {
                    StatusPill(title: "No address on the receipt", symbol: "questionmark", tone: .neutral)
                }
                TextField("Street and city", text: $text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused(focus, equals: receipt.id)
                    .onSubmit(find)
                    .insetField()
                    .accessibilityLabel("Address of \(receipt.displayTitle)")
                Button(action: find) {
                    Label("Find on the Map", systemImage: "magnifyingglass")
                }
                .buttonStyle(NeumorphicButtonStyle(prominence: .secondary, compact: true))
                .disabled(!canFind)
            }
        }
    }

    /// Something new to look up: a typed address that isn't the one already tried.
    private var canFind: Bool {
        return !trimmed.isEmpty && trimmed != receipt.location
    }

    private func find() {
        guard canFind else {
            return
        }
        onFind(trimmed)
    }
}
