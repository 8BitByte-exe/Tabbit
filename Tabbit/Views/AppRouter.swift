import SwiftUI

/// The tabs.
enum AppTab: String, CaseIterable, Identifiable {
    case groups
    case receipts
    case work
    case map
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .groups: return "Groups"
        case .receipts: return "My Receipts"
        case .work: return "Work"
        case .map: return "Map"
        case .profile: return "Profile"
        }
    }

    var symbol: String {
        switch self {
        case .groups: return "person.3.fill"
        case .receipts: return "doc.text.fill"
        case .work: return "briefcase.fill"
        case .map: return "map.fill"
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
    /// A business (Work): its year, jobs, invoices and receipts.
    case business(UUID)
    case job(UUID, business: UUID)
    /// A business's receipt, with its other receipts (or the job's) one swipe away.
    case workReceipt(UUID, business: UUID, job: UUID?)
    /// A group's receipts on a map.
    case map(UUID)
    case settings
}

/// Which tab is showing and what's pushed on each one.
@MainActor
final class AppRouter: ObservableObject {
    @Published var tab: AppTab = .groups
    @Published var groupsPath: [Route] = []
    @Published var receiptsPath: [Route] = []
    @Published var workPath: [Route] = []
    @Published var mapPath: [Route] = []
    @Published var profilePath: [Route] = []

    /// The tab bar only shows on the tabs' first screens.
    var isAtRoot: Bool {
        switch tab {
        case .groups: return groupsPath.isEmpty
        case .receipts: return receiptsPath.isEmpty
        case .work: return workPath.isEmpty
        case .map: return mapPath.isEmpty
        case .profile: return profilePath.isEmpty
        }
    }

    func push(_ route: Route) {
        switch tab {
        case .groups: groupsPath.append(route)
        case .receipts: receiptsPath.append(route)
        case .work: workPath.append(route)
        case .map: mapPath.append(route)
        case .profile: profilePath.append(route)
        }
    }

    /// Tapping the current tab again goes back to its first screen.
    func select(_ newTab: AppTab) {
        if newTab == tab {
            switch tab {
            case .groups: groupsPath = []
            case .receipts: receiptsPath = []
            case .work: workPath = []
            case .map: mapPath = []
            case .profile: profilePath = []
            }
        } else {
            tab = newTab
        }
    }
}
