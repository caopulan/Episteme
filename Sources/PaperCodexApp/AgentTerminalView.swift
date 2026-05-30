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
        AgentTerminalNativePanelView(
            state: state,
            runtimeProfiles: model.agentRuntimeProfiles,
            selectedRuntimeID: model.selectedChatRuntimeID,
            selectedRuntimeDisplayName: model.selectedChatRuntimeDisplayName,
            canLaunch: canLaunch,
            inputDraft: $terminalInputDraft,
            requestedColumns: $requestedColumns,
            requestedRows: $requestedRows,
            onSelectRuntime: { model.setSelectedChatRuntimeID($0) },
            onStart: { columns, rows in
                Task {
                    await model.startAgentTerminal(columns: columns, rows: rows)
                }
            },
            onStop: { model.stopAgentTerminal() },
            onResize: { columns, rows in model.resizeAgentTerminal(columns: columns, rows: rows) },
            onSend: { input in model.sendAgentTerminalInput(input) }
        )
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            model.resizeAgentTerminal(columns: requestedColumns, rows: requestedRows)
        }
    }
}
