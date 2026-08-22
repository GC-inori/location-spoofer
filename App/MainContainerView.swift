import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case location
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .location: return "定位"
        case .settings: return "配置"
        }
    }

    var iconName: String {
        switch self {
        case .location: return "location.viewfinder"
        case .settings: return "gearshape.circle"
        }
    }
}

struct MainContainerView: View {
    @ObservedObject var setup: SetupCoordinator
    @StateObject private var actions = LocationActionCoordinator()
    @StateObject private var favorites = FavoriteLocationStore()
    @State private var selectedTab: MainTab = .location

    // 青绿色主题色（匹配截图标注与高亮颜色）
    static let accentTeal = Color(red: 0.0, green: 0.82, blue: 0.71)

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab 1: 地图定位（常驻层，切换 Tab 不销毁 MapView 实例，保证零卡顿）
            MapHomeView(
                setup: setup,
                favorites: favorites,
                actions: actions,
                onOpenSettings: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = .settings
                    }
                }
            )
            .opacity(selectedTab == .location ? 1 : 0)
            .disabled(selectedTab != .location)

            // Tab 2: 配置设置
            NavigationView {
                SettingsView(
                    setup: setup,
                    actions: actions,
                    favorites: favorites,
                    onSwitchToLocationTab: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedTab = .location
                        }
                    }
                )
            }
            .navigationViewStyle(.stack)
            .opacity(selectedTab == .settings ? 1 : 0)
            .disabled(selectedTab != .settings)

            // 底部半透明毛玻璃导航栏
            customTabBar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var customTabBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(Color.white.opacity(0.12))
            HStack(spacing: 0) {
                tabButton(for: .location)
                tabButton(for: .settings)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 6)
        }
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                Color.black.opacity(0.55)
            }
            .ignoresSafeArea(edges: .bottom)
        )
    }

    private func tabButton(for tab: MainTab) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            if selectedTab != tab {
                withAnimation(.easeInOut(duration: 0.18)) {
                    selectedTab = tab
                }
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 23, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Self.accentTeal : Color.secondary)
                Text(tab.title)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? Self.accentTeal : Color.secondary)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}