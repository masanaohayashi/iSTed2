import XCTest
@testable import STedCore

final class TrackEditInputTests: XCTestCase {
    func testNumericInputStartsWithTheFirstDigitAndBuildsTheValue() {
        var input = NumericInput()

        XCTAssertEqual(input.enter(4, range: EventColumn.st.numericRange), 4)
        XCTAssertEqual(input.enter(8, range: EventColumn.st.numericRange), 48)
    }

    func testNumericInputClipsAtTheSelectedColumnMaximum() {
        var input = NumericInput()

        _ = input.enter(9, range: EventColumn.gt.numericRange)
        _ = input.enter(9, range: EventColumn.gt.numericRange)
        XCTAssertEqual(input.enter(9, range: EventColumn.gt.numericRange), 255)

        input.reset()
        _ = input.enter(1, range: EventColumn.note.numericRange)
        _ = input.enter(2, range: EventColumn.note.numericRange)
        XCTAssertEqual(input.enter(8, range: EventColumn.note.numericRange), 127)
    }

    func testSettingNumericValueClipsAndWritesTheSelectedField() {
        let original = TrackEvent(command: 60, delay: 48, param1: 36, param2: 100)

        XCTAssertEqual(original.settingNumericValue(999, in: .st).delay, 255)
        XCTAssertEqual(original.settingNumericValue(-1, in: .gt).param1, 0)
        XCTAssertEqual(original.settingNumericValue(999, in: .vel).param2, 127)
        XCTAssertEqual(original.settingNumericValue(127, in: .note).command, 127)
    }

    func testNumericTextInputKeepsFourCharactersAndClipsOnCommit() {
        XCTAssertEqual(TrackerTextInput.normalizedNumeric("-12345"), "-123")
        XCTAssertEqual(TrackerTextInput.numericValue("9999", in: .gt), 255)
        XCTAssertEqual(TrackerTextInput.numericValue("-12", in: .vel), 0)
        XCTAssertEqual(TrackerTextInput.numericValue("-", in: .st), 0)
        XCTAssertEqual(TrackerTextInput.numericValue("", in: .st), 0)
    }

    func testInlineNoteInputPutsTheCaretAfterTheStarterCharacter() {
        var input = TrackerTextInputSession(mode: .note, initialText: "D")

        XCTAssertEqual(input.text, "D")
        XCTAssertEqual(input.caretPosition, 1)

        input.insert("3")

        XCTAssertEqual(input.text, "D3")
        XCTAssertEqual(input.caretPosition, 2)
    }

    func testInlineNoteInputWithoutAStarterBeginsAtTheStartOfTheBuffer() {
        let input = TrackerTextInputSession(mode: .note)

        XCTAssertEqual(input.text, "")
        XCTAssertEqual(input.caretPosition, 0)
    }

    func testInlineNumericInputAppendsAfterStarterAndStopsAtFourCharacters() {
        var input = TrackerTextInputSession(mode: .numeric, initialText: "5")

        input.insert("1234")

        XCTAssertEqual(input.text, "5123")
        XCTAssertEqual(input.caretPosition, 4)
    }

    func testInlineInputKeepsOriginalCursorEditingOperations() {
        var input = TrackerTextInputSession(mode: .note, initialText: "D3")

        input.moveLeft()
        input.insert("#")
        XCTAssertEqual(input.text, "D#3")
        XCTAssertEqual(input.caretPosition, 2)

        input.backspace()
        XCTAssertEqual(input.text, "D3")
        input.delete()
        XCTAssertEqual(input.text, "D")

        input.clear()
        XCTAssertEqual(input.text, "")
        XCTAssertEqual(input.caretPosition, 0)
    }

    func testInlineNumericInputCommandsKeepMacDeleteBackward() {
        var input = TrackerTextInputSession(mode: .numeric, initialText: "123")

        input.apply(.deleteBackward)
        XCTAssertEqual(input.text, "12")

        input.apply(.moveToBeginning)
        input.apply(.deleteForward)
        XCTAssertEqual(input.text, "2")

        input.apply(.clear)
        XCTAssertEqual(input.text, "")
        XCTAssertEqual(input.caretPosition, 0)
    }

    func testInlineInputSelectsExistingValueForReplacement() {
        var numeric = TrackerTextInputSession(
            mode: .numeric,
            initialText: "48",
            selectAll: true
        )

        XCTAssertTrue(numeric.isAllSelected)
        numeric.insert("2")
        XCTAssertEqual(numeric.text, "2")
        XCTAssertEqual(numeric.caretPosition, 1)
        XCTAssertFalse(numeric.isAllSelected)

        var signed = TrackerTextInputSession(
            mode: .numeric,
            initialText: "48",
            selectAll: true
        )
        signed.insert("-")
        XCTAssertEqual(signed.text, "-")

        var note = TrackerTextInputSession(
            mode: .note,
            initialText: "C4",
            selectAll: true
        )
        note.insert("D")
        XCTAssertEqual(note.text, "D")
    }

    func testNoteTextInputUsesTheOriginalCtcNoteSyntax() {
        XCTAssertEqual(TrackerTextInput.noteNumber("C4"), 60)
        XCTAssertEqual(TrackerTextInput.noteNumber("C#4"), 61)
        XCTAssertEqual(TrackerTextInput.noteNumber("Bb3"), 58)
        XCTAssertEqual(TrackerTextInput.noteNumber("C."), 0)
        XCTAssertEqual(TrackerTextInput.noteNumber("60"), 60)
        XCTAssertNil(TrackerTextInput.noteNumber("B9"))
    }

    func testLowDigitPadMapsFlickDirections() {
        XCTAssertEqual(FlickPad.digitsLow.value(for: .tap), .digit(0))
        XCTAssertEqual(FlickPad.digitsLow.value(for: .left), .digit(1))
        XCTAssertEqual(FlickPad.digitsLow.value(for: .up), .digit(2))
        XCTAssertEqual(FlickPad.digitsLow.value(for: .right), .digit(3))
        XCTAssertEqual(FlickPad.digitsLow.value(for: .down), .digit(4))
    }

    func testHighDigitPadMapsFlickDirections() {
        XCTAssertEqual(FlickPad.digitsHigh.value(for: .tap), .digit(5))
        XCTAssertEqual(FlickPad.digitsHigh.value(for: .left), .digit(6))
        XCTAssertEqual(FlickPad.digitsHigh.value(for: .up), .digit(7))
        XCTAssertEqual(FlickPad.digitsHigh.value(for: .right), .digit(8))
        XCTAssertEqual(FlickPad.digitsHigh.value(for: .down), .digit(9))
    }

    func testNotePadsMapAThroughG() {
        XCTAssertEqual(FlickPad.notesAC.value(for: .tap), .pitchClass(0))
        XCTAssertEqual(FlickPad.notesAC.value(for: .left), .pitchClass(1))
        XCTAssertEqual(FlickPad.notesAC.value(for: .up), .pitchClass(2))
        XCTAssertNil(FlickPad.notesAC.value(for: .right))
        XCTAssertNil(FlickPad.notesAC.value(for: .down))

        XCTAssertEqual(FlickPad.notesDG.value(for: .tap), .pitchClass(3))
        XCTAssertEqual(FlickPad.notesDG.value(for: .left), .pitchClass(4))
        XCTAssertEqual(FlickPad.notesDG.value(for: .up), .pitchClass(5))
        XCTAssertEqual(FlickPad.notesDG.value(for: .right), .pitchClass(6))
        XCTAssertNil(FlickPad.notesDG.value(for: .down))
    }

    func testDigitShiftsIntoSelectedField() {
        var event = TrackEvent.defaultNote
        event = event.applying(.digit(4), column: .st)
        event = event.applying(.digit(8), column: .st)
        XCTAssertEqual(event.delay, 48)

        event = event.applying(.digit(1), column: .st)
        event = event.applying(.digit(2), column: .st)
        XCTAssertEqual(event.delay, 12)
    }

    func testPitchClassKeepsOctave() {
        let event = TrackEvent(command: 60, delay: 48, param1: 36, param2: 100)
            .applying(.pitchClass(0), column: .note)
        XCTAssertEqual(event.command, 69)
        XCTAssertEqual(event.trackerCells.note, "A 4  69")
    }

    func testPitchClassIgnoredOnNonNotes() {
        let event = TrackEvent(command: 0xee, delay: 11, param1: 85, param2: 74)
            .applying(.pitchClass(3), column: .note)
        XCTAssertEqual(event.command, 0xee)
    }

    func testDeleteControlCharactersMapToEditorDeleteKeys() {
        XCTAssertEqual(TrackerEditorKey(characters: "\u{8}"), .backspaceCharacter)
        XCTAssertEqual(TrackerEditorKey(characters: "\u{7f}"), .forwardDeleteCharacter)
        XCTAssertNil(TrackerEditorKey(characters: "a"))
    }

    func testEscDuringNewNoteInputDeletesTheInsertedStep() {
        XCTAssertEqual(
            TrackerInlineCancelAction.forInsertedNote(true),
            .deleteInsertedStep
        )
        XCTAssertEqual(
            TrackerInlineCancelAction.forInsertedNote(false),
            .discardEdits
        )
    }

    func testLetterKeysInsertANoteOnMeasureLinesAndTheTerminator() {
        XCTAssertEqual(TrackerNoteKeyAction.forCommand(60), .editExisting)
        XCTAssertEqual(TrackerNoteKeyAction.forCommand(0xeb), .ignore)
        XCTAssertEqual(TrackerNoteKeyAction.forCommand(0xee), .ignore)
        XCTAssertEqual(TrackerNoteKeyAction.forCommand(0xf8), .ignore)
        XCTAssertEqual(TrackerNoteKeyAction.forCommand(0xfc), .insertNew)
        XCTAssertEqual(TrackerNoteKeyAction.forCommand(0xfd), .insertNew)
        XCTAssertEqual(TrackerNoteKeyAction.forCommand(0xfe), .insertNew)
    }

    func testEqualsAndAsteriskInsertAMeasureLineOutsideSinput() {
        XCTAssertEqual(TrackerEditorKey(characters: "="), .insertMeasureLine)
        XCTAssertEqual(TrackerEditorKey(characters: "*"), .insertMeasureLine)
        XCTAssertEqual(
            TrackerEditorKeyMap.command(for: .insertMeasureLine, isInlineEditing: false),
            .insertMeasureLine
        )
        XCTAssertNil(
            TrackerEditorKeyMap.command(for: .insertMeasureLine, isInlineEditing: true)
        )
    }

    func testMainEditorDeleteRemovesTheSelectedRow() {
        let keys: [TrackerEditorKey] = [
            .delete, .deleteForward, .backspaceCharacter, .forwardDeleteCharacter
        ]

        for key in keys {
            XCTAssertEqual(
                TrackerEditorKeyMap.command(for: key, isInlineEditing: false),
                .deleteSelectedRow,
                "\(key) should delete the selected row outside sinput"
            )
        }
    }

    func testInlineEditorKeepsDeleteForCharacterEditing() {
        let keys: [TrackerEditorKey] = [
            .delete, .deleteForward, .backspaceCharacter, .forwardDeleteCharacter
        ]

        for key in keys {
            XCTAssertNil(
                TrackerEditorKeyMap.command(for: key, isInlineEditing: true),
                "\(key) should stay with the inline field during sinput"
            )
        }
    }
}
