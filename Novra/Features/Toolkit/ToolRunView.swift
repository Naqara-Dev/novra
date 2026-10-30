import SwiftUI

/// Shows what a tool is doing, line by line, and what it changed.
struct ToolRunView: View {
    var run: ToolkitModel.Run
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                ToolIcon(tool: run.tool, size: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.tool.title).font(.system(size: 17, weight: .bold))
                    statusLine
                }
                Spacer()
                if run.freed > 0 {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(run.freed.byteString).font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.green)
                        Text("freed").font(.system(size: 11)).foregroundStyle(Theme.secondary)
                    }
                    .transition(.scale.combined(with: .opacity))
                }
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(run.lines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(line.hasPrefix("$ ") ? Theme.lavender : index == 0 ? Theme.secondary : .white.opacity(0.85))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(14)
                }
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.stroke))
                .onChange(of: run.lines.count) { _, count in
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }

            HStack {
                Text(run.status == .running ? "You can close this; the tool keeps running." : "Saved to History.")
                    .font(.system(size: 11.5)).foregroundStyle(Theme.tertiary)
                Spacer()
                Button(run.status == .running ? "Hide" : "Done", action: onClose)
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 460)
        .background(Color(hex: 0x0D1434))
        .foregroundStyle(.white)
        .animation(.snappy, value: run.freed)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch run.status {
        case .running:
            HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Working…") }
                .font(.system(size: 12.5)).foregroundStyle(Theme.secondary)
        case .done(let text):
            Label(text, systemImage: "checkmark.circle.fill").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.green)
        case .failed(let text):
            Label(text, systemImage: "exclamationmark.circle.fill").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Theme.orange)
        case .idle:
            EmptyView()
        }
    }
}
