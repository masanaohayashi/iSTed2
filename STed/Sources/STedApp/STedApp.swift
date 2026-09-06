import SwiftUI
import STedPlayback
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
#endif

@main
struct STedApplication: App {
    @StateObject private var engine = PlaybackEngine()
#if os(macOS)
    @NSApplicationDelegateAdaptor(STedApplicationDelegate.self) private var appDelegate
#endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
#if os(macOS)
                .onAppear { appDelegate.engine = engine }
#endif
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
        .commands {
            TrackerFileCommands(engine: engine)
            TrackerHistoryCommands(engine: engine)
        }
    }
}

#if os(macOS)
@MainActor
private final class STedApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var engine: PlaybackEngine?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let engine, engine.isDirty else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "変更を保存しますか？"
        alert.informativeText = "保存していない変更があります。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "キャンセル")
        alert.addButton(withTitle: "いいえ")
        alert.addButton(withTitle: "はい")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return .terminateCancel
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            if let currentFileURL = engine.currentFileURL {
                do {
                    try engine.save(to: currentFileURL)
                    return .terminateNow
                } catch {
                    engine.reportError(error)
                    return .terminateCancel
                }
            }

            let panel = NSSavePanel()
            panel.canCreateDirectories = true
            panel.allowedContentTypes = [.data]
            panel.nameFieldStringValue = engine.exportFileName
            guard panel.runModal() == .OK, let url = panel.url else {
                return .terminateCancel
            }
            do {
                try engine.save(to: url)
                return .terminateNow
            } catch {
                engine.reportError(error)
                return .terminateCancel
            }
        }
    }
}
#endif

private struct TrackerFileCommands: Commands {
    @ObservedObject var engine: PlaybackEngine

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("新規プロジェクト") {
                engine.requestFileOperation(.newProject)
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        CommandGroup(after: .newItem) {
            Button("開く…") {
                engine.requestFileOperation(.open)
            }
            .keyboardShortcut("o", modifiers: .command)
        }
        CommandGroup(replacing: .saveItem) {
            Button("保存") {
                engine.requestFileOperation(.save)
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(engine.song == nil)
            Button("名前を付けて保存…") {
                engine.requestFileOperation(.saveAs)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(engine.song == nil)
        }
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
