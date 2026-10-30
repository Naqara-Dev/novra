import SwiftUI

struct DuplicatesView: View {
    @Bindable var model: DuplicatesModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Duplicates",
                           subtitle: model.hasScanned && !model.isScanning
                               ? "\(model.groups.count) sets of identical files · \(model.wasted.byteString) in extra copies"
                               : "Byte-for-byte identical files. Novra keeps the oldest copy of each.") {
                    Button { model.scan() } label: {
                        Label(model.hasScanned ? "Scan Again" : "Find Duplicates", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(PillButtonStyle(prominent: !model.hasScanned))
                    .disabled(model.isScanning || model.folders.isEmpty)
                }
                folderChips
                if let report = model.report {
                    CleanResultBanner(report: report, onEmptyTrash: { model.emptyTrash() }, onDismiss: { model.report = nil })
                }
            }
            .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 12)

            content
            if model.hasScanned && !model.isScanning && !model.groups.isEmpty {
                SelectionBar(count: model.selection.count, size: model.selectionSize) { confirming = true }
            }
        }
        .sheet(isPresented: $confirming) {
            ConfirmRemovalSheet(title: "Remove extra copies?", count: model.selection.count,
                                size: model.selectionSize, note: "One copy of every file always stays.") { model.remove(toTrash: $0) }
        }
    }

    private var folderChips: some View {
        HStack(spacing: 8) {
            ForEach(model.folders, id: \.self) { folder in
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill").font(.system(size: 10)).foregroundStyle(Theme.lavender)
                    Text(folder.lastPathComponent).font(.system(size: 12))
                    Button { model.folders.removeAll { $0 == folder } } label: {
                        Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.tertiary)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Theme.card))
                .overlay(Capsule().strokeBorder(Theme.stroke))
            }
            Button { model.addFolder() } label: { Label("Add Folder", systemImage: "plus") }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.accent)
            Spacer()
        }
        .disabled(model.isScanning)
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning {
            VStack(spacing: 18) {
                ZStack {
                    ProgressRing(progress: model.progress, lineWidth: 10)
                    Text("\(Int(model.progress * 100))%").font(.system(size: 20, weight: .bold, design: .rounded))
                }
                .frame(width: 100, height: 100)
                Text(model.currentPath.isEmpty ? " " : URL(filePath: model.currentPath).tildePath)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.tertiary)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 520)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.hasScanned {
            EmptyState(icon: "doc.on.doc", title: "Same file, saved twice",
                       message: "Downloads twice, copies of copies, photos exported again. Novra compares content, not names.")
        } else if model.groups.isEmpty {
            EmptyState(icon: "checkmark.seal", title: "No duplicates", message: "Every file in these folders is one of a kind.")
        } else {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(model.groups) { group in
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                HStack {
                                    Text("\(group.files.count) copies of \(group.files[0].url.lastPathComponent)")
                                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Spacer()
                                    Text("\(group.wasted.byteString) extra").font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.orange)
                                }
                                .padding(.horizontal, 16).padding(.vertical, 11)
                                Divider().overlay(Theme.stroke)
                                ForEach(group.files) { file in
                                    HStack(spacing: 12) {
                                        CheckBox(isOn: model.selection.contains(file.id)) { model.toggle(file, in: group) }
                                        FileIcon(url: file.url, size: 24)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(file.url.lastPathComponent).font(.system(size: 12.5)).lineLimit(1)
                                            Text(file.url.deletingLastPathComponent().tildePath)
                                                .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
                                                .lineLimit(1).truncationMode(.middle)
                                        }
                                        if file.id == group.files[0].id {
                                            Text("Original").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.green)
                                                .padding(.horizontal, 6).padding(.vertical, 1)
                                                .background(Capsule().fill(Theme.green.opacity(0.14)))
                                        }
                                        Spacer()
                                        SizeLabel(size: file.size, tint: .white.opacity(0.85))
                                        IconButton(systemName: "folder", help: "Show in Finder") { SystemInfo.reveal(file.url) }
                                    }
                                    .padding(.horizontal, 16).padding(.vertical, 7)
                                }
                            }
                            .padding(.bottom, 4)
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 16)
            }
        }
    }
}
