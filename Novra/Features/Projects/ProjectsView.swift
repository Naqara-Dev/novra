import SwiftUI

struct ProjectsView: View {
    @Bindable var model: ProjectsModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Projects",
                           subtitle: "Dependencies and build output in your code projects. All of it comes back with one install or build.") {
                    Button { model.scan() } label: {
                        Label(model.hasScanned ? "Scan Again" : "Find Projects", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(PillButtonStyle(prominent: !model.hasScanned))
                    .disabled(model.isScanning)
                }
                .reveal()
                if model.hasScanned && !model.isScanning && !model.projects.isEmpty {
                    HStack(spacing: 12) {
                        PillPicker(options: ProjectsModel.Age.allCases, selection: $model.age) { String(localized: String.LocalizationValue($0.label)) }
                        Spacer()
                        Text("\(model.visible.count) projects · \(model.visibleSize.byteString)")
                            .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.secondary)
                            .contentTransition(.numericText())
                        Button("Select these") { model.selectVisible() }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if let report = model.report {
                    CleanResultBanner(report: report, onEmptyTrash: { model.emptyTrash() },
                                      onDismiss: { withAnimation { model.report = nil } })
                }
            }
            .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 12)

            content
            if model.hasScanned && !model.isScanning && !model.projects.isEmpty {
                SelectionBar(count: model.selection.count, size: model.selectionSize) { confirming = true }
            }
        }
        .animation(.snappy, value: model.age)
        .sheet(isPresented: $confirming) {
            ConfirmRemovalSheet(title: "Remove build files?", count: model.selection.count, size: model.selectionSize,
                                note: "Your source code stays. Everything here comes back with npm install, pod install or a build. Deleting permanently frees the space right away.",
                                defaultToTrash: false) { model.remove(toTrash: $0) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning {
            VStack(spacing: 20) {
                ZStack {
                    ProgressRing(progress: model.progress, lineWidth: 12, colors: [Color(hex: 0x0EA5A4), Theme.green, Color(hex: 0x9AF5C8)])
                    Text("\(Int(model.progress * 100))%").font(.system(size: 24, weight: .bold, design: .rounded))
                        .contentTransition(.numericText(value: model.progress))
                        .animation(.snappy, value: Int(model.progress * 100))
                }
                .frame(width: 130, height: 130)
                .background { BreathingHalo(color: Color(hex: 0x0EA5A4)).frame(width: 240, height: 240) }
                Text(model.progress < 0.4 ? "Looking for projects…" : "Measuring dependencies…")
                    .font(.system(size: 15, weight: .semibold))
                Text(model.currentPath.isEmpty ? " " : URL(filePath: model.currentPath).tildePath)
                    .font(.system(size: 11.5, design: .monospaced)).foregroundStyle(Theme.tertiary)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 480)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.hasScanned {
            EmptyState(icon: "folder.badge.gearshape", title: "Old projects, heavy folders",
                       message: "node_modules, .next, build, Pods, .venv… Novra finds them in projects you haven't run in a while. Source code is never touched.")
        } else if model.visible.isEmpty {
            EmptyState(icon: "checkmark.seal", title: "Nothing this old",
                       message: "Every project here was used recently. Try a shorter time range.")
        } else {
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(model.visible) { project in
                        ProjectCard(model: model, project: project)
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 16)
            }
        }
    }
}

private struct ProjectCard: View {
    @Bindable var model: ProjectsModel
    var project: ProjectJunk

    private var isOpen: Bool { model.expanded.contains(project.id) }

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    CheckBox(model.state(of: project)) { model.toggle(project) }
                    Image(systemName: "folder.fill").font(.system(size: 20)).foregroundStyle(Color(hex: 0x0EA5A4))
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(project.project.lastPathComponent).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            // Same one-month line the Projects filter starts from.
                            if let used = project.lastUsed, used > .now.addingTimeInterval(-30 * 86_400) {
                                Text("Active \(used.relativeString)").font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(Theme.green)
                                    .padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(Theme.green.opacity(0.14)))
                                    .fixedSize()
                            } else {
                                StaleBadge(date: project.lastUsed ?? .distantPast, always: true)
                            }
                        }
                        Text(project.folders.map(\.url.lastPathComponent).joined(separator: " · ") + "   " + project.project.deletingLastPathComponent().tildePath)
                            .font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    IconButton(systemName: "eye.slash", help: "Ignore this project") { model.ignore(project) }
                    SizeLabel(size: project.size)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.tertiary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(14)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.snappy) {
                        if isOpen { model.expanded.remove(project.id) } else { model.expanded.insert(project.id) }
                    }
                }
                if isOpen {
                    Divider().overlay(Theme.stroke)
                    ForEach(project.folders) { folder in
                        HStack(spacing: 12) {
                            CheckBox(isOn: model.selection.contains(folder.id)) { model.toggle(folder) }
                            FileIcon(url: folder.url, size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.url.lastPathComponent).font(.system(size: 12.5, weight: .medium))
                                Text(ProjectScanner.hint(for: folder.url.lastPathComponent))
                                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                            }
                            Spacer()
                            SizeLabel(size: folder.footprint.size, tint: .white.opacity(0.85))
                            IconButton(systemName: "folder", help: "Show in Finder") { SystemInfo.reveal(folder.url) }
                        }
                        .padding(.horizontal, 14).padding(.leading, 30).padding(.vertical, 7)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    .padding(.bottom, 4)
                }
            }
        }
    }
}
