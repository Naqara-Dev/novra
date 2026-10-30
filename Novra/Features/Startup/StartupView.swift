import SwiftUI

struct StartupView: View {
    @Bindable var model: StartupModel
    @State private var confirming = false

    private var brokenCount: Int { model.items.filter(\.isBroken).count }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(title: "Startup Items",
                               subtitle: "Helpers that start with your Mac and keep running in the background.") {
                        HStack(spacing: 10) {
                            Button("Login Items…") { SystemInfo.openLoginItemsSettings() }
                                .buttonStyle(PillButtonStyle(prominent: false))
                            IconButton(systemName: "arrow.clockwise", help: "Refresh") { model.load() }
                        }
                    }
                    .reveal()

                    if brokenCount > 0 {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(brokenCount) items belong to apps that are gone")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("They try to start at every login and fail. Safe to remove.")
                                    .font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Button("Select them") { withAnimation(.snappy) { model.selectBroken() } }
                                .buttonStyle(PillButtonStyle(prominent: false))
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.orange.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.orange.opacity(0.25)))
                        .reveal(delay: 0.05)
                    }

                    if let report = model.report {
                        CleanResultBanner(report: report, onEmptyTrash: nil, onDismiss: { withAnimation { model.report = nil } })
                    }

                    if model.isLoading {
                        ProgressView().frame(maxWidth: .infinity).padding(40)
                    } else if model.items.isEmpty {
                        EmptyState(icon: "bolt.slash", title: "Nothing starts in the background",
                                   message: "No launch agents or daemons were found.")
                            .frame(height: 300)
                    } else {
                        ForEach(Array([StartupItem.Scope.user, .allUsers, .system, .helper].enumerated()), id: \.element) { index, scope in
                            let list = model.items.filter { $0.scope == scope }
                            if !list.isEmpty { section(scope, list).reveal(delay: 0.1 + Double(index) * 0.06) }
                        }
                    }
                }
                .padding(28)
            }
            SelectionBar(count: model.selection.count, size: 0, actionTitle: "Remove") { confirming = true }
        }
        .onAppear { model.loadIfNeeded() }
        .sheet(isPresented: $confirming) {
            ConfirmRemovalSheet(
                title: "Stop \(model.selection.count) startup items?",
                count: model.selection.count, size: 0,
                note: "They stop launching automatically. The apps themselves stay installed. Items for all users need your password.",
                allowTrashChoice: false
            ) { _ in model.removeSelection() }
        }
    }

    private func section(_ scope: StartupItem.Scope, _ list: [StartupItem]) -> some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CheckBox(model.state(of: list)) { model.toggle(list) }
                    Text(LocalizedStringKey(scope.rawValue)).font(.system(size: 13.5, weight: .semibold))
                    Spacer()
                    Text("\(list.count)").foregroundStyle(Theme.tertiary).font(.system(size: 12))
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                Divider().overlay(Theme.stroke)
                ForEach(list) { item in
                    StartupRow(item: item, isOn: model.selection.contains(item.id)) { model.toggle([item]) }
                }
            }
            .padding(.bottom, 4)
        }
    }
}

private struct StartupRow: View {
    var item: StartupItem
    var isOn: Bool
    var onToggle: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            CheckBox(isOn: isOn, action: onToggle)
            if let app = item.appURL, FileManager.default.fileExists(atPath: app.path) {
                FileIcon(url: app, size: 28)
            } else {
                Image(systemName: "gearshape.2").font(.system(size: 15)).foregroundStyle(Theme.lavender)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.06)))
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.appName ?? item.label).font(.system(size: 13)).lineLimit(1)
                    if item.isBroken {
                        InsightBadge(insight: Insight(label: "App is gone", tone: .unused))
                    }
                }
                Text(item.label).font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            IconButton(systemName: "folder", help: "Show in Finder") { SystemInfo.reveal(item.plist) }
                .opacity(hover ? 1 : 0.5)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(isOn ? Theme.accent.opacity(0.08) : hover ? Color.white.opacity(0.03) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onToggle)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.15), value: isOn)
    }
}
