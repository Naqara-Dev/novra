import SwiftUI

struct AppsView: View {
    @Bindable var model: AppsModel
    @State private var confirming = false
    @State private var exploring: URL?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                appList
                    .frame(width: 330)
                    .background(Color.black.opacity(0.12))
                Rectangle().fill(Theme.stroke).frame(width: 1)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            SelectionBar(count: model.selection.count, size: model.selectionSize) { confirming = true }
        }
        .onAppear { model.loadIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshRunning()
        }
        .sheet(isPresented: $confirming) {
            ConfirmRemovalSheet(
                title: "Remove selected files?",
                count: model.selection.count,
                size: model.selectionSize,
                note: "Apps that are open will be quit first."
            ) { model.removeSelection(toTrash: $0) }
        }
        .sheet(item: $exploring) { url in
            FolderExplorer(root: url) { model.remeasure(url) }
        }
    }

    // MARK: List

    private var appList: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.tertiary)
                TextField("Search apps", text: $model.search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.stroke))

            VStack(alignment: .leading, spacing: 10) {
                PillPicker(options: AppsModel.Sort.allCases, selection: $model.sort) { String(localized: String.LocalizationValue($0.rawValue)) }
                CheckToggle(title: Prefs.staleLabel, isOn: $model.onlyUnused)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if model.isLoading {
                Spacer()
                ProgressView("Finding your apps…").controlSize(.small).foregroundStyle(Theme.secondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if !model.orphans.isEmpty && model.search.isEmpty {
                            leftoversRow
                        }
                        ForEach(model.visibleApps) { app in
                            AppRow(app: app, total: model.total(for: app),
                                   isRunning: model.isRunning(app), lastActivity: model.lastActivity(app),
                                   state: model.state(of: model.items(for: app)),
                                   isFocused: model.focusedID == app.id,
                                   onToggle: { model.toggle(model.items(for: app)) })
                                .onTapGesture { withAnimation(.snappy) { model.focusedID = app.id } }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(16)
    }

    private var leftoversRow: some View {
        HStack(spacing: 12) {
            CheckBox(model.state(of: model.orphans)) { model.toggle(model.orphans) }
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: 15)).foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(Theme.orange.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text("Leftovers").font(.system(size: 13.5, weight: .semibold))
                Text("From apps that are gone").font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }
            Spacer()
            SizeLabel(size: model.total(model.orphans))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(model.focusedID == AppsModel.leftoversID ? Theme.cardHover : .clear))
        .contentShape(Rectangle())
        .onTapGesture { model.focusedID = AppsModel.leftoversID }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if model.focusedID == AppsModel.leftoversID {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PageHeader(title: "Leftovers",
                               subtitle: "Settings, caches and data from apps no longer on this Mac.")
                    reportBanner
                    groupedItems(model.orphans)
                }
                .padding(28)
            }
        } else if let app = model.focusedApp {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    appHeader(app).reveal()
                    reportBanner
                    groupedItems(model.items(for: app))
                    if model.items(for: app).contains(where: \.cautious) {
                        Label("Folders marked “Shared” may be used by other tools or hold your own work, so Uninstall leaves them unticked.",
                              systemImage: "info.circle")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                    }
                }
                .padding(28)
            }
        } else if !model.isLoading {
            EmptyState(icon: "app.dashed", title: "Pick an app", message: "See everything it keeps on your Mac, and look inside the big folders.")
        }
    }

    @ViewBuilder
    private var reportBanner: some View {
        if let report = model.report {
            CleanResultBanner(report: report, onEmptyTrash: { model.emptyTrash() }, onDismiss: { model.report = nil })
        }
    }

    private func appHeader(_ app: InstalledApp) -> some View {
        HStack(alignment: .center, spacing: 18) {
            FileIcon(url: app.url, size: 72)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name).font(.system(size: 24, weight: .bold))
                Text([app.version.map { "Version \($0)" }, app.bundleID].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(Theme.tertiary)
                HStack(spacing: 8) {
                    if model.isRunning(app) {
                        RunningBadge()
                    } else if let used = model.lastActivity(app) {
                        Text("Last active \(used.relativeString)")
                            .foregroundStyle(used.isStale ? Theme.orange : Theme.secondary)
                    } else {
                        Text("Last active: unknown").foregroundStyle(Theme.tertiary)
                    }
                }
                .font(.system(size: 12.5, weight: .medium))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 10) {
                Group {
                    if let total = model.total(for: app) {
                        Text(total.byteString)
                    } else {
                        Text("Measuring…").foregroundStyle(Theme.tertiary)
                    }
                }
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.orange)
                Button {
                    model.selectForUninstall(app)
                    confirming = true
                } label: { Label("Uninstall", systemImage: "trash") }
                    .buttonStyle(AccentButtonStyle(tint: Theme.red))
            }
        }
    }

    private func groupedItems(_ items: [RelatedItem]) -> some View {
        VStack(spacing: 14) {
            ForEach(Array(RelatedKind.allCases.enumerated()), id: \.element) { index, kind in
                let group = items.filter { $0.kind == kind }
                    .sorted { (model.footprints[$0.id]?.size ?? 0) > (model.footprints[$1.id]?.size ?? 0) }
                if !group.isEmpty {
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                CheckBox(model.state(of: group)) { model.toggle(group) }
                                Image(systemName: kind.icon).foregroundStyle(Theme.lavender).frame(width: 20)
                                Text(kind.title).font(.system(size: 13.5, weight: .semibold))
                                Spacer()
                                SizeLabel(size: model.total(group))
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)
                            Divider().overlay(Theme.stroke)
                            ForEach(group) { item in
                                RelatedRow(item: item, footprint: model.footprints[item.id],
                                           isOn: model.selection.contains(item.id),
                                           onToggle: { model.toggle([item]) },
                                           onExplore: { exploring = item.url })
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .reveal(delay: 0.05 + Double(index) * 0.05)
                }
            }
        }
        .id(model.focusedID)
    }
}

private struct AppRow: View {
    var app: InstalledApp
    var total: Int64?
    var isRunning: Bool
    var lastActivity: Date?
    var state: CheckState
    var isFocused: Bool
    var onToggle: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            CheckBox(state, action: onToggle)
            FileIcon(url: app.url, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                Group {
                    if isRunning {
                        Label("Running", systemImage: "circle.fill").labelStyle(.titleOnly).foregroundStyle(Theme.green)
                    } else if let used = lastActivity {
                        Text("Active \(used.relativeString)").foregroundStyle(used.isStale ? Theme.orange.opacity(0.9) : Theme.tertiary)
                    } else {
                        Text(app.bundleID).foregroundStyle(Theme.tertiary)
                    }
                }
                .font(.system(size: 11)).lineLimit(1)
            }
            Spacer()
            SizeLabel(size: total, tint: .white.opacity(0.9))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(isFocused ? Theme.cardHover : hover ? Theme.card : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

private struct RelatedRow: View {
    var item: RelatedItem
    var footprint: Footprint?
    var isOn: Bool
    var onToggle: () -> Void
    var onExplore: () -> Void

    private var isFolder: Bool { item.isFolder }

    var body: some View {
        HStack(spacing: 12) {
            CheckBox(isOn: isOn, action: onToggle)
            FileIcon(url: item.url, size: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.url.lastPathComponent).font(.system(size: 13)).lineLimit(1).truncationMode(.middle)
                        .layoutPriority(1)
                    if item.cautious {
                        Text("Shared").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.lavender)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Theme.lavender.opacity(0.14)))
                    }
                    // An app's own files never change when you use it, so only data folders get this badge.
                    if item.kind != .bundle { UsageBadge(url: item.url, lastUsed: footprint?.lastUsed) }
                }
                Text(PathHints.hint(for: item.url) ?? item.url.deletingLastPathComponent().tildePath)
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SizeLabel(size: footprint?.size, tint: .white.opacity(0.85))
            if isFolder {
                Button(action: onExplore) {
                    Label("Look inside", systemImage: "arrow.down.right.and.arrow.up.left")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .help("Browse this folder and pick what to remove")
            }
            IconButton(systemName: "folder", help: "Show in Finder") { SystemInfo.reveal(item.url) }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { path }
}
