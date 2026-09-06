import SwiftUI
import STedCore
import STedPlayback
#if os(macOS)
import AppKit
#else
import UIKit
#endif

private enum TrackerPalette {
    static let crt = Color(red: 0.04, green: 0.055, blue: 0.09)
    static let phosphor = Color(red: 0.50, green: 0.91, blue: 0.88)
    static let paper = Color.white
    static let yellow = Color(red: 1.0, green: 0.92, blue: 0.28)
    static let cyan = phosphor

    static func ink(_ ink: TrackerInk) -> Color {
        switch ink {
        case .white: return paper
        case .yellow: return yellow
        case .cyan: return cyan
        }
    }
    static let dim = Color(red: 0.28, green: 0.55, blue: 0.54)
    static let cell = Color(red: 0.37, green: 0.88, blue: 0.84)
    static let playhead = Color(red: 0.12, green: 0.28, blue: 0.30)
    static let pad = Color(red: 0.09, green: 0.12, blue: 0.18)
    static let padEdge = Color(red: 0.22, green: 0.38, blue: 0.40)
    static let danger = Color(red: 0.86, green: 0.38, blue: 0.32)
    static let insert = Color(red: 0.95, green: 0.78, blue: 0.32)
}

private enum TrackerKeyBindings {
    static let directionalKeys: Set<KeyEquivalent> = [
        .upArrow, .downArrow, .leftArrow, .rightArrow
    ]
    static let pageKeys: Set<KeyEquivalent> = [
        .pageUp, .pageDown
    ]
    static let pageRows = 24
}

/// Character columns match STed2 `trk_dis`: MEAS 5, STEP 5, NOTE+K# 7, ST/GT/VEL 6.
private enum TrackerLayout {
    static let fontSize: CGFloat = 19.5
    static let headerFontSize: CGFloat = 16.5
    static let characterWidth = monospacedAdvance(fontSize)
    static let cellHeight: CGFloat = {
        #if os(macOS)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        return ceil(font.ascender - font.descender + font.leading)
        #else
        return ceil(UIFont.monospacedSystemFont(ofSize: fontSize, weight: .medium).lineHeight)
        #endif
    }()
    static let caretHeight: CGFloat = cellHeight - 2

    static let measWidth = width(5)
    static let stepWidth = width(5)
    static let noteWidth = width(TrackerColumn.noteWidth)
    static let valueWidth = width(TrackerColumn.valueWidth)
    static let dataWidth = noteWidth + valueWidth * 3

    static func width(_ columns: Int) -> CGFloat {
        CGFloat(columns) * characterWidth
    }

    static var rowFont: Font { monospacedFont(fontSize, weight: .medium) }
    static var headerFont: Font { monospacedFont(headerFontSize, weight: .bold) }

    static func monospacedAdvance(_ size: CGFloat) -> CGFloat {
        #if os(macOS)
        NSFont.monospacedSystemFont(ofSize: size, weight: .medium).maximumAdvancement.width
        #else
        let font = UIFont.monospacedSystemFont(ofSize: size, weight: .medium)
        return ("0" as NSString).size(withAttributes: [.font: font]).width
        #endif
    }

    static func monospacedFont(_ size: CGFloat, weight: Font.Weight) -> Font {
        #if os(macOS)
        let nsWeight: NSFont.Weight = weight == .bold ? .bold : .medium
        return Font(NSFont.monospacedSystemFont(ofSize: size, weight: nsWeight))
        #else
        let uiWeight: UIFont.Weight = weight == .bold ? .bold : .medium
        return Font(UIFont.monospacedSystemFont(ofSize: size, weight: uiWeight))
        #endif
    }
}

struct TrackEditorView: View {
    private enum InlineEditorOrigin: Equatable {
        case direct
        case insertedNote
        case insertedSpecial
    }

    private enum InlineEditorKind: Equatable {
        case numeric(EventColumn)
        case note
        case symbol
        case special(SpecialControllerField)
    }

    private struct SpecialInsertSession: Equatable {
        var row: Int
        var code: SpecialControllerCode?
        var fields: [SpecialControllerField]
        var fieldIndex: Int
    }

    private struct InlineEditor: Equatable {
        let row: Int
        let kind: InlineEditorKind
        let origin: InlineEditorOrigin
        let sessionID: Int
        let selectsText: Bool
        let copiedNotePreview: String?

        var column: EventColumn {
            switch kind {
            case .numeric(let column): return column
            case .note, .symbol: return .note
            case .special(let field): return SpecialController.column(for: field)
            }
        }
    }

    @EnvironmentObject private var engine: PlaybackEngine
    let trackID: Int
    @State private var cursor = TrackCursor()
    @State private var rowSelection: TrackerRowSelection?
    @State private var inlineEditor: InlineEditor?
    @State private var inlineText = ""
    @State private var inlineEditorSessionID = 0
    @FocusState private var isKeyboardFocused: Bool
    @FocusState private var isToneSelectorFocused: Bool
    @State private var isTrackSettingsPresented = false
    @State private var specialInsert: SpecialInsertSession?
    @State private var specialSelectorIndex = 0
    @State private var isSpecialSelectorPresented = false
    @State private var toneEditor: InlineEditor?
    @State private var toneDraft = ""
    @State private var toneIndex = 0

    private var track: Track? {
        engine.song?.tracks.first { $0.id == trackID }
    }

    var body: some View {
        Group {
            if let song = engine.song, let track {
                editor(song: song, track: track)
            } else {
                ContentUnavailableView(
                    "トラックがありません",
                    systemImage: "minus.circle",
                    description: Text("先に曲を読み込む")
                )
            }
        }
        .background(TrackerPalette.crt.ignoresSafeArea())
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(TrackerPalette.crt, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        #endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if let track {
                    Button(track.mode.isMuted ? "MUTE" : "PLAY") {
                        engine.setMuted(!track.mode.isMuted, trackID: track.id)
                    }
                }
            }
        }
        .sheet(isPresented: $isTrackSettingsPresented) {
            if let track {
                TrackSettingsView(track: track) { channel, startTick, keyShift, memo in
                    engine.updateTrack(
                        trackID: trackID,
                        midiChannel: channel,
                        startTick: startTick,
                        keyShift: keyShift,
                        memo: memo
                    )
                }
            }
        }
        .onAppear {
            engine.selectedTrackID = trackID
            resetInlineEditor()
            normalizeCursor()
            isKeyboardFocused = true
        }
        .onChange(of: trackID) { _, _ in
            rowSelection = nil
            engine.endEdit()
            toneEditor = nil
            resetInlineEditor()
            normalizeCursor()
            isKeyboardFocused = true
        }
        .onDisappear { engine.endEdit() }
        .onChange(of: engine.historyRevision) { _, _ in clearHistoryEditors() }
        .focusedSceneValue(\.trackerHistory, TrackerHistoryActions(
            undo: { performHistory(redo: false) },
            redo: { performHistory(redo: true) },
            hasDraft: inlineEditor != nil || toneEditor != nil,
            copy: { copyRows() }, cut: { copyRows(cutting: true) }, paste: { pasteRows() },
            hasSelection: !selectedRows.isEmpty,
            canPaste: inlineEditor == nil && toneEditor == nil && !isSpecialSelectorPresented

        ))
    }

    private func clearHistoryEditors() {
        rowSelection = nil
        toneEditor = nil
        isToneSelectorFocused = false
        specialInsert = nil
        isSpecialSelectorPresented = false
        resetInlineEditor()
        normalizeCursor()
        isKeyboardFocused = true
    }

    private func performHistory(redo: Bool) {
        if toneEditor != nil { closeToneSelector(confirming: false) }
        if let editor = inlineEditor {
            if editor.origin == .insertedSpecial {
                if case .special = editor.kind { commitSpecialField(inlineText) }
            } else {
                commitInlineEditor()
            }
        }
        engine.endEdit()
        clearHistoryEditors()
        if redo { engine.redo() } else { engine.undo() }
    }

    private var title: String {
        if let track {
            let memo = track.memo.isEmpty ? "" : "  \(track.memo)"
            return "Track \(track.number)\(memo)"
        }
        return "トラック編集"
    }

    private func editor(song: Song, track: Track) -> some View {
        let rows = track.eventRows(
            timeBase: song.timeBase,
            beatNumerator: song.beatNumerator,
            beatDenominator: song.beatDenominator
        )
        return GeometryReader { geo in
            VStack(spacing: 0) {
                header(track)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 4)

                columnHeader
                    .padding(.horizontal, 8)

                trackerList(rows: rows)
                    #if os(iOS)
                    .frame(height: max(160, geo.size.height * 0.48))
                    #else
                    .frame(maxHeight: .infinity)
                    #endif

                #if os(iOS)
                inputDeck
                    .frame(maxHeight: .infinity)
                #endif
            }
            .overlay {
                if isSpecialSelectorPresented {
                    specialSelectorOverlay
                }
                if toneEditor != nil {
                    toneSelectorOverlay
                }
            }
        }
        .focusable()
        .focused($isKeyboardFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: TrackerKeyBindings.directionalKeys, phases: [.down, .repeat]) { press in
            return handleDirectionalPress(press, rowCount: rows.count)
        }
        .onKeyPress(keys: TrackerKeyBindings.pageKeys, phases: [.down, .repeat]) { press in
            switch press.key {
            case .pageUp:
                return handlePageKey(by: -TrackerKeyBindings.pageRows, rowCount: rows.count)
            case .pageDown:
                return handlePageKey(by: TrackerKeyBindings.pageRows, rowCount: rows.count)
            default:
                return .ignored
            }
        }
        .onKeyPress(.return, phases: .down) { _ in
            if toneEditor != nil {
                closeToneSelector(confirming: true)
                return .handled
            }
            if isSpecialSelectorPresented {
                confirmSpecialSelector()
                return .handled
            }
            if inlineEditor?.origin == .insertedSpecial {
                return handleSpecialInsertCommit()
            }
            if inlineEditor != nil {
                // `retkey(13)` in EDIT.C advances to the next row after
                // committing the active field.
                return handleCursorKey(
                    for: .downArrow,
                    rowCount: rows.count,
                    selectDestination: false
                )
            } else {
                insertNoteBeforeCursor()
            }
            return .handled
        }
        .onKeyPress(.space, phases: .down) { _ in
            if toneEditor != nil { return .handled }
            if isSpecialSelectorPresented {
                dismissSpecialSelector()
                return .handled
            }
            if inlineEditor?.origin == .insertedSpecial {
                return handleSpecialInsertCommit()
            }
            playFromCursorMeasure(track)
            return .handled
        }
        .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
            return handleEditorCommandKey(press) ?? .ignored
        }
        .onKeyPress(phases: [.down, .repeat]) { press in
            if press.modifiers.contains(.command) { return .ignored }
            if toneEditor != nil {
                if TrackerKeyBindings.directionalKeys.contains(press.key) {
                    return handleCursorKey(for: press.key, rowCount: rows.count)
                }
                if press.key == .return {
                    closeToneSelector(confirming: true)
                    return .handled
                }
                if press.key == .pageUp || press.key == .pageDown {
                    toneIndex = ProgramToneList.moved(toneIndex, by: press.key == .pageUp ? -16 : 16)
                    return .handled
                }
                if press.key == .escape || press.characters == "\u{1b}" {
                    closeToneSelector(confirming: false)
                }
                return .handled
            }
            // Keep non-selector text entry single-shot. Held navigation keys
            // are handled by the directional/page handlers above.
            guard press.phase == .down else { return .ignored }
            if isSpecialSelectorPresented {
                return handleSpecialSelectorKey(press)
            }
            if let result = handleEditorCommandKey(press) {
                return result
            }
            guard inlineEditor == nil else { return .ignored }
            if press.key == .escape, rowSelection != nil {
                rowSelection = nil
                return .handled
            }
            if let digit = keyboardDigit(from: press) {
                return beginNumericEdit(String(digit)) ? .handled : .ignored
            }
            if let note = keyboardNoteCharacter(from: press) {
                return handleNoteLetter(note)
            }
            if press.characters == "-" {
                return beginNumericEdit("-") ? .handled : .ignored
            }
            return .ignored
        }
    }

    private func header(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isTrackSettingsPresented = true
            } label: {
                Text("M:\(track.memo.isEmpty ? "--------" : track.memo)")
                    .font(.system(size: TrackerLayout.fontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(TrackerPalette.phosphor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                headerField("TR", "\(track.number)")
                headerField("MEAS", "\(cursorMeasure(track))")
                headerField("CH", channelText(track))
                headerField("USED", "\(track.terminatorIndex)")
                Spacer(minLength: 0)
            }
            .font(.system(size: TrackerLayout.headerFontSize, weight: .medium, design: .monospaced))
            .foregroundStyle(TrackerPalette.phosphor)

            TransportBar(compact: true, playMeasure: cursorMeasure(track))
                .tint(TrackerPalette.phosphor)
        }
    }

    private func headerField(_ name: String, _ value: String) -> some View {
        HStack(spacing: 2) {
            Text("\(name):")
                .foregroundStyle(TrackerPalette.dim)
            Text(value)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("MEAS")
                .lineLimit(1)
                .frame(width: TrackerLayout.measWidth, alignment: .trailing)
            Text("STEP")
                .lineLimit(1)
                .frame(width: TrackerLayout.stepWidth, alignment: .trailing)
            Text(":")
            columnTitle(TrackerColumn.note("NOTE K#"), .note)
                .frame(width: TrackerLayout.noteWidth, alignment: .leading)
            columnTitle(TrackerColumn.value("ST"), .st)
                .frame(width: TrackerLayout.valueWidth, alignment: .leading)
            columnTitle(TrackerColumn.value("GT"), .gt)
                .frame(width: TrackerLayout.valueWidth, alignment: .leading)
            columnTitle(TrackerColumn.value("VEL"), .vel)
                .frame(width: TrackerLayout.valueWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
        .font(TrackerLayout.headerFont)
        .foregroundStyle(Color.white.opacity(0.9))
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(TrackerPalette.dim.opacity(0.55))
    }

    private func columnTitle(_ title: String, _ column: EventColumn) -> some View {
        Text(title)
            .lineLimit(1)
            .foregroundStyle(cursor.column == column ? TrackerPalette.cell : Color.white.opacity(0.9))
            .onTapGesture {
                moveCursorToCell(row: cursor.row, column: column)
            }
    }

    private func trackerList(rows: [EventRow]) -> some View {
        let playheadRow = engine.state == .playing || engine.state == .paused
            ? rows.lastIndex(where: { !$0.isTerminator && !$0.isMeasureLine && $0.time.tick <= engine.positionTick })
            : nil
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        trackerRow(index: index, row: row, isPlayhead: index == playheadRow)
                            .id(index)
                    }
                }
            }
            .background(TrackerPalette.crt)
            .onChange(of: cursor.row) { _, row in
                proxy.scrollTo(row, anchor: .center)
            }
        }
    }

    private func trackerRow(index: Int, row: EventRow, isPlayhead: Bool) -> some View {
        let isSelected = cursor.row == index
        let ink = TrackerPalette.ink(row.ink)
        return HStack(spacing: 0) {
            Text(row.showsMeasure ? String(format: "%5d", row.time.measure) : "")
                .lineLimit(1)
                .frame(width: TrackerLayout.measWidth, alignment: .trailing)
                .foregroundStyle(TrackerPalette.paper)
            Text(row.stepNumber.map { String(format: "%5d", $0) } ?? "")
                .lineLimit(1)
                .frame(width: TrackerLayout.stepWidth, alignment: .trailing)
                .foregroundStyle(TrackerPalette.paper)
            Text(":")
                .foregroundStyle(TrackerPalette.paper)
            if row.isMeasureLine || row.isTerminator {
                Text(row.noteText)
                    .lineLimit(1)
                    .frame(width: TrackerLayout.dataWidth, alignment: .leading)
                    .background(isSelected && cursor.column == .note ? TrackerPalette.cell : Color.clear)
                    .foregroundStyle(
                        isSelected && cursor.column == .note
                            ? TrackerPalette.crt
                            : ink
                    )
                    .onTapGesture {
                        moveCursorToCell(row: index, column: .note)
                    }
            } else {
                cell(
                    TrackerColumn.note(row.noteText),
                    column: .note,
                    index: index,
                    alignment: .leading,
                    ink: ink
                )
                    .frame(width: TrackerLayout.noteWidth, alignment: .leading)
                cell(
                    TrackerColumn.value(row.stText),
                    column: .st,
                    index: index,
                    alignment: .leading,
                    ink: ink
                )
                    .frame(width: TrackerLayout.valueWidth, alignment: .leading)
                cell(
                    TrackerColumn.value(row.gtText),
                    column: .gt,
                    index: index,
                    alignment: .leading,
                    ink: ink
                )
                    .frame(width: TrackerLayout.valueWidth, alignment: .leading)
                cell(
                    TrackerColumn.value(row.velText),
                    column: .vel,
                    index: index,
                    alignment: .leading,
                    ink: ink
                )
                    .frame(width: TrackerLayout.valueWidth, alignment: .leading)
            }
            Spacer(minLength: 0)
        }
        .font(TrackerLayout.rowFont)
        .frame(height: TrackerLayout.cellHeight)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            if selectedRows.contains(index) {
                TrackerPalette.cell.opacity(0.35)
            } else if isSelected {
                TrackerPalette.playhead.opacity(0.85)
            } else if isPlayhead {
                TrackerPalette.playhead.opacity(0.35)
            } else {
                Color.clear
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            rowSelection = nil
            if inlineEditor != nil {
                moveCursorToCell(row: index, column: cursor.column)
            } else {
                resetInlineEditor()
                cursor.row = index
                isKeyboardFocused = true
            }
        }
    }

    @ViewBuilder
    private func cell(
        _ text: String,
        column: EventColumn,
        index: Int,
        alignment: Alignment,
        ink: Color
    ) -> some View {
        let active = cursor.row == index && cursor.column == column
        if let inlineEditor,
           inlineEditor.row == index,
           inlineEditor.column == column {
            inlineEditorField(
                kind: inlineEditor.kind,
                selectAll: inlineEditor.selectsText,
                copiedNotePreview: inlineEditor.copiedNotePreview,
                isTrailing: column != .note
            )
                .id(inlineEditor.sessionID)
                .frame(maxWidth: .infinity, alignment: alignment)
        } else {
            Text(text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: alignment)
                .background(active ? TrackerPalette.cell : Color.clear)
                .foregroundStyle(active ? TrackerPalette.crt : ink)
                .onTapGesture {
                    moveCursorToCell(row: index, column: column)
                }
        }
    }

    private func inlineEditorField(
        kind: InlineEditorKind,
        selectAll: Bool,
        copiedNotePreview: String?,
        isTrailing: Bool
    ) -> some View {
        TrackerInlineEditorField(
            mode: inlineEditorMode(for: kind),
            initialText: inlineText,
            selectAll: selectAll,
            copiedNotePreview: copiedNotePreview,
            isTrailing: isTrailing,
            onTextChange: { text in
                inlineText = text
            },
            onCancel: {
                cancelInlineEditor()
            }
        )
    }

    private func inlineEditorMode(for kind: InlineEditorKind) -> TrackerTextInputMode {
        switch kind {
        case .numeric:
            return .numeric
        case .note:
            return .note
        case .symbol:
            return .symbol
        case .special(let field):
            switch field {
            case .pitchBend:
                return .pitch
            case .stepTime, .gateTime, .velocity, .midiChannel:
                return .numeric
            }
        }
    }

    private var inputDeck: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                FlickKeyPad(pad: .notesAC, onInput: apply)
                FlickKeyPad(pad: .notesDG, onInput: apply)
                FlickKeyPad(pad: .digitsLow, onInput: apply)
                FlickKeyPad(pad: .digitsHigh, onInput: apply)
            }
            .padding(.horizontal, 10)

            HStack(spacing: 8) {
                Button(action: insertEvent) {
                    Text("挿入")
                        .font(.system(size: 27, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(TrackerPalette.crt)
                        .background(TrackerPalette.insert)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: deleteEvent) {
                    Text("削除")
                        .font(.system(size: 27, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(.white)
                        .background(TrackerPalette.danger)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canDelete)
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
        .padding(.top, 10)
        .background(TrackerPalette.pad)
    }

    private var canDelete: Bool {
        guard let track else { return false }
        return cursor.row >= 0 && cursor.row < track.terminatorIndex
    }

    private func apply(_ input: TrackEditInput) {
        resetInlineEditor()
        guard let track else { return }
        let index = cursor.row
        guard track.events.indices.contains(index), index < track.terminatorIndex else { return }
        engine.updateEvent(
            trackID: trackID,
            index: index,
            track.events[index].applying(input, column: cursor.column)
        )
        isKeyboardFocused = true
    }

    private func insertEvent() {
        guard let track else { return }
        resetInlineEditor()
        let index = min(cursor.row + 1, track.terminatorIndex)
        engine.insertEvent(trackID: trackID, at: index)
        cursor = TrackCursor(row: index, column: .note)
        isKeyboardFocused = true
    }

    private func insertMeasureLine() {
        guard let track else { return }
        resetInlineEditor()
        let index = min(max(0, cursor.row), track.terminatorIndex)
        engine.insertEvent(trackID: trackID, at: index, .measureLine)
        cursor = TrackCursor(row: index + 1, column: .note)
        normalizeCursor()
        isKeyboardFocused = true
    }

    private func deleteEvent() {
        if !selectedRows.isEmpty {
            replaceSelectedRows(with: [])
            return
        }
        guard let track, cursor.row < track.terminatorIndex else { return }
        resetInlineEditor()
        let index = cursor.row
        engine.deleteEvent(trackID: trackID, at: index)
        let newTerminatorIndex = max(0, track.terminatorIndex - 1)
        cursor.row = min(index, newTerminatorIndex)
        isKeyboardFocused = true
    }

    private func handleEditorCommandKey(_ press: KeyPress) -> KeyPress.Result? {
        guard toneEditor == nil else { return .handled }
        guard let key = trackerEditorKey(from: press),
              let command = TrackerEditorKeyMap.command(
                for: key,
                isInlineEditing: inlineEditor != nil
              )
        else {
            return nil
        }

        switch command {
        case .deleteSelectedRow:
            deleteEvent()
            return .handled
        case .insertMeasureLine:
            insertMeasureLine()
            return .handled
        case .insertSpecialController:
            insertSpecialController()
            return .handled
        }
    }

    private func trackerEditorKey(from press: KeyPress) -> TrackerEditorKey? {
        switch press.key {
        case .delete:
            return .delete
        case .deleteForward:
            return .deleteForward
        default:
            return TrackerEditorKey(characters: press.characters)
        }
    }

    private var selectedRows: Range<Int> {
        rowSelection?.range(eventCount: track?.terminatorIndex ?? 0) ?? 0..<0
    }

    private func handleDirectionalPress(_ press: KeyPress, rowCount: Int) -> KeyPress.Result {
        if press.modifiers.contains(.shift),
           press.key == .upArrow || press.key == .downArrow,
           toneEditor == nil, !isSpecialSelectorPresented {
            if inlineEditor != nil {
                if inlineEditor?.origin == .insertedSpecial {
                    return handleCursorKey(for: press.key, rowCount: rowCount)
                }
                commitInlineEditor()
                engine.endEdit()
            }
            if rowSelection == nil { rowSelection = TrackerRowSelection(anchor: cursor.row) }
            cursor.move(press.key == .upArrow ? .up : .down, rowCount: rowCount)
            rowSelection?.move(to: cursor.row)
            isKeyboardFocused = true
            return .handled
        }
        rowSelection = nil
        return handleCursorKey(for: press.key, rowCount: rowCount)
    }

    private func copyRows(cutting: Bool = false) {
        guard let track, !selectedRows.isEmpty else { return }
        let events = Array(track.events[selectedRows])
        let data = TrackEventClipboard.encode(events)
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: NSPasteboard.PasteboardType(TrackEventClipboard.typeIdentifier))
        #else
        UIPasteboard.general.setData(data, forPasteboardType: TrackEventClipboard.typeIdentifier)
        #endif
        if cutting { replaceSelectedRows(with: []) }
    }

    private func pasteRows() {
        guard inlineEditor == nil, toneEditor == nil, !isSpecialSelectorPresented else { return }
        #if os(macOS)
        let data = NSPasteboard.general.data(forType: NSPasteboard.PasteboardType(TrackEventClipboard.typeIdentifier))
        #else
        let data = UIPasteboard.general.data(forPasteboardType: TrackEventClipboard.typeIdentifier)
        #endif
        guard let data, let events = TrackEventClipboard.decode(data) else { return }
        replaceSelectedRows(with: events)
    }

    private func replaceSelectedRows(with events: [TrackEvent]) {
        guard let track else { return }
        let index = min(cursor.row, track.terminatorIndex)
        let range = selectedRows.isEmpty ? index..<index : selectedRows
        engine.replaceEvents(trackID: trackID, in: range, with: events)
        rowSelection = nil
        resetInlineEditor()
        cursor.row = range.lowerBound
        normalizeCursor()
        isKeyboardFocused = true
    }

    private func handleCursorKey(
        for key: KeyEquivalent,
        rowCount: Int,
        selectDestination: Bool = true
    ) -> KeyPress.Result {
        let direction: TrackCursorDirection?
        switch key {
        case .upArrow: direction = .up
        case .downArrow: direction = .down
        case .leftArrow: direction = .left
        case .rightArrow: direction = .right
        default: direction = nil
        }

        guard let direction else { return .ignored }
        if toneEditor != nil {
            switch direction {
            case .up: toneIndex = ProgramToneList.moved(toneIndex, by: -1)
            case .down: toneIndex = ProgramToneList.moved(toneIndex, by: 1)
            case .left: toneIndex = ProgramToneList.moved(toneIndex, by: -16)
            case .right: toneIndex = ProgramToneList.moved(toneIndex, by: 16)
            }
            return .handled
        }
        if direction == .down, openToneSelectorIfNeeded() {
            return .handled
        }
        if isSpecialSelectorPresented {
            return handleSpecialSelectorDirection(direction)
        }
        if let inlineEditor, inlineEditor.origin == .insertedSpecial {
            return handleInsertedSpecialNavigation(direction: direction)
        }
        if let inlineEditor, inlineEditor.origin == .insertedNote {
            return handleInsertedEditorNavigation(
                direction: direction,
                rowCount: rowCount,
                selectDestination: selectDestination
            )
        }
        let wasEditing = inlineEditor != nil
        finishInlineEditorBeforeNavigation()
        cursor.move(direction, rowCount: rowCount)
        if selectDestination && wasEditing && beginEditorAtCursor(selectAll: true) {
            return .handled
        }
        isKeyboardFocused = true
        return .handled
    }

    private func handlePageKey(by delta: Int, rowCount: Int) -> KeyPress.Result {
        if toneEditor != nil {
            toneIndex = ProgramToneList.moved(toneIndex, by: delta < 0 ? -16 : 16)
            return .handled
        }
        if isSpecialSelectorPresented {
            return .handled
        }
        rowSelection = nil
        finishInlineEditorBeforeNavigation()
        cursor.page(by: delta, rowCount: rowCount)
        isKeyboardFocused = true
        return .handled
    }

    private func handleInsertedEditorNavigation(
        direction: TrackCursorDirection,
        rowCount: Int,
        selectDestination: Bool
    ) -> KeyPress.Result {
        guard let editor = inlineEditor else { return .ignored }

        switch direction {
        case .right:
            switch editor.kind {
            case .note:
                return beginInsertedNumericEditor(
                    row: editor.row,
                    column: .st,
                    selectAll: true
                )
            case .symbol, .special:
                return finishInsertedEditorAndMove(
                    .right,
                    rowCount: rowCount,
                    selectDestination: selectDestination
                )
            case .numeric(let column):
                switch column {
                case .st:
                    return beginInsertedNumericEditor(
                        row: editor.row,
                        column: .gt,
                        selectAll: true
                    )
                case .gt:
                    return beginInsertedNumericEditor(
                        row: editor.row,
                        column: .vel,
                        selectAll: true
                    )
                case .vel:
                    return finishInsertedEditorAndMove(
                        .down,
                        rowCount: rowCount,
                        selectDestination: selectDestination
                    )
                case .note:
                    return .ignored
                }
            }
        case .left:
            switch editor.kind {
            case .note:
                return finishInsertedEditorAndMove(
                    .left,
                    rowCount: rowCount,
                    selectDestination: selectDestination
                )
            case .symbol, .special:
                return finishInsertedEditorAndMove(
                    .left,
                    rowCount: rowCount,
                    selectDestination: selectDestination
                )
            case .numeric(let column):
                switch column {
                case .st:
                    return beginInsertedNoteEditor(row: editor.row, selectAll: true)
                case .gt:
                    return beginInsertedNumericEditor(
                        row: editor.row,
                        column: .st,
                        selectAll: true
                    )
                case .vel:
                    return beginInsertedNumericEditor(
                        row: editor.row,
                        column: .gt,
                        selectAll: true
                    )
                case .note:
                    return .ignored
                }
            }
        case .up, .down:
            return finishInsertedEditorAndMove(
                direction,
                rowCount: rowCount,
                selectDestination: selectDestination
            )
        }
    }

    private func beginInsertedNumericEditor(
        row: Int,
        column: EventColumn,
        selectAll: Bool
    ) -> KeyPress.Result {
        guard let track,
              track.events.indices.contains(row),
              let value = track.events[row].numericValue(in: column)
        else {
            finishInlineEditorBeforeNavigation()
            isKeyboardFocused = true
            return .handled
        }

        commitInlineEditor()
        cursor = TrackCursor(row: row, column: column)
        let initialText = value == 0 ? "" : String(value)
        if beginNumericEdit(
            initialText,
            origin: .insertedNote,
            selectAll: selectAll
        ) {
            return .handled
        }
        isKeyboardFocused = true
        return .handled
    }

    private func beginInsertedNoteEditor(row: Int, selectAll: Bool) -> KeyPress.Result {
        guard let track, track.events.indices.contains(row) else {
            finishInlineEditorBeforeNavigation()
            isKeyboardFocused = true
            return .handled
        }

        let initialText = track.events[row].noteInputText
        commitInlineEditor()
        cursor = TrackCursor(row: row, column: .note)
        if beginNoteEdit(
            initialText: initialText,
            origin: .insertedNote,
            selectAll: selectAll
        ) {
            return .handled
        }
        isKeyboardFocused = true
        return .handled
    }

    private func finishInsertedEditorAndMove(
        _ direction: TrackCursorDirection,
        rowCount: Int,
        selectDestination: Bool
    ) -> KeyPress.Result {
        guard let row = inlineEditor?.row else { return .ignored }
        commitInlineEditor()
        engine.endEdit()
        cursor = TrackCursor(row: row, column: .note)
        cursor.move(direction, rowCount: rowCount)
        if selectDestination && beginEditorAtCursor(selectAll: true) {
            return .handled
        }
        isKeyboardFocused = true
        return .handled
    }

    private func finishInlineEditorBeforeNavigation() {
        guard inlineEditor != nil else { return }
        if inlineEditor?.origin == .insertedSpecial {
            _ = handleSpecialInsertCommit()
            return
        }
        commitInlineEditor()
        engine.endEdit()
    }

    private func moveCursorToCell(row: Int, column: EventColumn) {
        rowSelection = nil
        let wasEditing = inlineEditor != nil
        if wasEditing {
            commitInlineEditor()
        } else {
            resetInlineEditor()
        }
        engine.endEdit()
        cursor = TrackCursor(row: row, column: column)
        if wasEditing && beginEditorAtCursor(selectAll: true) {
            return
        }
        isKeyboardFocused = true
    }

    private func beginEditorAtCursor(selectAll: Bool) -> Bool {
        guard let track,
              track.events.indices.contains(cursor.row),
              cursor.row < track.terminatorIndex
        else { return false }

        let event = track.events[cursor.row]
        if cursor.column == .note, event.command < 0x80 {
            return beginNoteEdit(
                initialText: event.noteInputText,
                selectAll: selectAll
            )
        }

        let action = TrackerNumericEditAction.forCommand(event.command, column: cursor.column)
        guard let value = event.editorValue(for: action) else { return false }
        return beginNumericEdit(
            value == 0 ? "" : String(value),
            selectAll: selectAll
        )
    }

    private func insertNoteBeforeCursor() {
        guard let track else { return }
        resetInlineEditor()
        engine.beginEdit()
        let index = min(max(0, cursor.row), track.terminatorIndex)
        let insertedEvent = engine.insertNoteBefore(trackID: trackID, at: index)
        cursor = TrackCursor(row: index, column: .note)
        if !beginNoteEdit(
            initialText: "",
            copiedNotePreview: insertedEvent?.noteInputText,
            origin: .insertedNote
        ) {
            isKeyboardFocused = true
        }
    }

    private func normalizeCursor() {
        guard let song = engine.song, let track else { return }
        let rowCount = track.eventRows(
            timeBase: song.timeBase,
            beatNumerator: song.beatNumerator,
            beatDenominator: song.beatDenominator
        ).count
        cursor = TrackCursor(
            row: min(cursor.row, max(0, rowCount - 1)),
            column: cursor.column
        )
    }

    private func beginNumericEdit(
        _ initialText: String,
        origin: InlineEditorOrigin = .direct,
        selectAll: Bool = false
    ) -> Bool {
        rowSelection = nil
        guard let track else { return false }
        let index = cursor.row
        guard track.events.indices.contains(index),
              index < track.terminatorIndex
        else { return false }

        let event = track.events[index]
        let action = TrackerNumericEditAction.forCommand(event.command, column: cursor.column)
        switch action {
        case .ignore:
            return false
        case .edit(let column):
            cursor.column = column
            inlineText = TrackerTextInput.normalizedNumeric(initialText)
            inlineEditorSessionID += 1
            inlineEditor = InlineEditor(
                row: index,
                kind: .numeric(column),
                origin: origin,
                sessionID: inlineEditorSessionID,
                selectsText: selectAll,
                copiedNotePreview: nil
            )
        case .editPitchBend:
            cursor.column = .vel
            inlineText = TrackerTextInput.normalizedNumeric(
                initialText,
                maximumLength: TrackerTextInput.symbolMaximumLength
            )
            inlineEditorSessionID += 1
            inlineEditor = InlineEditor(
                row: index,
                kind: .special(.pitchBend),
                origin: origin,
                sessionID: inlineEditorSessionID,
                selectsText: selectAll,
                copiedNotePreview: nil
            )
        }
        isKeyboardFocused = false
        return true
    }

    private func handleNoteLetter(_ initialCharacter: Character) -> KeyPress.Result {
        guard let track else { return .ignored }
        let index = min(max(0, cursor.row), track.terminatorIndex)
        guard track.events.indices.contains(index) else { return .ignored }

        switch TrackerNoteKeyAction.forCommand(track.events[index].command) {
        case .editExisting:
            return beginNoteEdit(initialCharacter) ? .handled : .ignored
        case .insertNew:
            return insertNoteAndBeginEdit(initialCharacter)
        case .ignore:
            return .ignored
        }
    }

    private func insertNoteAndBeginEdit(_ initialCharacter: Character) -> KeyPress.Result {
        guard let track else { return .ignored }
        resetInlineEditor()
        engine.beginEdit()
        let index = min(max(0, cursor.row), track.terminatorIndex)
        let insertedEvent = engine.insertNoteBefore(trackID: trackID, at: index)
        cursor = TrackCursor(row: index, column: .note)
        if beginNoteEdit(
            initialText: String(initialCharacter),
            copiedNotePreview: insertedEvent?.noteInputText,
            origin: .insertedNote
        ) {
            return .handled
        }
        isKeyboardFocused = true
        return .handled
    }

    private func beginNoteEdit(_ initialCharacter: Character) -> Bool {
        beginNoteEdit(initialText: String(initialCharacter))
    }

    private func beginNoteEdit(
        initialText: String,
        copiedNotePreview: String? = nil,
        origin: InlineEditorOrigin = .direct,
        selectAll: Bool = false
    ) -> Bool {
        rowSelection = nil
        guard let track else { return false }
        let index = cursor.row
        guard track.events.indices.contains(index),
              index < track.terminatorIndex,
              track.events[index].command < 0x80
        else { return false }

        cursor.column = .note
        inlineText = TrackerTextInput.normalizedNote(initialText)
        inlineEditorSessionID += 1
        inlineEditor = InlineEditor(
            row: index,
            kind: .note,
            origin: origin,
            sessionID: inlineEditorSessionID,
            selectsText: selectAll,
            copiedNotePreview: copiedNotePreview
        )
        isKeyboardFocused = false
        return true
    }

    private func commitInlineEditor(text draftText: String? = nil) {
        if inlineEditor?.origin == .insertedSpecial {
            _ = handleSpecialInsertCommit()
            return
        }

        guard let inlineEditor,
              let track,
              track.events.indices.contains(inlineEditor.row),
              inlineEditor.row < track.terminatorIndex
        else {
            cancelInlineEditor()
            return
        }

        let event = track.events[inlineEditor.row]
        let draftText = draftText ?? inlineText
        let updated: TrackEvent?
        switch inlineEditor.kind {
        case .numeric(let column):
            let range = TrackerNumericEditAction.range(command: event.command, column: column)
            let value = TrackerTextInput.numericValue(draftText, in: range)
            updated = value.map { event.settingEditorValue($0, action: .edit(column)) }
        case .note:
            guard event.command < 0x80 else {
                cancelInlineEditor()
                return
            }
            let value = TrackerTextInput.noteNumber(
                draftText,
                referenceNote: Int(event.command)
            )
            updated = value.map { event.settingNumericValue($0, in: .note) }
        case .special(.pitchBend):
            let range = TrackerNumericEditAction.range(command: 0xee, column: .vel)
            let value = TrackerTextInput.numericValue(
                draftText,
                in: range,
                maximumLength: TrackerTextInput.symbolMaximumLength
            )
            updated = value.map { event.settingEditorValue($0, action: .editPitchBend) }
        case .symbol, .special:
            cancelInlineEditor()
            return
        }

        if let updated {
            engine.updateEvent(
                trackID: trackID,
                index: inlineEditor.row,
                updated
            )
        }
        resetInlineEditor()
        isKeyboardFocused = true
    }

    private func cancelInlineEditor() {
        toneEditor = nil
        let editor = inlineEditor
        isSpecialSelectorPresented = false
        specialInsert = nil
        switch TrackerInlineCancelAction.forInsertedNote(
            editor?.origin == .insertedNote || editor?.origin == .insertedSpecial
        ) {
        case .deleteInsertedStep:
            if let row = editor?.row {
                cursor.row = row
            }
            resetInlineEditor()
            deleteEvent()
        case .discardEdits:
            resetInlineEditor()
            isKeyboardFocused = true
        }
        engine.endEdit()
    }

    private func resetInlineEditor() {
        inlineEditor = nil
        inlineText = ""
    }

    private func insertSpecialController() {
        guard let track else { return }
        resetInlineEditor()
        engine.beginEdit()
        isSpecialSelectorPresented = false
        let index = min(max(0, cursor.row), track.terminatorIndex)
        engine.insertEvent(trackID: trackID, at: index, .specialControllerPlaceholder)
        cursor = TrackCursor(row: index, column: .note)
        specialInsert = SpecialInsertSession(row: index, code: nil, fields: [], fieldIndex: 0)
        beginSpecialSymbolEdit(at: index)
    }

    private func beginSpecialSymbolEdit(at index: Int) {
        cursor = TrackCursor(row: index, column: .note)
        inlineText = ""
        inlineEditorSessionID += 1
        inlineEditor = InlineEditor(
            row: index,
            kind: .symbol,
            origin: .insertedSpecial,
            sessionID: inlineEditorSessionID,
            selectsText: false,
            copiedNotePreview: nil
        )
        isKeyboardFocused = false
    }

    private func handleInsertedSpecialNavigation(
        direction: TrackCursorDirection
    ) -> KeyPress.Result {
        guard let editor = inlineEditor else { return .ignored }
        switch editor.kind {
        case .symbol:
            if SpecialController.symbolInputAction(forDownArrow: direction == .down) == .openSelector {
                openSpecialSelector()
                return .handled
            }
            return handleSpecialInsertCommit()
        case .special, .numeric, .note:
            return handleSpecialInsertCommit()
        }
    }

    private func handleSpecialInsertCommit() -> KeyPress.Result {
        guard let editor = inlineEditor, editor.origin == .insertedSpecial else {
            return .ignored
        }
        switch editor.kind {
        case .symbol:
            commitSpecialSymbol(inlineText)
        case .special:
            commitSpecialField(inlineText)
        case .numeric, .note:
            commitSpecialField(inlineText)
        }
        return .handled
    }

    private func commitSpecialSymbol(_ text: String) {
        // An empty symbol is a request to choose an event, not a cancelled insert.
        // In particular, Right advances from this field just like Return.
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            openSpecialSelector()
            return
        }
        guard let session = specialInsert else {
            cancelInlineEditor()
            return
        }
        guard let code = SpecialController.code(from: text) else {
            cancelSpecialInsert()
            return
        }
        applySpecialCode(code, at: session.row)
    }

    private func applySpecialCode(_ code: SpecialControllerCode, at index: Int) {
        guard let track, track.events.indices.contains(index) else {
            cancelSpecialInsert()
            return
        }
        let event = SpecialController.makeEvent(
            code,
            previousEvents: track.events.prefix(index),
            trackMIDIChannel: track.midiChannel
        )
        engine.updateEvent(trackID: trackID, index: index, event)
        let fields = SpecialController.fields(for: code)
        specialInsert = SpecialInsertSession(
            row: index,
            code: code,
            fields: fields,
            fieldIndex: 0
        )
        resetInlineEditor()
        beginNextSpecialField()
    }

    private func beginNextSpecialField() {
        guard var session = specialInsert else { return }
        guard session.fieldIndex < session.fields.count else {
            finishSpecialInsert()
            return
        }
        let field = session.fields[session.fieldIndex]
        session.fieldIndex += 1
        specialInsert = session
        cursor = TrackCursor(row: session.row, column: SpecialController.column(for: field))
        let initialText = specialFieldInitialText(field, row: session.row)
        inlineText = initialText
        inlineEditorSessionID += 1
        inlineEditor = InlineEditor(
            row: session.row,
            kind: .special(field),
            origin: .insertedSpecial,
            sessionID: inlineEditorSessionID,
            selectsText: true,
            copiedNotePreview: nil
        )
        isKeyboardFocused = false
    }

    private func specialFieldInitialText(_ field: SpecialControllerField, row: Int) -> String {
        guard let track, track.events.indices.contains(row) else { return "" }
        let event = track.events[row]
        switch field {
        case .stepTime:
            return event.delay == 0 ? "" : "\(event.delay)"
        case .gateTime:
            let displayed = event.command == 0xeb ? Int(event.param1 & 127) : Int(event.param1)
            return displayed == 0 ? "" : "\(displayed)"
        case .midiChannel:
            return event.param1 == 0 ? "" : "\(event.param1)"
        case .velocity:
            return event.param2 == 0 ? "" : "\(event.param2)"
        case .pitchBend:
            let bend = SpecialController.pitchValue(param1: event.param1, param2: event.param2)
            return bend == 0 ? "" : "\(bend)"
        }
    }

    private func commitSpecialField(_ text: String) {
        guard let editor = inlineEditor,
              case .special(let field) = editor.kind,
              let track,
              track.events.indices.contains(editor.row)
        else {
            cancelSpecialInsert()
            return
        }
        var event = track.events[editor.row]
        let range = SpecialController.numericRange(for: field)
        let maximumLength = field == .pitchBend
            ? TrackerTextInput.symbolMaximumLength
            : TrackerTextInput.maximumLength
        let value = TrackerTextInput.numericValue(
            text,
            in: range,
            maximumLength: maximumLength
        ) ?? range.lowerBound

        switch field {
        case .stepTime:
            event.delay = UInt8(clamping: value)
        case .gateTime, .midiChannel:
            event.param1 = UInt8(clamping: value)
        case .velocity:
            event.param2 = UInt8(clamping: value)
        case .pitchBend:
            event = SpecialController.pitchBendEvent(delay: event.delay, bend: value)
        }
        engine.updateEvent(trackID: trackID, index: editor.row, event)
        resetInlineEditor()
        beginNextSpecialField()
    }

    private func finishSpecialInsert() {
        engine.endEdit()
        let row = specialInsert?.row ?? cursor.row
        specialInsert = nil
        isSpecialSelectorPresented = false
        resetInlineEditor()
        cursor = TrackCursor(row: row, column: .note)
        if let track {
            let rowCount = track.eventRows(
                timeBase: engine.song?.timeBase ?? 48,
                beatNumerator: engine.song?.beatNumerator ?? 4,
                beatDenominator: engine.song?.beatDenominator ?? 4
            ).count
            cursor.move(.down, rowCount: rowCount)
        }
        isKeyboardFocused = true
    }

    private func cancelSpecialInsert() {
        isSpecialSelectorPresented = false
        specialInsert = nil
        cancelInlineEditor()
    }

    private func openSpecialSelector() {
        resetInlineEditor()
        specialSelectorIndex = 0
        isSpecialSelectorPresented = true
        isKeyboardFocused = true
    }

    private func confirmSpecialSelector() {
        guard let symbol = SpecialController.selectorSymbol(
            at: specialSelectorIndex,
            confirming: true
        ) else { return }
        isSpecialSelectorPresented = false
        commitSpecialSymbol(symbol)
    }

    private func dismissSpecialSelector() {
        isSpecialSelectorPresented = false
        if let row = specialInsert?.row {
            beginSpecialSymbolEdit(at: row)
        } else {
            isKeyboardFocused = true
        }
    }

    private func handleSpecialSelectorKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .escape:
            dismissSpecialSelector()
            return .handled
        case .return:
            confirmSpecialSelector()
            return .handled
        case .space:
            dismissSpecialSelector()
            return .handled
        default:
            break
        }
        let characters = press.characters.uppercased()
        if press.characters == "\u{1b}" {
            dismissSpecialSelector()
            return .handled
        }
        if characters.count == 1, let character = characters.first, character.isLetter {
            if let index = SpecialController.selectorItems.prefix(18).firstIndex(where: {
                $0.symbol.first == character
            }) {
                specialSelectorIndex = index
                return .handled
            }
        }
        return .ignored
    }

    private func handleSpecialSelectorDirection(_ direction: TrackCursorDirection) -> KeyPress.Result {
        switch direction {
        case .up:
            specialSelectorIndex = SpecialController.nextSelectorIndex(from: specialSelectorIndex, movingDown: false)
        case .down:
            specialSelectorIndex = SpecialController.nextSelectorIndex(from: specialSelectorIndex, movingDown: true)
        case .left, .right:
            dismissSpecialSelector()
        }
        return .handled
    }

    private func openToneSelectorIfNeeded() -> Bool {
        guard let editor = inlineEditor, editor.column == .gt,
              let track, track.events.indices.contains(editor.row),
              track.events[editor.row].command == 0xec || track.events[editor.row].command == 0xe2
        else { return false }
        toneEditor = editor
        toneDraft = inlineText
        toneIndex = inlineText.isEmpty
            ? Int(track.events[editor.row].param1)
            : TrackerTextInput.numericValue(inlineText, in: 0...127) ?? 0
        toneIndex = min(127, toneIndex)
        resetInlineEditor()
        isKeyboardFocused = true
        return true
    }

    private func closeToneSelector(confirming: Bool) {
        guard let editor = toneEditor else { return }
        isToneSelectorFocused = false
        isKeyboardFocused = false
        toneEditor = nil
        inlineEditorSessionID += 1
        inlineEditor = InlineEditor(
            row: editor.row, kind: editor.kind, origin: editor.origin,
            sessionID: inlineEditorSessionID, selectsText: true, copiedNotePreview: nil
        )
        inlineText = confirming ? String(toneIndex) : toneDraft
        if confirming {
            if editor.origin == .insertedSpecial {
                commitSpecialField(inlineText)
            } else {
                commitInlineEditor()
            }
        } else {
            isKeyboardFocused = false
        }
        // Restore focus after the selector's focusable view has been removed.
        if inlineEditor == nil {
            DispatchQueue.main.async {
                isKeyboardFocused = true
            }
        }
    }

    private var toneSelectorOverlay: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TONE LIST")
                .font(TrackerLayout.headerFont)
            Text("GM / SC-55 CAPITAL · 0–127")
                .font(.caption)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(ProgramToneList.names.indices, id: \.self) { index in
                            Button {
                                toneIndex = index
                                closeToneSelector(confirming: true)
                            } label: {
                                Text(String(format: "%3d: %@", index, ProgramToneList.names[index]))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.vertical, 2)
                                    .foregroundStyle(index == toneIndex ? TrackerPalette.crt : TrackerPalette.paper)
                                    .background(index == toneIndex ? TrackerPalette.cell : Color.clear)
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                }
                .onAppear { proxy.scrollTo(toneIndex, anchor: .center) }
                .onChange(of: toneIndex) { _, index in proxy.scrollTo(index, anchor: .center) }
            }
            Text("↑↓ 選択  ←→ 16音色移動  Enter 決定  Esc 戻る")
                .font(.caption)
        }
        .font(TrackerLayout.rowFont)
        .foregroundStyle(TrackerPalette.paper)
        .padding(12)
        .frame(maxWidth: 420, maxHeight: 560)
        .background(TrackerPalette.crt)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(TrackerPalette.phosphor))
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .background {
            Color.black.opacity(0.35)
                .onTapGesture { closeToneSelector(confirming: false) }
        }
        .focusable()
        .focused($isToneSelectorFocused)
        .focusEffectDisabled()
        .onAppear { isToneSelectorFocused = true }
        .onKeyPress(phases: [.down, .repeat]) { press in
            if press.modifiers.contains(.command) { return .ignored }
            switch press.key {
            case .upArrow: toneIndex = ProgramToneList.moved(toneIndex, by: -1)
            case .downArrow: toneIndex = ProgramToneList.moved(toneIndex, by: 1)
            case .leftArrow, .pageUp: toneIndex = ProgramToneList.moved(toneIndex, by: -16)
            case .rightArrow, .pageDown: toneIndex = ProgramToneList.moved(toneIndex, by: 16)
            case .return: closeToneSelector(confirming: true)
            case .escape: closeToneSelector(confirming: false)
            default: break
            }
            return .handled
        }
    }

    private var specialSelectorOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(" SPECIAL CONTROLER")
                .font(TrackerLayout.headerFont)
                .foregroundStyle(TrackerPalette.paper)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            ForEach(Array(SpecialController.selectorItems.enumerated()), id: \.offset) { index, item in
                if item.symbol.isEmpty {
                    Rectangle()
                        .fill(TrackerPalette.dim.opacity(0.5))
                        .frame(height: 1)
                        .padding(.vertical, 4)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                } else {
                    let selected = index == specialSelectorIndex
                    HStack(spacing: 6) {
                        Text(item.symbol.isEmpty ? "   " : "[\(item.symbol)]")
                            .frame(width: TrackerLayout.width(5), alignment: .leading)
                        Text(item.name)
                            .frame(width: TrackerLayout.width(9), alignment: .leading)
                        Text(item.comment)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(TrackerLayout.rowFont)
                    .foregroundStyle(selected ? TrackerPalette.crt : TrackerPalette.paper)
                    .background(selected ? TrackerPalette.cell : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        specialSelectorIndex = index
                        confirmSpecialSelector()
                    }
                }
            }
        }
        .padding(12)
        .background(TrackerPalette.crt.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(TrackerPalette.phosphor, lineWidth: 1)
        )
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .background {
            Color.black.opacity(0.35)
                .onTapGesture { dismissSpecialSelector() }
        }
    }

    private func keyboardNoteCharacter(from press: KeyPress) -> Character? {
        let characters = Array(press.characters.uppercased())
        guard characters.count == 1,
              let character = characters.first,
              "ABCDEFG".contains(character)
        else { return nil }
        return character
    }

    private func keyboardDigit(from press: KeyPress) -> Int? {
        let characters = Array(press.characters)
        guard characters.count == 1,
              let digit = characters[0].wholeNumberValue,
              (0...9).contains(digit)
        else { return nil }
        return digit
    }

    private func playFromCursorMeasure(_ track: Track) {
        let measure = cursorMeasure(track)
        Task {
            do {
                try await engine.play(fromMeasure: measure)
            } catch {
                engine.reportAudioError(error)
            }
        }
    }

    private func cursorMeasure(_ track: Track) -> Int {
        guard let song = engine.song else { return engine.positionTime.measure }
        let rows = track.eventRows(
            timeBase: song.timeBase,
            beatNumerator: song.beatNumerator,
            beatDenominator: song.beatDenominator
        )
        if rows.indices.contains(cursor.row) {
            return rows[cursor.row].time.measure
        }
        return engine.positionTime.measure
    }

    private func channelText(_ track: Track) -> String {
        guard let channel = track.midiChannel else { return "OFF" }
        return "A \(channel)"
    }
}

private struct TrackerInlineEditorField: View {
    private static let characterWidth = TrackerLayout.characterWidth
    private static let fieldHeight = TrackerLayout.cellHeight

    private var bufferWidth: CGFloat {
        CGFloat(TrackerTextInput.maximumLength(for: mode)) * Self.characterWidth
    }

    let mode: TrackerTextInputMode
    let copiedNotePreview: String?
    let isTrailing: Bool
    let onTextChange: (String) -> Void
    let onCancel: () -> Void

    @State private var input: TrackerTextInputSession
    @State private var hasDismissedPreview = false
    @FocusState private var isFocused: Bool

    init(
        mode: TrackerTextInputMode,
        initialText: String,
        selectAll: Bool,
        copiedNotePreview: String?,
        isTrailing: Bool,
        onTextChange: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.copiedNotePreview = copiedNotePreview
        self.isTrailing = isTrailing
        self.onTextChange = onTextChange
        self.onCancel = onCancel
        _input = State(
            initialValue: TrackerTextInputSession(
                mode: mode,
                initialText: initialText,
                selectAll: selectAll
            )
        )
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let caretVisible = Int(timeline.date.timeIntervalSinceReferenceDate / 0.5)
                .isMultiple(of: 2)
            let displayText = hasDismissedPreview || !input.text.isEmpty
                ? input.text
                : copiedNotePreview ?? input.text

            ZStack(alignment: .leading) {
                if input.isAllSelected {
                    Rectangle()
                        .fill(Color.blue.opacity(0.82))
                        .frame(width: selectedTextWidth, height: Self.fieldHeight)
                        .offset(x: selectedTextOffset)
                }

                HStack(spacing: 0) {
                    if isTrailing {
                        Spacer(minLength: leadingEmptyWidth)
                    }

                    ForEach(Array(displayText.enumerated()), id: \.offset) { _, character in
                        Text(String(character))
                            .frame(
                                width: Self.characterWidth,
                                height: Self.fieldHeight,
                                alignment: .leading
                            )
                    }

                    if !isTrailing {
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: bufferWidth, alignment: .leading)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1, height: TrackerLayout.caretHeight)
                    .opacity(caretVisible && !input.isAllSelected ? 1 : 0)
                    .offset(x: caretOffset)
            }
            .font(TrackerLayout.rowFont)
            .foregroundStyle(TrackerPalette.crt)
            .frame(width: bufferWidth, height: Self.fieldHeight, alignment: .leading)
        }
        .frame(width: bufferWidth, height: Self.fieldHeight)
        .padding(.horizontal, 2)
        .background(TrackerPalette.cell)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            isFocused = true
        }
        .onKeyPress(phases: .down) { press in
            if press.modifiers.contains(.command) { return .ignored }
            switch press.key {
            case .escape:
                onCancel()
                return .handled
            case .return:
                return .ignored
            case .upArrow, .downArrow, .leftArrow, .rightArrow, .space, .pageUp, .pageDown:
                return .ignored
            case .home:
                hasDismissedPreview = true
                input.apply(.moveToBeginning)
                return .handled
            case .end:
                hasDismissedPreview = true
                input.apply(.moveToEnd)
                return .handled
            case .clear:
                hasDismissedPreview = true
                input.apply(.clear)
                onTextChange(input.text)
                return .handled
            case .delete, .deleteForward:
                hasDismissedPreview = true
                // macOS's Delete key is a backward delete. SwiftUI can
                // expose it as either delete equivalent depending on the
                // keyboard, so both key forms follow the Mac behavior.
                input.apply(.deleteBackward)
                onTextChange(input.text)
                return .handled
            default:
                break
            }

            if press.characters == "\u{1b}" {
                onCancel()
                return .handled
            }
            if press.characters == "\u{8}" {
                hasDismissedPreview = true
                input.apply(.deleteBackward)
                onTextChange(input.text)
                return .handled
            }
            if press.characters == "\u{7f}" {
                hasDismissedPreview = true
                input.apply(.deleteBackward)
                onTextChange(input.text)
                return .handled
            }

            guard !press.characters.isEmpty else { return .ignored }
            hasDismissedPreview = true
            input.insert(press.characters)
            onTextChange(input.text)
            return .handled
        }
    }

    private var leadingEmptyWidth: CGFloat {
        CGFloat(leadingEmptySlots) * Self.characterWidth
    }

    private var caretOffset: CGFloat {
        return CGFloat(leadingEmptySlots + input.caretPosition) * Self.characterWidth
    }

    private var selectedTextOffset: CGFloat {
        return CGFloat(leadingEmptySlots) * Self.characterWidth
    }

    private var selectedTextWidth: CGFloat {
        CGFloat(input.text.count) * Self.characterWidth
    }

    private var leadingEmptySlots: Int {
        isTrailing
            ? max(0, TrackerTextInput.maximumLength(for: mode) - input.text.count)
            : 0
    }
}

private struct FlickKeyPad: View {
    let pad: FlickPad
    var onInput: (TrackEditInput) -> Void
    @State private var translation: CGSize = .zero
    @State private var preview: FlickDirection = .tap

    var body: some View {
        let labels = pad.labels
        let shown = previewLabel
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(TrackerPalette.crt)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(TrackerPalette.padEdge, lineWidth: 1.5)
                )

            if let up = labels.up {
                Text(up)
                    .offset(y: -34)
                    .foregroundStyle(preview == .up ? TrackerPalette.cell : TrackerPalette.dim)
            }
            if let down = labels.down {
                Text(down)
                    .offset(y: 34)
                    .foregroundStyle(preview == .down ? TrackerPalette.cell : TrackerPalette.dim)
            }
            if let left = labels.left {
                Text(left)
                    .offset(x: -30)
                    .foregroundStyle(preview == .left ? TrackerPalette.cell : TrackerPalette.dim)
            }
            if let right = labels.right {
                Text(right)
                    .offset(x: 30)
                    .foregroundStyle(preview == .right ? TrackerPalette.cell : TrackerPalette.dim)
            }

            Text(shown)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .foregroundStyle(TrackerPalette.phosphor)
                .offset(
                    x: min(18, max(-18, translation.width * 0.18)),
                    y: min(18, max(-18, translation.height * 0.18))
                )
        }
        .font(.system(size: TrackerLayout.fontSize, weight: .semibold, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    translation = value.translation
                    preview = FlickDirection.from(value.translation)
                }
                .onEnded { value in
                    let direction = FlickDirection.from(value.translation)
                    if let input = pad.value(for: direction) {
                        onInput(input)
                    }
                    translation = .zero
                    preview = .tap
                }
        )
    }

    private var previewLabel: String {
        switch preview {
        case .tap: return pad.labels.center
        case .left: return pad.labels.left ?? pad.labels.center
        case .up: return pad.labels.up ?? pad.labels.center
        case .right: return pad.labels.right ?? pad.labels.center
        case .down: return pad.labels.down ?? pad.labels.center
        }
    }
}

private extension FlickPad {
    var labels: (center: String, left: String?, up: String?, right: String?, down: String?) {
        switch self {
        case .digitsLow: return ("0", "1", "2", "3", "4")
        case .digitsHigh: return ("5", "6", "7", "8", "9")
        case .notesAC: return ("A", "B", "C", nil, nil)
        case .notesDG: return ("D", "E", "F", "G", nil)
        }
    }
}

private extension FlickDirection {
    static func from(_ translation: CGSize, threshold: CGFloat = 28) -> FlickDirection {
        if hypot(translation.width, translation.height) < threshold {
            return .tap
        }
        if abs(translation.width) > abs(translation.height) {
            return translation.width < 0 ? .left : .right
        }
        return translation.height < 0 ? .up : .down
    }
}

struct TrackSettingsView: View {
    @State private var channel: Int
    @State private var startTick: Int
    @State private var keyShift: Int
    @State private var memo: String
    var onSave: (Int?, Int, Int, String) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        track: Track,
        onSave: @escaping (Int?, Int, Int, String) -> Void
    ) {
        _channel = State(initialValue: track.midiChannel ?? 0)
        _startTick = State(initialValue: track.startTick)
        _keyShift = State(initialValue: track.keyShift)
        _memo = State(initialValue: track.memo)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("MIDIチャンネル", selection: $channel) {
                    Text("OFF").tag(0)
                    ForEach(1...16, id: \.self) { channel in
                        Text("Ch \(channel)").tag(channel)
                    }
                }
                Stepper(value: $startTick, in: -99...99) {
                    Text("開始位置（tick）: \(startTick)")
                        .font(.body.monospacedDigit())
                }
                Stepper(value: $keyShift, in: -64...63) {
                    Text("移調（半音）: \(keyShift)")
                        .font(.body.monospacedDigit())
                }
                TextField("トラック名", text: $memo)
                    .onChange(of: memo) { _, newValue in
                        if newValue.count > 36 {
                            memo = String(newValue.prefix(36))
                        }
                    }
            }
            .formStyle(.grouped)
            .navigationTitle("トラック設定")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("適用") {
                        onSave(channel == 0 ? nil : channel, startTick, keyShift, memo)
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }
}
