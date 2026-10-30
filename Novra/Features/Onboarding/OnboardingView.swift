import SwiftUI

struct OnboardingView: View {
    var onDone: () -> Void
    @State private var page = 0
    @State private var hasAccess = SystemInfo.hasFullDiskAccess
    @AppStorage(Prefs.Key.menuBarEnabled) private var menuBar = false
    @AppStorage(Prefs.Key.lowDiskAlert) private var lowDiskAlert = false
    @AppStorage(Prefs.Key.checkForUpdates) private var checkForUpdates = true
    private let pages = 4

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch page {
                case 0: welcome
                case 1: promise
                case 2: access
                default: extras
                }
            }
            .id(page)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<pages, id: \.self) { i in
                        Capsule().fill(i == page ? Theme.accent : .white.opacity(0.2))
                            .frame(width: i == page ? 18 : 6, height: 6)
                    }
                }
                Spacer()
                if page > 0 {
                    Button("Back") { withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { page -= 1 } }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
                Button(page == pages - 1 ? "Start Using Novra" : "Continue") {
                    if page == pages - 1 { onDone() } else {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.88)) { page += 1 }
                    }
                }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(24)
        }
        .frame(width: 620, height: 500)
        .background(AmbientBackground())
        .foregroundStyle(.white)
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            if page == 2 { withAnimation { hasAccess = SystemInfo.hasFullDiskAccess } }
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Image("NovraLogo").resizable().frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Theme.accent.opacity(0.4), radius: 24)
                .reveal()
            Text("Welcome to Novra").font(.system(size: 30, weight: .bold)).reveal(delay: 0.1)
            Text("Novra finds it. You decide what goes.")
                .font(.system(size: 16)).foregroundStyle(Theme.lavender).reveal(delay: 0.18)
            Text("Caches, leftovers, old projects, duplicate photos, apps you never open. All in one place, with honest numbers.")
                .font(.system(size: 13)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 420).reveal(delay: 0.26)
        }
        .padding(40)
    }

    private var promise: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How Novra works").font(.system(size: 26, weight: .bold)).reveal()
            point("eye", "You see everything first", "Every file Novra finds is listed with its size and what it's for.", 0.08)
            point("checkmark.shield", "Nothing goes without your OK", "Removing always asks first, and goes to the Trash by default.", 0.16)
            point("info.circle", "You know what happens next", "Each kind of junk tells you what changes after cleaning it.", 0.24)
            point("lock.shield", "Nothing leaves your Mac", "Your files are never uploaded. No analytics, no tracking. The only connection is an optional update check.", 0.32)
        }
        .padding(44)
    }

    private func point(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey, _ delay: Double) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Theme.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
            }
        }
        .reveal(delay: delay)
    }

    private var access: some View {
        VStack(spacing: 18) {
            Image(systemName: hasAccess ? "lock.open.fill" : "lock.shield")
                .font(.system(size: 46)).foregroundStyle(hasAccess ? Theme.green : Theme.lavender)
                .contentTransition(.symbolEffect(.replace))
            Text("Full Disk Access").font(.system(size: 26, weight: .bold))
            Text("Lets Novra look at Safari, Mail, Messages and the Trash, and at apps' sandboxed caches. Without it, Novra still works but finds less.")
                .font(.system(size: 13)).foregroundStyle(Theme.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
            if hasAccess {
                Label("Access granted", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
                    .font(.system(size: 14, weight: .semibold))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    step(1, "Click Open Settings below.")
                    step(2, "Turn on Novra in the list. Use + to add it if it's missing.")
                    step(3, "Come back here. This page updates by itself.")
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
                Button("Open Settings") { SystemInfo.openFullDiskAccessSettings() }
                    .buttonStyle(PillButtonStyle())
            }
        }
        .padding(40)
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(spacing: 10) {
            Text("\(n)").font(.system(size: 12, weight: .bold)).frame(width: 22, height: 22)
                .background(Circle().fill(Theme.accent))
            Text(text).font(.system(size: 12.5))
        }
    }

    private var extras: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("A couple of extras").font(.system(size: 26, weight: .bold)).reveal()
            VStack(spacing: 0) {
                optionRow("Show Novra in the menu bar", "Disk and memory at a glance, with Quick Clean.", isOn: $menuBar)
                Divider().overlay(Theme.stroke)
                optionRow("Warn me when the disk is almost full", "Only while Novra is open. You can change this in Settings.",
                          isOn: $lowDiskAlert)
                Divider().overlay(Theme.stroke)
                optionRow("Check for updates", "Once a day, asks GitHub for the latest version number. Nothing else is sent.",
                          isOn: $checkForUpdates)
            }
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
            .reveal(delay: 0.08)
            .onChange(of: lowDiskAlert) { _, on in if on { LowDiskWatcher.requestPermission() } }
        }
        .padding(44)
    }

    private func optionRow(_ title: LocalizedStringKey, _ detail: LocalizedStringKey, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(Theme.secondary)
            }
            Spacer(minLength: 12)
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
