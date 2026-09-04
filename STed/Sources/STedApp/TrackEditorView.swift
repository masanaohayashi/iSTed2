import SwiftUI
import STedCore
import STedPlayback

private enum TrackerPalette {
    static let crt = Color(red: 0.04, green: 0.055, blue: 0.09)
    static let phosphor = Color(red: 0.50, green: 0.91, blue: 0.88)
    static let dim = Color(red: 0.28, green: 0.55, blue: 0.54)
    static let cell = Color(red: 0.37, green: 0.88, blue: 0.84)
    static let playhead = Color(red: 0.12, green: 0.28, blue: 0.30)
    static let pad = Color(red: 0.09, green: 0.12, blue: 0.18)
    static let padEdge = Color(red: 0.22, green: 0.38, blue: 0.40)
    static let danger = Color(red: 0.86, green: 0.38, blue: 0.32)
    static let insert = Color(red: 0.95, green: 0.78, blue: 0.32)
}

struct TrackEditorView: View {
    private enum InlineEditorKind: Equatable {
        case numeric(EventColumn)
        case note
    }

    private struct InlineEditor: Equatable {
        let row: Int
        let kind: InlineEditorKind

        var column: EventColumn {
            switch kind {
            case .numeric(let column): return column
            case .note: return .note
            }
        }
    }

    @EnvironmentObject private var engine: PlaybackEngine
    let trackID: Int
    @State private var cursor = TrackCursor()
    @State private var inlineEditor: InlineEditor?
    @State private var inlineText = ""
    @FocusState private var isKeyboardFocused: Bool
    @State private var isTrackSettingsPresented = false

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
            resetInlineEditor()
            normalizeCursor()
            isKeyboardFocused = true
        }
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
                    .frame(height: max(160, geo.size.height * 0.48))

                inputDeck
                    .frame(maxHeight: .infinity)
            }
        }
        .focusable()
        .focused($isKeyboardFocused)
        .focusEffectDisabled()
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
            guard inlineEditor == nil else { return .ignored }
            return moveCursor(for: press.key, rowCount: rows.count)
        }
        .onKeyPress(.return, phases: .down) { _ in
            if inlineEditor != nil {
                commitInlineEditor()
            } else {
                insertNoteBeforeCursor()
            }
            return .handled
        }
        .onKeyPress(phases: .down) { press in
            guard inlineEditor == nil else { return .ignored }
            if let digit = keyboardDigit(from: press) {
                return beginNumericEdit(String(digit)) ? .handled : .ignored
            }
            if let note = keyboardNoteCharacter(from: press) {
                return beginNoteEdit(note) ? .handled : .ignored
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
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
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
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(TrackerPalette.phosphor)

            TransportBar(compact: true)
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
                .frame(width: 36, alignment: .trailing)
            Text("STEP")
                .frame(width: 36, alignment: .trailing)
            Text(":")
            columnTitle("NOTE K#", .note)
                .frame(maxWidth: .infinity, alignment: .leading)
            columnTitle("ST", .st)
                .frame(width: 44, alignment: .trailing)
            columnTitle("GT", .gt)
                .frame(width: 52, alignment: .trailing)
            columnTitle("VEL", .vel)
                .frame(width: 48, alignment: .trailing)
        }
        .font(.system(size: 11, weight: .bold, design: .monospaced))
        .foregroundStyle(Color.white.opacity(0.9))
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .background(TrackerPalette.dim.opacity(0.55))
    }

    private func columnTitle(_ title: String, _ column: EventColumn) -> some View {
        Text(title)
            .foregroundStyle(cursor.column == column ? TrackerPalette.cell : Color.white.opacity(0.9))
            .onTapGesture {
                resetInlineEditor()
                cursor.column = column
                isKeyboardFocused = true
            }
    }

    private func trackerList(rows: [EventRow]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        trackerRow(index: index, row: row)
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

    private func trackerRow(index: Int, row: EventRow) -> some View {
        let isSelected = cursor.row == index
        let isPlayhead = row.time.tick <= engine.positionTick
        return HStack(spacing: 0) {
            Text(row.showsMeasure ? String(format: "%3d", row.time.measure) : "")
                .frame(width: 36, alignment: .trailing)
            Text(row.stepNumber.map { String(format: "%3d", $0) } ?? "")
                .frame(width: 36, alignment: .trailing)
            Text(":")
            cell(row.noteText, column: .note, index: index, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            cell(row.stText, column: .st, index: index, alignment: .trailing)
                .frame(width: 44, alignment: .trailing)
            cell(row.gtText, column: .gt, index: index, alignment: .trailing)
                .frame(width: 52, alignment: .trailing)
            cell(row.velText, column: .vel, index: index, alignment: .trailing)
                .frame(width: 48, alignment: .trailing)
        }
        .font(.system(size: 13, weight: .medium, design: .monospaced))
        .foregroundStyle(TrackerPalette.phosphor)
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .background {
            if isSelected {
                TrackerPalette.playhead.opacity(0.85)
            } else if isPlayhead {
                TrackerPalette.playhead.opacity(0.35)
            } else {
                Color.clear
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            resetInlineEditor()
            cursor.row = index
            isKeyboardFocused = true
        }
    }

    @ViewBuilder
    private func cell(
        _ text: String,
        column: EventColumn,
        index: Int,
        alignment: Alignment
    ) -> some View {
        let active = cursor.row == index && cursor.column == column
        if let inlineEditor,
           inlineEditor.row == index,
           inlineEditor.column == column {
            inlineEditorField(kind: inlineEditor.kind, isTrailing: column != .note)
                .frame(maxWidth: .infinity, alignment: alignment)
        } else {
            Text(text)
                .frame(maxWidth: .infinity, alignment: alignment)
                .padding(.horizontal, 2)
                .background(active ? TrackerPalette.cell : Color.clear)
                .foregroundStyle(active ? TrackerPalette.crt : TrackerPalette.phosphor)
                .onTapGesture {
                    resetInlineEditor()
                    cursor = TrackCursor(row: index, column: column)
                    isKeyboardFocused = true
                }
        }
    }

    private func inlineEditorField(
        kind: InlineEditorKind,
        isTrailing: Bool
    ) -> some View {
        TrackerInlineEditorField(
            mode: inlineEditorMode(for: kind),
            initialText: inlineText,
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
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .foregroundStyle(TrackerPalette.crt)
                        .background(TrackerPalette.insert)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: deleteEvent) {
                    Text("削除")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
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

    private func deleteEvent() {
        guard let track, cursor.row < track.terminatorIndex else { return }
        resetInlineEditor()
        let index = cursor.row
        engine.deleteEvent(trackID: trackID, at: index)
        let newTerminatorIndex = max(0, track.terminatorIndex - 1)
        cursor.row = min(index, newTerminatorIndex)
        isKeyboardFocused = true
    }

    private func moveCursor(for key: KeyEquivalent, rowCount: Int) -> KeyPress.Result {
        let direction: TrackCursorDirection?
        switch key {
        case .upArrow: direction = .up
        case .downArrow: direction = .down
        case .leftArrow: direction = .left
        case .rightArrow: direction = .right
        default: direction = nil
        }

        guard let direction else { return .ignored }
        resetInlineEditor()
        cursor.move(direction, rowCount: rowCount)
        isKeyboardFocused = true
        return .handled
    }

    private func insertNoteBeforeCursor() {
        guard let track else { return }
        resetInlineEditor()
        let index = min(max(0, cursor.row), track.terminatorIndex)
        engine.insertNoteBefore(trackID: trackID, at: index)
        cursor = TrackCursor(row: index, column: .note)
        isKeyboardFocused = true
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

    private func beginNumericEdit(_ initialText: String) -> Bool {
        guard let track else { return false }
        let index = cursor.row
        guard track.events.indices.contains(index),
              index < track.terminatorIndex,
              track.events[index].command < 0x80
        else { return false }

        inlineText = TrackerTextInput.normalizedNumeric(initialText)
        inlineEditor = InlineEditor(row: index, kind: .numeric(cursor.column))
        isKeyboardFocused = false
        return true
    }

    private func beginNoteEdit(_ initialCharacter: Character) -> Bool {
        guard let track else { return false }
        let index = cursor.row
        guard track.events.indices.contains(index),
              index < track.terminatorIndex,
              track.events[index].command < 0x80
        else { return false }

        cursor.column = .note
        inlineText = TrackerTextInput.normalizedNote(String(initialCharacter))
        inlineEditor = InlineEditor(row: index, kind: .note)
        isKeyboardFocused = false
        return true
    }

    private func commitInlineEditor(text draftText: String? = nil) {
        guard let inlineEditor,
              let track,
              track.events.indices.contains(inlineEditor.row),
              inlineEditor.row < track.terminatorIndex,
              track.events[inlineEditor.row].command < 0x80
        else {
            cancelInlineEditor()
            return
        }

        let event = track.events[inlineEditor.row]
        let draftText = draftText ?? inlineText
        let value: Int?
        switch inlineEditor.kind {
        case .numeric(let column):
            value = TrackerTextInput.numericValue(draftText, in: column)
        case .note:
            value = TrackerTextInput.noteNumber(
                draftText,
                referenceNote: Int(event.command)
            )
        }

        if let value {
            let column = inlineEditor.column
            engine.updateEvent(
                trackID: trackID,
                index: inlineEditor.row,
                event.settingNumericValue(value, in: column)
            )
        }
        resetInlineEditor()
        isKeyboardFocused = true
    }

    private func cancelInlineEditor() {
        resetInlineEditor()
        isKeyboardFocused = true
    }

    private func resetInlineEditor() {
        inlineEditor = nil
        inlineText = ""
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
    private static let characterWidth: CGFloat = 8
    private static let bufferWidth = CGFloat(TrackerTextInput.maximumLength) * characterWidth

    let mode: TrackerTextInputMode
    let isTrailing: Bool
    let onTextChange: (String) -> Void
    let onCancel: () -> Void

    @State private var input: TrackerTextInputSession
    @FocusState private var isFocused: Bool

    init(
        mode: TrackerTextInputMode,
        initialText: String,
        isTrailing: Bool,
        onTextChange: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.isTrailing = isTrailing
        self.onTextChange = onTextChange
        self.onCancel = onCancel
        _input = State(
            initialValue: TrackerTextInputSession(mode: mode, initialText: initialText)
        )
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let caretVisible = Int(timeline.date.timeIntervalSinceReferenceDate / 0.5)
                .isMultiple(of: 2)

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    if isTrailing {
                        Spacer(minLength: leadingEmptyWidth)
                    }

                    ForEach(Array(input.text.enumerated()), id: \.offset) { _, character in
                        Text(String(character))
                            .frame(
                                width: Self.characterWidth,
                                height: 22,
                                alignment: .leading
                            )
                    }

                    if !isTrailing {
                        Spacer(minLength: 0)
                    }
                }
                .frame(width: Self.bufferWidth, alignment: .leading)

                Rectangle()
                    .fill(Color.white)
                    .frame(width: 1, height: 18)
                    .opacity(caretVisible ? 1 : 0)
                    .offset(x: caretOffset)
            }
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(TrackerPalette.crt)
            .frame(width: Self.bufferWidth, height: 22, alignment: .leading)
        }
        .frame(width: Self.bufferWidth, height: 22)
        .padding(.horizontal, 2)
        .background(TrackerPalette.cell)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            isFocused = true
        }
        .onKeyPress(.escape, phases: .down) { _ in
            onCancel()
            return .handled
        }
        .onKeyPress(keys: [.home, .end], phases: [.down, .repeat]) { press in
            switch press.key {
            case .home:
                input.moveToBeginning()
            case .end:
                input.moveToEnd()
            default:
                return .ignored
            }
            return .handled
        }
        .onKeyPress(.clear, phases: .down) { _ in
            input.clear()
            onTextChange(input.text)
            return .handled
        }
        .onKeyPress(keys: [.leftArrow, .rightArrow], phases: [.down, .repeat]) { press in
            switch press.key {
            case .leftArrow:
                input.moveLeft()
            case .rightArrow:
                input.moveRight()
            default:
                return .ignored
            }
            onTextChange(input.text)
            return .handled
        }
        .onKeyPress(phases: .down) { press in
            if press.key == .return {
                return .ignored
            }
            if press.key == .delete || press.characters == "\u{8}" {
                input.backspace()
                onTextChange(input.text)
                return .handled
            }
            if press.key == .deleteForward || press.characters == "\u{7f}" {
                input.delete()
                onTextChange(input.text)
                return .handled
            }
            guard !press.characters.isEmpty else { return .ignored }
            input.insert(press.characters)
            onTextChange(input.text)
            return .handled
        }
    }

    private var leadingEmptyWidth: CGFloat {
        CGFloat(max(0, TrackerTextInput.maximumLength - input.text.count)) * Self.characterWidth
    }

    private var caretOffset: CGFloat {
        let leadingEmptySlots = isTrailing
            ? max(0, TrackerTextInput.maximumLength - input.text.count)
            : 0
        return CGFloat(leadingEmptySlots + input.caretPosition) * Self.characterWidth
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
        .font(.system(size: 13, weight: .semibold, design: .monospaced))
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

private struct TrackSettingsView: View {
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
                Stepper(value: $channel, in: 0...16) {
                    Text(channel == 0 ? "Ch OFF" : "Ch \(channel)")
                        .font(.body.monospacedDigit())
                }
                Stepper(value: $startTick, in: -99...99) {
                    Text("ST+ \(startTick)")
                        .font(.body.monospacedDigit())
                }
                Stepper(value: $keyShift, in: -64...63) {
                    Text("K#+ \(keyShift)")
                        .font(.body.monospacedDigit())
                }
                TextField("メモ", text: $memo)
                    .onChange(of: memo) { _, newValue in
                        if newValue.count > 36 {
                            memo = String(newValue.prefix(36))
                        }
                    }
            }
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
    }
}
