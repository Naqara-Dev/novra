import SwiftUI

/// Photo or video thumbnail, loaded off the main thread and cached.
struct PhotoThumb: View {
    var item: PhotoItem
    var maxPixel = 300
    @State private var image: NSImage?

    private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        ZStack {
            Rectangle().fill(.white.opacity(0.05))
            if let image {
                Image(nsImage: image).resizable().scaledToFill().transition(.opacity)
            } else {
                ProgressView().controlSize(.small)
            }
            if item.isVideo {
                Image(systemName: "play.circle.fill").font(.system(size: 22)).foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 4)
            }
        }
        .clipped()
        .task(id: "\(item.id)|\(maxPixel)") {
            let key = "\(maxPixel)|\(item.id)" as NSString
            if let cached = Self.cache.object(forKey: key) { image = cached; return }
            let target = item, size = maxPixel
            let cg = await Task.detached(priority: .userInitiated) { PhotoAnalyzer.thumbnail(for: target, maxPixel: size) }.value
            guard let cg else { return }
            let loaded = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            Self.cache.setObject(loaded, forKey: key)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}

struct PhotosView: View {
    @Bindable var model: PhotosModel
    @State private var confirming = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    PageHeader(title: "Photos", subtitle: "Similar, blurry and dark shots, screenshots and big videos. Novra keeps your best shot and offers the rest.") {
                        HStack(spacing: 10) {
                            PillPicker(options: PhotosModel.Source.allCases, selection: $model.source) { String(localized: String.LocalizationValue($0.rawValue)) }
                                .disabled(model.isScanning)
                            Button { model.scan() } label: {
                                Label(model.hasScanned ? "Scan Again" : "Scan", systemImage: "magnifyingglass")
                            }
                            .buttonStyle(PillButtonStyle(prominent: !model.hasScanned))
                            .disabled(model.isScanning)
                        }
                    }
                    .reveal()
                    if let message = model.message {
                        Label(message, systemImage: "info.circle").font(.system(size: 12.5)).foregroundStyle(Theme.lavender)
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 28).padding(.top, 26).padding(.bottom, 12)

                content
                if model.hasScanned && !model.isScanning {
                    SelectionBar(count: model.selection.count, size: model.selectionSize) { confirming = true }
                }
            }
            if let deck = model.swipe {
                SwipeView(items: deck) { model.finishSwipe(delete: $0) }
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.swipe != nil)
        .sheet(isPresented: $confirming) {
            ConfirmRemovalSheet(title: "Remove selected photos?", count: model.selection.count, size: model.selectionSize,
                                note: model.source == .library
                                    ? LocalizedStringKey("Photos go to Recently Deleted in the Photos app for 30 days. macOS will ask you to confirm.")
                                    : nil,
                                allowTrashChoice: model.source == .folders) { _ in model.remove() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.denied {
            EmptyState(icon: "photo.badge.exclamationmark", title: "Novra can't see your photos",
                       message: "Allow access in System Settings › Privacy & Security › Photos, or scan folders instead.")
        } else if model.isScanning {
            VStack(spacing: 20) {
                ZStack {
                    ProgressRing(progress: model.progress, lineWidth: 12, colors: [Theme.purple, Theme.accent, Theme.lavender])
                    Text("\(Int(model.progress * 100))%").font(.system(size: 24, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .frame(width: 130, height: 130)
                .background { BreathingHalo(color: Theme.purple).frame(width: 240, height: 240) }
                Text(model.phase).font(.system(size: 15, weight: .semibold))
                Text("Everything is analysed on this Mac.").font(.system(size: 12)).foregroundStyle(Theme.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.hasScanned {
            EmptyState(icon: "photo.stack", title: "Clean up your photos",
                       message: "Finds near-duplicates and keeps the sharpest, plus blurry and dark shots, screenshots and videos you could shrink.")
        } else if model.allItems.isEmpty {
            EmptyState(icon: "checkmark.seal", title: "Your photos look tidy", message: "No duplicates, blurry or dark shots found.")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(Array(PhotosModel.Section.allCases.enumerated()), id: \.element) { index, section in
                        let items = model.items(in: section)
                        if !items.isEmpty {
                            sectionCard(section, items).reveal(delay: Double(index) * 0.05)
                        }
                    }
                }
                .padding(.horizontal, 28).padding(.bottom, 16)
            }
        }
    }

    private func sectionCard(_ section: PhotosModel.Section, _ items: [PhotoItem]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text(LocalizedStringKey(section.rawValue)).font(.system(size: 15, weight: .semibold))
                    Text("\(items.count) · \(items.map(\.size).sum.byteString)")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondary)
                    Spacer()
                    if section != .videos {
                        Button { model.startSwipe(section) } label: { Label("Swipe to Clean", systemImage: "hand.draw") }
                            .buttonStyle(PillButtonStyle(prominent: false))
                    }
                    Button(section == .similar ? "Select extras" : "Select all") { model.selectAll(section) }
                        .buttonStyle(PillButtonStyle(prominent: false))
                }
                if section == .similar {
                    ForEach(model.report.similar.prefix(40), id: \.first?.id) { group in
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(Array(group.enumerated()), id: \.element.id) { index, item in
                                    tile(item, best: index == 0)
                                }
                            }
                        }
                        .scrollIndicators(.never)
                    }
                    if model.report.similar.count > 40 {
                        Text("and \(model.report.similar.count - 40) more groups. Use Swipe to Clean or Select extras.")
                            .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                    }
                } else if section == .videos {
                    ForEach(items.prefix(30)) { video in videoRow(video) }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                        ForEach(items.prefix(120)) { tile($0, best: false) }
                    }
                    if items.count > 120 {
                        Text("and \(items.count - 120) more").font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                    }
                }
            }
        }
    }

    private func tile(_ item: PhotoItem, best: Bool) -> some View {
        let isOn = model.selection.contains(item.id)
        return PhotoThumb(item: item)
            .frame(width: 110, height: 110)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isOn ? Theme.accent : best ? Theme.green.opacity(0.8) : .clear, lineWidth: 2))
            .overlay(alignment: .topLeading) {
                CheckBox(isOn: isOn) { model.toggle(item) }.padding(7)
            }
            .overlay(alignment: .bottomLeading) {
                if best {
                    Label("Best", systemImage: "star.fill").font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.green)).padding(6)
                }
            }
            .opacity(isOn ? 0.75 : 1)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.snappy) { model.toggle(item) } }
            .help(item.name)
    }

    private func videoRow(_ video: PhotoItem) -> some View {
        let compressor = VideoCompressor.shared
        return HStack(spacing: 12) {
            CheckBox(isOn: model.selection.contains(video.id)) { model.toggle(video) }
            PhotoThumb(item: video, maxPixel: 160).frame(width: 64, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(video.name).font(.system(size: 13)).lineLimit(1)
                Text([video.duration > 0 ? Duration.seconds(video.duration).formatted(.time(pattern: .minuteSecond)) : nil,
                      video.date?.formatted(date: .abbreviated, time: .omitted)].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(Theme.tertiary)
            }
            Spacer()
            if let progress = compressor.progress[video.id] {
                ProgressView(value: progress).frame(width: 90)
            } else if let result = compressor.results[video.id] {
                Text(result).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Theme.green)
            } else {
                Button("Compress") { compressor.compress(video) { model.replace(video, withSize: $0) } }
                    .buttonStyle(PillButtonStyle(prominent: false))
                    .help("Re-encode as HEVC 1080p. The original goes to the Trash or Recently Deleted.")
            }
            SizeLabel(size: video.size)
        }
        .padding(.vertical, 4)
    }
}
