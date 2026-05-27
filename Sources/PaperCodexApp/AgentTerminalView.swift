import PaperCodexCore
import SwiftUI

struct AgentTerminalView: View {
    @EnvironmentObject private var model: AppModel
    @State private var terminalInputDraft = ""
    @State private var requestedColumns = 120
    @State private var requestedRows = 32

    private var state: AgentTerminalState? {
        model.agentTerminalState(for: model.selectedSession?.id)
    }

    private var canLaunch: Bool {
        model.selectedSession != nil && model.selectedChatRuntimeSupportsPTY
    }

    var body: some View {
        VStack(spacing: 0) {
            terminalToolbar
            Divider()
            AgentTerminalOutputView(output: state?.output ?? "")
            Divider()
            inputBar
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            resizeAgentTerminal()
        }
    }

    private var terminalToolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: state?.isRunning == true ? "terminal.fill" : "terminal")
                .foregroundStyle(state?.isRunning == true ? .green : .secondary)

            Menu {
                ForEach(model.agentRuntimeProfiles.filter(\.supportsPTY)) { profile in
                    Button {
                        model.setSelectedChatRuntimeID(profile.id)
                    } label: {
                        if profile.id == model.selectedChatRuntimeID {
                            Label(profile.displayName, systemImage: "checkmark")
                        } else {
                            Text(profile.displayName)
                        }
                    }
                    .disabled(state?.isRunning == true)
                }
            } label: {
                Label(state?.runtimeName ?? model.selectedChatRuntimeDisplayName, systemImage: "cpu")
                    .labelStyle(.titleAndIcon)
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Agent Runtime")

            if let state {
                Text(state.isRunning ? "Running" : "Stopped")
                    .font(.caption)
                    .foregroundStyle(state.isRunning ? .green : .secondary)
                Text(state.logPath)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(state.logPath)
            } else if !model.selectedChatRuntimeSupportsPTY {
                Text("Terminal unavailable")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Spacer()

            Stepper("Cols \(requestedColumns)", value: $requestedColumns, in: 80...220, step: 10)
                .labelsHidden()
                .help("Columns")
            Text("\(requestedColumns)x\(requestedRows)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)
            Stepper("Rows \(requestedRows)", value: $requestedRows, in: 20...80, step: 4)
                .labelsHidden()
                .help("Rows")
            Button(action: resizeAgentTerminal) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(state?.isRunning != true)
            .help("Resize Terminal")

            if state?.isRunning == true {
                Button(role: .destructive, action: stopAgentTerminal) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Stop Terminal")
            } else {
                Button(action: startAgentTerminal) {
                    Image(systemName: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canLaunch)
                .help("Start Terminal")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .onChange(of: requestedColumns) { _, _ in resizeAgentTerminal() }
        .onChange(of: requestedRows) { _, _ in resizeAgentTerminal() }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Terminal input", text: $terminalInputDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .font(.system(.body, design: .monospaced))
                .disabled(state?.isRunning != true)
                .onSubmit(sendAgentTerminalInput)

            Button(action: sendAgentTerminalInput) {
                Image(systemName: "arrow.turn.down.left")
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .buttonStyle(.borderedProminent)
            .disabled(state?.isRunning != true || terminalInputDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("Send Input")
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func startAgentTerminal() {
        Task {
            await model.startAgentTerminal(columns: requestedColumns, rows: requestedRows)
        }
    }

    private func sendAgentTerminalInput() {
        let trimmed = terminalInputDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        model.sendAgentTerminalInput(terminalInputDraft)
        terminalInputDraft = ""
    }

    private func resizeAgentTerminal() {
        model.resizeAgentTerminal(columns: requestedColumns, rows: requestedRows)
    }

    private func stopAgentTerminal() {
        model.stopAgentTerminal()
    }
}

struct AgentTerminalOutputView: View {
    var output: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(visibleOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
                Color.clear
                    .frame(height: 1)
                    .id("terminal-bottom")
            }
            .background(Color(nsColor: .textBackgroundColor))
            .onChange(of: output) { _, _ in
                DispatchQueue.main.async {
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    proxy.scrollTo("terminal-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var visibleOutput: String {
        output.isEmpty ? " " : output
    }
}
