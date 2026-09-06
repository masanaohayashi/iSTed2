import SwiftUI
import STedPlayback

@main
struct STedApplication: App {
    @StateObject private var engine = PlaybackEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
                .task {
                    do {
                        try await engine.prepareAudio()
                    } catch {
                        engine.reportAudioError(error)
                    }
                    if ProcessInfo.processInfo.arguments.contains("--demo") {
                        do {
                            try engine.loadDemo()
                        } catch {
                            engine.reportError(error)
                        }
                    }
                }
        }
        .commands { TrackerHistoryCommands(engine: engine) }
    }
}

struct TrackerHistoryActions {
    var undo: () -> Void
    var redo: () -> Void
    var hasDraft: Bool
    var copy: () -> Void
    var cut: () -> Void
    var paste: () -> Void
    var hasSelection: Bool
    var canPaste: Bool
}
private struct TrackerHistoryKey: FocusedValueKey {
    typealias Value = TrackerHistoryActions
}
extension FocusedValues {
    var trackerHistory: TrackerHistoryActions? {
        get { self[TrackerHistoryKey.self] }
        set { self[TrackerHistoryKey.self] = newValue }
    }
}
private struct TrackerHistoryCommands: Commands {
    @ObservedObject var engine: PlaybackEngine
    @FocusedValue(\.trackerHistory) private var actions
    var body: some Commands {
        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { actions?.cut() }
                .keyboardShortcut("x", modifiers: .command)
                .disabled(actions?.hasSelection != true)
            Button("Copy") { actions?.copy() }
                .keyboardShortcut("c", modifiers: .command)
                .disabled(actions?.hasSelection != true)
            Button("Paste") { actions?.paste() }
                .keyboardShortcut("v", modifiers: .command)
                .disabled(actions?.canPaste != true)
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") {
                if let actions { actions.undo() } else { engine.undo() }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!engine.canUndo && actions?.hasDraft != true)
            Button("Redo") {
                if let actions { actions.redo() } else { engine.redo() }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!engine.canRedo)
        }
    }
}
