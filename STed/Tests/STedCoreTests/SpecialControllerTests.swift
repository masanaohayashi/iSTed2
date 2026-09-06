import XCTest
@testable import STedCore

final class SpecialControllerTests: XCTestCase {
    func testSlashKeyInsertsASpecialControllerOutsideSinput() {
        XCTAssertEqual(TrackerEditorKey(characters: "/"), .insertSpecialController)
        XCTAssertEqual(
            TrackerEditorKeyMap.command(for: .insertSpecialController, isInlineEditing: false),
            .insertSpecialController
        )
        XCTAssertNil(
            TrackerEditorKeyMap.command(for: .insertSpecialController, isInlineEditing: true)
        )
    }

    func testSpcCodeMapsManualSymbolsToCommandsAndDefaultControls() {
        XCTAssertEqual(SpecialController.code(from: "G"), SpecialControllerCode(command: 0xec, control: -1))
        XCTAssertEqual(SpecialController.code(from: "G@"), SpecialControllerCode(command: 0xe2, control: -1))
        XCTAssertEqual(SpecialController.code(from: "M"), SpecialControllerCode(command: 0xe6, control: -1))
        XCTAssertEqual(SpecialController.code(from: "T"), SpecialControllerCode(command: 0xe7, control: -1))
        XCTAssertEqual(SpecialController.code(from: "P"), SpecialControllerCode(command: 0xee, control: -1))
        XCTAssertEqual(SpecialController.code(from: "C"), SpecialControllerCode(command: 0xea, control: -1))
        XCTAssertEqual(SpecialController.code(from: "K"), SpecialControllerCode(command: 0xed, control: -1))
        XCTAssertEqual(SpecialController.code(from: "L"), SpecialControllerCode(command: 0xeb, control: -1))
        XCTAssertEqual(SpecialController.code(from: "D"), SpecialControllerCode(command: 0xeb, control: 1))
        XCTAssertEqual(SpecialController.code(from: "V"), SpecialControllerCode(command: 0xeb, control: 7))
        XCTAssertEqual(SpecialController.code(from: "N"), SpecialControllerCode(command: 0xeb, control: 10))
        XCTAssertEqual(SpecialController.code(from: "E"), SpecialControllerCode(command: 0xeb, control: 11))
        XCTAssertEqual(SpecialController.code(from: "H"), SpecialControllerCode(command: 0xeb, control: 64))
        XCTAssertEqual(SpecialController.code(from: "A"), SpecialControllerCode(command: 0xeb, control: 121))
        XCTAssertEqual(SpecialController.code(from: "@"), SpecialControllerCode(command: 0xeb, control: 0))
        XCTAssertEqual(SpecialController.code(from: "@@"), SpecialControllerCode(command: 0xeb, control: 32))
        XCTAssertEqual(SpecialController.code(from: "F1"), SpecialControllerCode(command: 0xeb, control: 91))
        XCTAssertEqual(SpecialController.code(from: "F3"), SpecialControllerCode(command: 0xeb, control: 93))
        XCTAssertEqual(SpecialController.code(from: "F4"), SpecialControllerCode(command: 0xeb, control: 94))
        XCTAssertEqual(SpecialController.code(from: "PT"), SpecialControllerCode(command: 0xeb, control: 5))
        XCTAssertEqual(SpecialController.code(from: "PO"), SpecialControllerCode(command: 0xeb, control: 65))
        XCTAssertEqual(SpecialController.code(from: "PC"), SpecialControllerCode(command: 0xeb, control: 84))
        XCTAssertEqual(SpecialController.code(from: "SS"), SpecialControllerCode(command: 0xeb, control: 66))
        XCTAssertEqual(SpecialController.code(from: "ST"), SpecialControllerCode(command: 0xeb, control: 67))
        XCTAssertEqual(SpecialController.code(from: "BR"), SpecialControllerCode(command: 0xeb, control: 2))
        XCTAssertEqual(SpecialController.code(from: "EM"), SpecialControllerCode(command: 0xeb, control: 6))
        XCTAssertEqual(SpecialController.code(from: "EL"), SpecialControllerCode(command: 0xeb, control: 38))
        XCTAssertEqual(SpecialController.code(from: "NM"), SpecialControllerCode(command: 0xeb, control: 99))
        XCTAssertEqual(SpecialController.code(from: "NL"), SpecialControllerCode(command: 0xeb, control: 98))
        XCTAssertEqual(SpecialController.code(from: "RM"), SpecialControllerCode(command: 0xeb, control: 101))
        XCTAssertEqual(SpecialController.code(from: "RL"), SpecialControllerCode(command: 0xeb, control: 100))
        XCTAssertEqual(SpecialController.code(from: "U0"), SpecialControllerCode(command: 0x90, control: -1))
        XCTAssertEqual(SpecialController.code(from: "U7"), SpecialControllerCode(command: 0x97, control: -1))
        XCTAssertEqual(SpecialController.code(from: "X"), SpecialControllerCode(command: 0x98, control: -1))
        XCTAssertEqual(SpecialController.code(from: "B"), SpecialControllerCode(command: 0xdd, control: -1))
        XCTAssertEqual(SpecialController.code(from: "R"), SpecialControllerCode(command: 0xde, control: -1))
        XCTAssertEqual(SpecialController.code(from: "I"), SpecialControllerCode(command: 0xdf, control: -1))
        XCTAssertEqual(SpecialController.code(from: "S4"), SpecialControllerCode(command: 0xdc, control: -1))
        XCTAssertEqual(SpecialController.code(from: "S5"), SpecialControllerCode(command: 0xc5, control: -1))
        XCTAssertEqual(SpecialController.code(from: "S6"), SpecialControllerCode(command: 0xc6, control: -1))
    }

    func testSpcCodeAcceptsLowercaseALeadingSlashAndControlNumbers() {
        XCTAssertEqual(SpecialController.code(from: "v"), SpecialController.code(from: "V"))
        XCTAssertEqual(SpecialController.code(from: "/V"), SpecialController.code(from: "V"))
        XCTAssertEqual(SpecialController.code(from: "L11"), SpecialControllerCode(command: 0xeb, control: 11))
        XCTAssertEqual(SpecialController.code(from: "7"), SpecialControllerCode(command: 0xeb, control: 7))
        XCTAssertEqual(SpecialController.code(from: "G12"), SpecialControllerCode(command: 0xec, control: 12))
        XCTAssertEqual(SpecialController.code(from: "G@3"), SpecialControllerCode(command: 0xe2, control: 3))
        XCTAssertEqual(SpecialController.code(from: "AT"), SpecialControllerCode(command: 0xeb, control: 73))
        XCTAssertEqual(SpecialController.code(from: "CO"), SpecialControllerCode(command: 0xeb, control: 74))
        XCTAssertEqual(SpecialController.code(from: "@L"), SpecialControllerCode(command: 0xeb, control: 32))
    }

    func testSpcCodeRejectsUnknownSymbols() {
        XCTAssertNil(SpecialController.code(from: ""))
        XCTAssertNil(SpecialController.code(from: "Z"))
        XCTAssertNil(SpecialController.code(from: "S"))
        XCTAssertNil(SpecialController.code(from: "Q"))
        XCTAssertNil(SpecialController.code(from: "F"))
    }

    func testInsertPlaceholderIsABlankFourByteRow() {
        var track = Track(
            id: 0,
            number: 1,
            events: [
                TrackEvent(command: 60, delay: 48, param1: 36, param2: 100),
                TrackEvent(command: 64, delay: 48, param1: 36, param2: 100),
                TrackEvent(command: 0xfe, delay: 0, param1: 0, param2: 0)
            ]
        )

        track.insertSpecialControllerPlaceholder(at: 1)

        XCTAssertEqual(track.events.map(\.command), [60, 0, 64, 0xfe])
        XCTAssertEqual(track.events[1], TrackEvent.specialControllerPlaceholder)
    }

    func testVolumeEventUsesControlChangeSeven() {
        let event = SpecialController.makeEvent(
            SpecialController.code(from: "V")!,
            previousEvents: [],
            trackMIDIChannel: 1
        )

        XCTAssertEqual(event, TrackEvent(command: 0xeb, delay: 0, param1: 7, param2: 0))
    }

    func testBareControlLeavesGateAs128UntilTheNumberIsEdited() {
        let event = SpecialController.makeEvent(
            SpecialController.code(from: "L")!,
            previousEvents: [],
            trackMIDIChannel: 1
        )

        XCTAssertEqual(event, TrackEvent(command: 0xeb, delay: 0, param1: 128, param2: 0))
    }

    func testProgramChangeCopiesThePreviousProgramNumber() {
        let previous: [TrackEvent] = [
            TrackEvent(command: 0xec, delay: 0, param1: 41, param2: 0),
            TrackEvent(command: 60, delay: 48, param1: 36, param2: 100)
        ]

        let event = SpecialController.makeEvent(
            SpecialController.code(from: "G")!,
            previousEvents: previous[...],
            trackMIDIChannel: 2
        )

        XCTAssertEqual(event, TrackEvent(command: 0xec, delay: 0, param1: 41, param2: 0))
    }

    func testNumberedProgramChangeUsesTheTypedProgram() {
        let event = SpecialController.makeEvent(
            SpecialController.code(from: "G5")!,
            previousEvents: [
                TrackEvent(command: 0xec, delay: 0, param1: 41, param2: 0)
            ][...],
            trackMIDIChannel: 1
        )

        XCTAssertEqual(event, TrackEvent(command: 0xec, delay: 0, param1: 5, param2: 0))
    }

    func testPitchBendCentersAt64() {
        let event = SpecialController.makeEvent(
            SpecialController.code(from: "P")!,
            previousEvents: [],
            trackMIDIChannel: 1
        )

        XCTAssertEqual(event, TrackEvent(command: 0xee, delay: 0, param1: 0, param2: 64))
    }

    func testMIDIChannelCopiesTheCurrentChannelThenEarlierChannelEvents() {
        XCTAssertEqual(
            SpecialController.makeEvent(
                SpecialController.code(from: "M")!,
                previousEvents: [],
                trackMIDIChannel: 12
            ),
            TrackEvent(command: 0xe6, delay: 0, param1: 12, param2: 0)
        )

        XCTAssertEqual(
            SpecialController.makeEvent(
                SpecialController.code(from: "M")!,
                previousEvents: [
                    TrackEvent(command: 0xe6, delay: 0, param1: 5, param2: 0),
                    TrackEvent(command: 60, delay: 48, param1: 36, param2: 100)
                ][...],
                trackMIDIChannel: 12
            ),
            TrackEvent(command: 0xe6, delay: 0, param1: 5, param2: 0)
        )
    }

    func testInsertFieldsFollowSpcon() {
        XCTAssertEqual(
            SpecialController.fields(for: SpecialController.code(from: "V")!),
            [.stepTime, .velocity(0...127)]
        )
        XCTAssertEqual(
            SpecialController.fields(for: SpecialController.code(from: "L")!),
            [.stepTime, .gateTime(0...127), .velocity(0...127)]
        )
        XCTAssertEqual(
            SpecialController.fields(for: SpecialController.code(from: "P")!),
            [.stepTime, .pitchBend]
        )
        XCTAssertEqual(
            SpecialController.fields(for: SpecialController.code(from: "G")!),
            [.stepTime, .gateTime(0...127)]
        )
        XCTAssertEqual(
            SpecialController.fields(for: SpecialController.code(from: "G5")!),
            [.stepTime]
        )
        XCTAssertEqual(
            SpecialController.fields(for: SpecialController.code(from: "G@")!),
            [.stepTime, .gateTime(0...127), .velocity(0...127)]
        )
        XCTAssertEqual(
            SpecialController.fields(for: SpecialController.code(from: "M")!),
            [.stepTime, .midiChannel]
        )
        XCTAssertEqual(
            SpecialController.fields(for: SpecialController.code(from: "T")!),
            [.stepTime, .gateTime(1...255), .velocity(0...255)]
        )
        XCTAssertEqual(
            SpecialController.fields(for: SpecialController.code(from: "K")!),
            [.stepTime, .gateTime(0...127)]
        )
        XCTAssertEqual(
            SpecialController.fields(for: SpecialController.code(from: "C")!),
            [.stepTime, .gateTime(0...127), .velocity(0...127)]
        )
    }

    func testPitchBendEncodesCenteredFourteenBitValue() {
        XCTAssertEqual(
            SpecialController.pitchBendEvent(delay: 11, bend: 0),
            TrackEvent(command: 0xee, delay: 11, param1: 0, param2: 64)
        )
        XCTAssertEqual(
            SpecialController.pitchBendEvent(delay: 0, bend: 1365),
            TrackEvent(command: 0xee, delay: 0, param1: 85, param2: 74)
        )
        XCTAssertEqual(
            SpecialController.pitchValue(param1: 85, param2: 74),
            1365
        )
    }

    func testSelectorCatalogMatchesOriginalSpecialControlerList() {
        let items = SpecialController.selectorItems
        XCTAssertEqual(items.count, 24)
        XCTAssertEqual(items[0].symbol, "G")
        XCTAssertEqual(items[0].name, "PROGRAM")
        XCTAssertEqual(items[0].comment, "PROGRAM CHANGE")
        XCTAssertEqual(items[1].symbol, "M")
        XCTAssertEqual(items[6].symbol, "L")
        XCTAssertEqual(items[13].symbol, "")
        XCTAssertEqual(items[14].symbol, "X")
        XCTAssertEqual(items[18].symbol, "EM")
        XCTAssertEqual(items[23].symbol, "RL")
        XCTAssertEqual(SpecialController.selectorSymbol(at: 0, confirming: true), "G")
        XCTAssertNil(SpecialController.selectorSymbol(at: 0, confirming: false))
        XCTAssertNil(SpecialController.selectorSymbol(at: 13, confirming: true))
    }

    func testSelectorNavigationSkipsSeparatorInBothDirections() {
        XCTAssertEqual(SpecialController.nextSelectorIndex(from: 12, movingDown: true), 14)
        XCTAssertEqual(SpecialController.nextSelectorIndex(from: 14, movingDown: false), 12)
        XCTAssertEqual(SpecialController.nextSelectorIndex(from: 23, movingDown: true), 0)
        XCTAssertEqual(SpecialController.nextSelectorIndex(from: 0, movingDown: false), 23)
        for index in SpecialController.selectorItems.indices {
            for movingDown in [true, false] {
                let next = SpecialController.nextSelectorIndex(from: index, movingDown: movingDown)
                XCTAssertNotNil(SpecialController.selectorSymbol(at: next, confirming: true))
            }
        }
    }

    func testEscDuringSpecialInsertDeletesThePlaceholder() {
        XCTAssertEqual(
            TrackerInlineCancelAction.forInsertedSpecial(true),
            .deleteInsertedStep
        )
    }

    func testDownDuringSymbolInputOpensTheSelector() {
        XCTAssertEqual(
            SpecialController.symbolInputAction(forDownArrow: true),
            .openSelector
        )
        XCTAssertEqual(
            SpecialController.symbolInputAction(forDownArrow: false),
            .commitSymbol
        )
    }
}
