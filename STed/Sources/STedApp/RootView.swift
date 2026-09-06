import SwiftUI
import UniformTypeIdentifiers
import STedPlayback
#if os(iOS)
import UIKit
#endif

struct RootView: View {
    @EnvironmentObject private var engine: PlaybackEngine
    @State private var path: [AppRoute] = []
    @State private var isSettingsPresented = false
    @State private var isImporterPresented = false
    @State private var isExporterPresented = false
    @State private var exportDocument = RCPFileDocument()
    @State private var pendingFileOperation: PlaybackEngine.FileOperation?
    @State private var pendingOperationAfterSave: PlaybackEngine.FileOperation?

    var body: some View {
        Group {
            if usesStackNavigation {
                NavigationStack(path: $path) {
                    TrackListView(opensEditorInStack: true, isSettingsPresented: $isSettingsPresented)
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .trackEditor(let trackID):
                                TrackEditorView(trackID: trackID)
                            case .settings:
                                SettingsView()
                            }
                        }
                }
                .onChange(of: engine.song?.title) { _, _ in
                    applyLaunchRoute()
                }
            } else {
                splitWorkspace
                    .sheet(isPresented: $isSettingsPresented) {
                        NavigationStack {
                            SettingsView()
                                .toolbar {
                                    ToolbarItem(placement: .confirmationAction) {
                                        Button("閉じる") { isSettingsPresented = false }
                                    }
                                }
                        }
                        #if os(macOS)
                        .frame(minWidth: 420, minHeight: 480)
                        #endif
                    }
            }
        }
        .onChange(of: engine.requestedFileOperation) { _, operation in
            guard let operation else { return }
            engine.consumeFileOperation()
            handleFileOperation(operation)
        }
        .alert("変更を保存しますか？", isPresented: Binding(
            get: { pendingFileOperation != nil },
            set: { isPresented in
                if !isPresented { pendingFileOperation = nil }
            }
        )) {
            Button("キャンセル") {
                pendingFileOperation = nil
            }
            Button("いいえ") {
                continuePendingFileOperation(save: false)
            }
            Button("はい") {
                continuePendingFileOperation(save: true)
            }
        } message: {
            Text("保存していない変更があります。")
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .data,
            defaultFilename: engine.exportFileName
        ) { result in
            switch result {
            case .success(let url):
                engine.recordSavedFile(at: url)
                if let operation = pendingOperationAfterSave {
                    pendingOperationAfterSave = nil
                    performFileOperation(operation)
                }
            case .failure(let error):
                pendingOperationAfterSave = nil
                engine.reportError(error)
            }
        }
        .fileImporter(
            isPresented: $isImporterPresented,
            allowedContentTypes: [.data, .item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    try engine.load(url: url)
                    path.removeAll()
                } catch {
                    engine.reportError(error)
                }
            case .failure(let error):
                engine.reportError(error)
            }
        }
        #if os(macOS)
        .frame(minWidth: 960, minHeight: 640)
        #endif
    }

    @ViewBuilder
    private var splitWorkspace: some View {
        #if os(macOS)
        HSplitView {
            NavigationStack {
                TrackListView(opensEditorInStack: false, isSettingsPresented: $isSettingsPresented)
            }
            .frame(minWidth: 280, idealWidth: 360, maxWidth: 520)
            editorColumn
                .frame(minWidth: 480)
        }
        #else
        NavigationSplitView {
            TrackListView(opensEditorInStack: false, isSettingsPresented: $isSettingsPresented)
                .navigationSplitViewColumnWidth(min: 280, ideal: 360, max: 520)
        } detail: {
            editorColumn
        }
        #endif
    }

    @ViewBuilder
    private var editorColumn: some View {
        if let trackID = engine.selectedTrackID {
            NavigationStack {
                TrackEditorView(trackID: trackID)
            }
        } else {
            ContentUnavailableView(
                "トラックを選択",
                systemImage: "music.note.list",
                description: Text("左のリストから編集するトラックを選ぶ")
            )
        }
    }

    private var usesStackNavigation: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private func applyLaunchRoute() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--settings") {
            path = [.settings]
            return
        }
        if arguments.contains("--editor"),
           let trackID = engine.selectedTrackID ?? engine.song?.tracks.first?.id
        {
            path = [.trackEditor(trackID)]
        }
    }

    private func handleFileOperation(_ operation: PlaybackEngine.FileOperation) {
        switch operation {
        case .newProject:
            requestFileOperationIfNeeded(operation)
        case .open:
            requestFileOperationIfNeeded(operation)
        case .save:
            performFileOperation(operation)
        case .saveAs:
            performFileOperation(operation)
        }
    }

    private func requestFileOperationIfNeeded(_ operation: PlaybackEngine.FileOperation) {
        if engine.isDirty {
            pendingFileOperation = operation
        } else {
            performFileOperation(operation)
        }
    }

    private func continuePendingFileOperation(save: Bool) {
        guard let operation = pendingFileOperation else { return }
        pendingFileOperation = nil
        if !save {
            performFileOperation(operation)
            return
        }

        if engine.currentFileURL != nil {
            do {
                try engine.save()
                performFileOperation(operation)
            } catch {
                engine.reportError(error)
            }
        } else {
            pendingOperationAfterSave = operation
            beginSaveAs()
        }
    }

    private func performFileOperation(_ operation: PlaybackEngine.FileOperation) {
        switch operation {
        case .newProject:
            path.removeAll()
            engine.newProject()
        case .open:
            isImporterPresented = true
        case .save:
            if engine.currentFileURL == nil {
                beginSaveAs()
            } else {
                do {
                    try engine.save()
                } catch {
                    engine.reportError(error)
                }
            }
        case .saveAs:
            beginSaveAs()
        }
    }

    private func beginSaveAs() {
        do {
            exportDocument = RCPFileDocument(data: try engine.encodedRCP())
            isExporterPresented = true
        } catch {
            pendingOperationAfterSave = nil
            engine.reportError(error)
        }
    }
}
