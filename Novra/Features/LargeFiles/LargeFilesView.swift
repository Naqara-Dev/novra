import SwiftUI

struct LargeFilesView: View {
    @Bindable var model: LargeFilesModel
    @State private var confirming = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Large Files", subtitle: "The biggest files in your home folder, biggest first.") {
                    HStack(spacing: 10) {
                        PillPicker(options: LargeFilesModel.thresholds, selection: $model.minSize) { "≥ " + $0.byteString }
                        Button { model.scan() } label: {
                            Label(model.hasScanned ? "Scan Again" : "Scan", systemImage: "magnifyingglass")
                        }
                        .buttonStyle(PillButtonStyle(prominent: !model.hasScanned))
                        .disabled(model.isScanning)
                    }
                }
                if model.hasScanned && !model.isScanning {
                    HStack(spacing: 8) {
                        PillPicker(options: LargeFile.Kind.allCases, selection: $model.filter) { String(localized: String.LocalizationValue($0.rawValue)) }
                        Spacer()
                        CheckToggle(title: Prefs.staleLabel, isOn: $model.onlyOld)
                    }
                }
                if let report = model.report {
                    CleanResultBanner(report: report, onEmptyTrash: { model.emptyTrash() }, onDismiss: { model.report = nil })
                }
            }
            .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 12)

            content
            if model.hasScanned {
                SelectionBar(count: model.selection.count, size: model.selectionSize) { confirming = true }
            }
        }
        .sheet(isPresented: $confirming) {
            ConfirmRemovalSheet(title: "Remove selected files?", count: model.selection.count,
                                size: model.selectionSize, note: nil) { model.remove(toTrash: $0) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning {
            VStack(spacing: 18) {
                SpinningRing(lineWidth: 10).frame(width: 90, height: 90)
                Text(model.currentPath.isEmpty ? " " : URL(filePath: model.currentPath).tildePath)
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.tertiary)
                    .lineLimit(1).truncationMode(.middle).frame(maxWidth: 520)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.hasScanned {
            EmptyState(icon: "doc.viewfinder", title: "Find what's taking space",
                       message: "Novra looks through your home folder for big files: forgotten videos, old disk images, archives you already unpacked.")
        } else if model.visible.isEmpty {
            EmptyState(icon: "checkmark.seal", title: "Nothing here", message: "No files match this filter.")
        } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(model.visible.enumerated()), id: \.element.id) { index, file in
                        HStack(spacing: 12) {
                            CheckBox(isOn: model.selection.contains(file.id)) { model.toggle(file) }
                            FileIcon(url: file.url, size: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(file.url.lastPathComponent).font(.system(size: 13)).lineLimit(1)
                                    StaleBadge(date: file.modified)
                                }
                                Text(file.url.deletingLastPathComponent().tildePath)
                                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary).lineLimit(1).truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            SizeLabel(size: file.size)
                            IconButton(systemName: "folder", help: "Show in Finder") { SystemInfo.reveal(file.url) }
                            IconButton(systemName: "eye.slash", help: "Ignore: never show this again") { model.ignore(file) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card.opacity(0.6)))
                        .reveal(index: index, step: 0.02)
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 16)
            }
        }
    }
}
