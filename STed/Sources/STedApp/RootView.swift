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
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: .data,
            defaultFilename: engine.exportFileName
        ) { result in
            switch result {
            case .success(let url):
                engine.recordSavedFile(at: url)
            case .failure(let error):
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
            engine.reportError(error)
        }
    }
}
