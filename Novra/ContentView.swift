import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state
    @AppStorage(Prefs.Key.onboarded) private var onboarded = false

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 236)
            ZStack {
                AmbientBackground()
                detail
                    .id(state.section)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 18)).combined(with: .scale(scale: 0.985)),
                        removal: .opacity
                    ))
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.88), value: state.section)
            .overlay { ActivityOverlay() }
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refresh()
        }
        .sheet(isPresented: .init(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            OnboardingView { onboarded = true }
                .interactiveDismissDisabled()
        }
        .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in
            state.disk = SystemInfo.disk()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch state.section {
        case .scan: SmartScanView(model: state.scan)
        case .apps: AppsView(model: state.apps)
        case .projects: ProjectsView(model: state.projects)
        case .photos: PhotosView(model: state.photos)
        case .largeFiles: LargeFilesView(model: state.largeFiles)
        case .duplicates: DuplicatesView(model: state.duplicates)
        case .startup: StartupView(model: state.startup)
        case .toolkit: ToolkitView(model: state.toolkit)
        case .history: HistoryView()
        }
    }
}

private struct Sidebar: View {
    @Environment(AppState.self) private var state
    @Namespace private var selection
    @State private var logoIn = false
    @State private var barIn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image("NovraLogo").resizable().frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .rotationEffect(.degrees(logoIn ? 0 : -25))
                    .scaleEffect(logoIn ? 1 : 0.5)
                Text("Novra").font(.system(size: 22, weight: .bold))
                    .opacity(logoIn ? 1 : 0)
                    .offset(x: logoIn ? 0 : -8)
            }
            .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.6).delay(0.1)) { logoIn = true } }
            .padding(.top, 58)
            .padding(.horizontal, 22)
            .padding(.bottom, 30)

            VStack(spacing: 2) {
                ForEach(Array(Section.allCases.enumerated()), id: \.element) { index, section in
                    SidebarItem(section: section, isOn: state.section == section, namespace: selection) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { state.section = section }
                    }
                    .reveal(delay: 0.15 + Double(index) * 0.05)
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            if let release = Updates.shared.available {
                UpdateCard(release: release)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            diskSummary
                .padding(.horizontal, 22)
                .padding(.bottom, 14)

            SettingsLink {
                Label("Settings", systemImage: "gearshape").font(.system(size: 12.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondary)
            .padding(.horizontal, 22)
            .padding(.bottom, 12)

            Button { SystemInfo.open("https://naqara.dev") } label: {
                HStack(spacing: 6) {
                    Text("Powered by").foregroundStyle(Theme.tertiary)
                    Text("naqara.dev").fontWeight(.semibold).foregroundStyle(Theme.lavender)
                    Image(systemName: "arrow.up.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.lavender)
                }
                .font(.system(size: 11.5))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.bottom, 6)
            .help("Made by Naqara Dev")

            Button { SystemInfo.open(SystemInfo.repository) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 10, weight: .semibold))
                    Text("Open source on GitHub")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.tertiary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
            .help(SystemInfo.repository)
        }
        .frame(maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Color(hex: 0x0C1230), Theme.sidebar], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .trailing) { Rectangle().fill(Theme.stroke).frame(width: 1) }
    }

    private var diskSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "internaldrive").foregroundStyle(Theme.lavender)
                Text("Macintosh HD").font(.system(size: 12, weight: .semibold))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule().fill(LinearGradient(colors: Theme.diskColors(state.disk.usedFraction), startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * (barIn ? state.disk.usedFraction : 0))
                }
            }
            .frame(height: 6)
            .onAppear { withAnimation(.spring(response: 1.2, dampingFraction: 0.8).delay(0.4)) { barIn = true } }
            Text("\(state.disk.free.byteString) free of \(state.disk.total.byteString)")
                .font(.system(size: 11)).foregroundStyle(Theme.secondary)
                .contentTransition(.numericText())
                .animation(.snappy, value: state.disk.free)
        }
    }
}

private struct SidebarItem: View {
    var section: Section
    var isOn: Bool
    var namespace: Namespace.ID
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .regular))
                    .frame(width: 20)
                    .foregroundStyle(isOn ? .white : Theme.secondary)
                Text(LocalizedStringKey(section.rawValue)).font(.system(size: 13.5, weight: isOn ? .medium : .regular))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .foregroundStyle(isOn ? .white : Theme.secondary)
            .background {
                if isOn {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                } else if hover {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04))
                }
            }
            .animation(.easeOut(duration: 0.15), value: hover)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
