import SwiftUI

struct ToolkitView: View {
    @Bindable var model: ToolkitModel
    @State private var confirming: Tool?

    private var quickTools: [Tool] {
        Tool.allCases.filter { !$0.hasPage && $0 != .trash && model.available.contains($0) }
    }

    var body: some View {
        ZStack {
            if let tool = model.open {
                page(for: tool)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
            } else {
                grid.transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.88), value: model.open)
        .onAppear { model.refreshFacts() }
        .sheet(isPresented: .init(get: { model.activeRun != nil }, set: { if !$0 { model.activeRun = nil } })) {
            if let run = model.activeRun {
                ToolRunView(run: run) { model.activeRun = nil }
            }
        }
        .confirmationDialog(confirming?.title ?? "", isPresented: .init(get: { confirming != nil }, set: { if !$0 { confirming = nil } })) {
            Button("Run") { if let tool = confirming { model.run(tool) } }
        } message: {
            Text(confirming?.confirmation ?? "")
        }
    }

    @ViewBuilder
    private func page(for tool: Tool) -> some View {
        let back = { model.open = nil }
        switch tool {
        case .spaceLens: SpaceLensView(onBack: back)
        case .memory: MemoryView(onBack: back)
        default: ShredderView(onBack: back)
        }
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "Toolkit", subtitle: "Small fixes and power tools. Each one says what it does before it does it.")
                    .reveal()

                HStack(alignment: .top, spacing: 14) {
                    HeroCard(tool: .spaceLens) { model.open = .spaceLens }
                        .reveal(delay: 0.05)
                    VStack(spacing: 14) {
                        WideCard(tool: .memory, fact: nil, status: .idle) { model.open = .memory }
                            .reveal(delay: 0.1)
                        WideCard(tool: .trash, fact: model.facts[.trash], status: model.state(.trash)) { trigger(.trash) }
                            .reveal(delay: 0.15)
                        WideCard(tool: .shredder, fact: nil, status: .idle) { model.open = .shredder }
                            .reveal(delay: 0.2)
                    }
                }

                ForEach(Array(Tool.Group.allCases.enumerated()), id: \.element) { groupIndex, group in
                    let tools = quickTools.filter { $0.group == group }
                    if !tools.isEmpty {
                        Text(LocalizedStringKey(group.rawValue)).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.secondary)
                            .padding(.top, 6)
                            .reveal(delay: 0.2 + Double(groupIndex) * 0.05)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                            ForEach(Array(tools.enumerated()), id: \.element) { index, tool in
                                ToolCard(tool: tool, fact: model.facts[tool], status: model.state(tool)) { trigger(tool) }
                                    .reveal(delay: 0.25 + Double(groupIndex) * 0.08 + Double(index) * 0.04)
                            }
                        }
                    }
                }
            }
            .padding(28)
        }
    }

    private func trigger(_ tool: Tool) {
        if tool.confirmation != nil { confirming = tool } else { model.run(tool) }
    }
}

// MARK: Cards

private struct HeroCard: View {
    var tool: Tool
    var action: () -> Void
    @State private var hover = false
    @State private var spin = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    ForEach(0..<5, id: \.self) { i in
                        Circle()
                            .trim(from: Double(i) * 0.2, to: Double(i) * 0.2 + 0.17)
                            .stroke(tool.colors[i % 2].opacity(0.9 - Double(i) * 0.12),
                                    style: StrokeStyle(lineWidth: 22, lineCap: .butt))
                            .frame(width: 150, height: 150)
                    }
                    Circle()
                        .trim(from: 0.1, to: 0.35)
                        .stroke(Theme.lavender.opacity(0.6), style: StrokeStyle(lineWidth: 10))
                        .frame(width: 104, height: 104)
                    Image(systemName: "magnifyingglass").font(.system(size: 30, weight: .semibold))
                }
                .rotationEffect(.degrees(spin ? 360 : 0))
                .scaleEffect(hover ? 1.06 : 1)
                .frame(maxWidth: .infinity)
                .padding(.top, 34)
                .padding(.bottom, 30)

                Text(tool.title).font(.system(size: 20, weight: .bold))
                Text(tool.subtitle).font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                HStack(spacing: 6) {
                    Text("Open").font(.system(size: 12.5, weight: .semibold))
                    Image(systemName: "arrow.right").font(.system(size: 11, weight: .bold))
                        .offset(x: hover ? 4 : 0)
                }
                .foregroundStyle(Theme.accent)
                .padding(.top, 14)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [tool.colors[0].opacity(hover ? 0.28 : 0.2), tool.colors[1].opacity(0.08)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(hover ? 0.18 : 0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: hover)
        .onAppear { withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) { spin = true } }
    }
}

private struct WideCard: View {
    var tool: Tool
    var fact: String?
    var status: ToolkitModel.Status
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ToolIcon(tool: tool, size: 46)
                    .scaleEffect(hover ? 1.08 : 1)
                    .rotationEffect(.degrees(hover ? -4 : 0))
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.title).font(.system(size: 14.5, weight: .semibold))
                    Text(tool.subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.secondary).lineLimit(2)
                }
                Spacer(minLength: 8)
                StatusView(status: status, fact: fact, hover: hover, opens: tool.hasPage)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 84)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(hover ? Theme.cardHover : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(hover ? tool.colors[0].opacity(0.4) : Theme.stroke))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: hover)
    }
}

private struct ToolCard: View {
    var tool: Tool
    var fact: String?
    var status: ToolkitModel.Status
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    ToolIcon(tool: tool, size: 44)
                        .scaleEffect(hover ? 1.08 : 1)
                        .rotationEffect(.degrees(hover ? -4 : 0))
                    Spacer()
                    if let fact {
                        Text(fact).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.lavender)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Theme.lavender.opacity(0.12)))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(tool.title).font(.system(size: 14, weight: .semibold))
                    Text(tool.subtitle).font(.system(size: 11.5)).foregroundStyle(Theme.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
                StatusView(status: status, fact: nil, hover: hover, opens: false)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(hover ? Theme.cardHover : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(hover ? tool.colors[0].opacity(0.4) : Theme.stroke))
            .offset(y: hover ? -3 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: hover)
        .animation(.snappy, value: fact)
    }
}

private struct StatusView: View {
    var status: ToolkitModel.Status
    var fact: String?
    var hover: Bool
    var opens: Bool

    var body: some View {
        Group {
            switch status {
            case .running:
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Working…") }
                    .foregroundStyle(Theme.secondary)
            case .done(let text):
                Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.green)
                    .symbolEffect(.bounce, value: text)
            case .failed(let text):
                Label(text, systemImage: "exclamationmark.circle.fill").foregroundStyle(Theme.orange)
            case .idle:
                HStack(spacing: 6) {
                    if let fact { Text(fact).foregroundStyle(Theme.lavender) }
                    Text(opens ? "Open" : "Run").foregroundStyle(Theme.accent)
                    Image(systemName: opens ? "arrow.right" : "play.fill").font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .offset(x: hover ? 3 : 0)
                }
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .lineLimit(1)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
    }
}
