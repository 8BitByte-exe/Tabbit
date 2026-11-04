import PhotosUI
import SwiftUI

@main
struct TabbitApp: App {
    @StateObject private var store: TabbitStore
    @StateObject private var router: AppRouter
    @StateObject private var flow: ReceiptFlow

    init() {
        Theme.configureNavigationBar()

        let store: TabbitStore
        #if DEBUG
        if DemoMode.isEnabled {
            // Screenshot mode (CI): sample data in a throwaway folder, never the real one.
            store = TabbitStore(folder: DemoMode.freshFolder())
            DemoMode.populate(store)
        } else {
            store = TabbitStore()
        }
        #else
        store = TabbitStore()
        #endif

        let router = AppRouter()
        let flow = ReceiptFlow(store: store)
        #if DEBUG
        DemoMode.prepare(router: router, flow: flow, store: store)
        #endif

        _store = StateObject(wrappedValue: store)
        _router = StateObject(wrappedValue: router)
        _flow = StateObject(wrappedValue: flow)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
                .environmentObject(flow)
        }
    }
}

/// The tabs, the floating tab bar, and everything that can appear over any screen:
/// the add-receipt sheet, camera, photo picker, editor and processing overlay.
struct RootView: View {
    @EnvironmentObject private var store: TabbitStore
    @EnvironmentObject private var router: AppRouter
    @EnvironmentObject private var flow: ReceiptFlow

    @AppStorage(AppearanceSetting.storageKey) private var appearance: AppearanceSetting = .system
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsWhatsNew = false

    var body: some View {
        ZStack(alignment: .bottom) {
            tab(.groups) {
                NavigationStack(path: $router.groupsPath) {
                    GroupsView()
                        .navigationDestination(for: Route.self) { route in
                            RouteView(route: route)
                        }
                }
            }
            tab(.receipts) {
                NavigationStack(path: $router.receiptsPath) {
                    MyReceiptsView()
                        .navigationDestination(for: Route.self) { route in
                            RouteView(route: route)
                        }
                }
            }
            tab(.profile) {
                NavigationStack(path: $router.profilePath) {
                    ProfileView()
                        .navigationDestination(for: Route.self) { route in
                            RouteView(route: route)
                        }
                }
            }

            if router.isAtRoot {
                ClayTabBar(selection: router.tab, onSelect: { tab in
                    router.select(tab)
                })
                .padding(.bottom, Theme.Spacing.s)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : Theme.Motion.standard, value: router.isAtRoot)
        .tint(Theme.Colors.accentInk)
        .sheet(isPresented: $flow.isChoosingSource, onDismiss: {
            flow.sourceSheetDismissed()
        }, content: {
            AddReceiptSheet()
                .environmentObject(store)
                .environmentObject(flow)
        })
        .fullScreenCover(isPresented: $flow.isShowingScanner) {
            DocumentScannerView(onOutcome: { outcome in
                flow.handle(outcome)
            })
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $flow.isShowingPhotoPicker, selection: $flow.photoSelection,
                      maxSelectionCount: 5, selectionBehavior: .ordered, matching: .images)
        .onChange(of: flow.photoSelection) { _, items in
            if !items.isEmpty {
                flow.handlePickedPhotos()
            }
        }
        .sheet(item: $flow.session) { session in
            ReceiptEditorView(session: session)
                .environmentObject(store)
                .environmentObject(flow)
        }
        .sheet(isPresented: $showsWhatsNew) {
            WhatsNewView()
        }
        .overlay {
            phaseOverlay
        }
        .alert("Something went wrong", isPresented: errorBinding, actions: {
            Button("OK", role: .cancel) {
                store.lastError = nil
            }
        }, message: {
            Text(store.lastError ?? "")
        })
        .sensoryFeedback(.selection, trigger: router.tab)
        .preferredColorScheme(appearance.colorScheme)
        .onAppear {
            checkWhatsNew()
        }
    }

    /// Keeps every tab alive (so each keeps its place) and shows only the selected one.
    private func tab<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        let isSelected = router.tab == tab
        return content()
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }

    private var errorBinding: Binding<Bool> {
        return Binding(get: {
            store.lastError != nil
        }, set: { isShowing in
            if !isShowing {
                store.lastError = nil
            }
        })
    }

    @ViewBuilder
    private var phaseOverlay: some View {
        switch flow.phase {
        case .idle:
            EmptyView()
        case .processing:
            ProcessingOverlay()
        case .failed(let message):
            ErrorOverlay(
                message: message,
                onRetry: {
                    flow.retry()
                },
                onClose: {
                    flow.dismissError()
                }
            )
        }
    }

    /// Shows What's New once after an update (not on a fresh install).
    private func checkWhatsNew() {
        #if DEBUG
        if DemoMode.isEnabled {
            showsWhatsNew = DemoMode.screen == "whatsnew"
            return
        }
        #endif
        let defaults = UserDefaults.standard
        let lastSeen = defaults.string(forKey: Changelog.lastSeenKey)
        let current = Changelog.currentVersion
        guard lastSeen != current else {
            return
        }
        if lastSeen != nil || !store.receipts.isEmpty {
            showsWhatsNew = true
        }
        defaults.set(current, forKey: Changelog.lastSeenKey)
    }
}

/// The screen for a pushed route.
struct RouteView: View {
    let route: Route

    var body: some View {
        switch route {
        case .group(let id):
            GroupDetailView(groupID: id)
        case .receipt(let id, let groupID):
            ReceiptPagerView(startID: id, groupID: groupID)
        case .settleUp(let id):
            SettleUpView(groupID: id)
        case .settings:
            SettingsView()
        }
    }
}

/// The floating clay tab bar: icons only, the selected tab sits on a green pill.
struct ClayTabBar: View {
    let selection: AppTab
    let onSelect: (AppTab) -> Void

    @Namespace private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(AppTab.allCases) { tab in
                button(for: tab)
            }
        }
        .padding(Theme.Spacing.s)
        .clayRaised(cornerRadius: Theme.Size.tabBarHeight / 2, elevation: Theme.Elevations.floating)
        .padding(.horizontal, 52)
    }

    private func button(for tab: AppTab) -> some View {
        let isSelected = tab == selection
        return Button(action: {
            if reduceMotion {
                onSelect(tab)
            } else {
                withAnimation(Theme.Motion.bouncy) {
                    onSelect(tab)
                }
            }
        }, label: {
            Image(systemName: tab.symbol)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(isSelected ? Theme.Colors.onAccent : Theme.Colors.secondaryText)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Size.tabBarHeight - 2 * Theme.Spacing.s)
                .background {
                    if isSelected {
                        ClayBackground(shape: Capsule(style: .continuous), style: .accent,
                                       elevation: Theme.Elevations.small)
                            .matchedGeometryEffect(id: "selectedTab", in: namespace)
                    }
                }
                .contentShape(Capsule(style: .continuous))
        })
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Shown while a scan is being read.
struct ProcessingOverlay: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Theme.Colors.background
                .opacity(reduceTransparency ? 1 : 0.92)
                .ignoresSafeArea()
            NeumorphicCard {
                VStack(spacing: Theme.Spacing.l) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(Theme.Colors.accentInk)
                        .frame(width: 72, height: 72)
                        .clayInset(cornerRadius: 36)
                    Text("Reading your receipt…")
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Label("Everything stays on this iPhone", systemImage: "lock.fill")
                        .font(Theme.Fonts.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(Theme.Spacing.xxl)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Reading your receipt")
    }
}

/// Shown when scanning or reading failed.
struct ErrorOverlay: View {
    let message: String
    let onRetry: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Theme.Colors.background
                .opacity(reduceTransparency ? 1 : 0.92)
                .ignoresSafeArea()
            NeumorphicCard {
                VStack(spacing: Theme.Spacing.l) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(Theme.Fonts.largeTitle)
                        .foregroundStyle(Theme.Colors.warning)
                        .accessibilityHidden(true)
                    Text("Something went wrong")
                        .font(Theme.Fonts.headline)
                        .foregroundStyle(Theme.Colors.text)
                    Text(message)
                        .font(Theme.Fonts.callout)
                        .foregroundStyle(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                    Button(action: onRetry) {
                        Label("Try Again", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(NeumorphicButtonStyle(prominence: .primary))
                    Button("Close", action: onClose)
                        .buttonStyle(NeumorphicButtonStyle(prominence: .secondary))
                }
                .frame(maxWidth: .infinity)
            }
            .padding(Theme.Spacing.xl)
        }
    }
}
