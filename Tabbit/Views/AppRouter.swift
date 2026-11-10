import SwiftUI

/// The three tabs.
enum AppTab: String, CaseIterable, Identifiable {
    case groups
    case receipts
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .groups: return "Groups"
        case .receipts: return "My Receipts"
        case .profile: return "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .groups: return "person.3.fill"
        case .receipts: return "doc.text.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }
}

/// Screens that are pushed onto a tab's navigation stack.
enum Route: Hashable {
    case group(UUID)
    /// A receipt, with the other receipts of the same group (or My Receipts) one swipe away.
    case receipt(UUID, inGroup: UUID?)
    case settleUp(UUID)
    case settings
}

/// Which tab is showing and what's pushed on each one.
@MainActor
final class AppRouter: ObservableObject {
    @Published var tab: AppTab = .groups
    @Published var groupsPath: [Route] = []
    @Published var receiptsPath: [Route] = []
    @Published var profilePath: [Route] = []

    /// The tab bar only shows on the tabs' first screens.
    var isAtRoot: Bool {
        switch tab {
        case .groups: return groupsPath.isEmpty
        case .receipts: return receiptsPath.isEmpty
        case .profile: return profilePath.isEmpty
        }
    }

    func push(_ route: Route) {
        switch tab {
        case .groups: groupsPath.append(route)
        case .receipts: receiptsPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    /// Tapping the current tab again goes back to its first screen.
    func select(_ newTab: AppTab) {
        if newTab == tab {
            switch tab {
            case .groups: groupsPath = []
            case .receipts: receiptsPath = []
            case .profile: profilePath = []
            }
        } else {
            tab = newTab
        }
    }
}
