import AudioToolbox
import AVFoundation
import Foundation

private final class UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}

/// Hosts the SC-55 AUv3 music device (`aumu` / `Sc55` / `Rin2`) and accepts raw MIDI.
@MainActor
public final class AudioUnitAdapter: MIDISink {
    public let engine = AVAudioEngine()
    public private(set) var instrumentName = AudioUnitCatalog.displayName
    public var isAttached: Bool { instrument != nil }
    private var instrument: AVAudioUnit?
    private var clockNode: AVAudioSourceNode?
    private let renderContext = RenderContext()

    var clock: PlaybackRuntime? {
        get { renderContext.clock }
        set { renderContext.clock = newValue }
    }

    public init() {}

    public func attachDefaultInstrument() async throws {
        AudioUnitCatalog.logAvailableAUMU()
        try activateAudioSessionIfNeeded()

        #if os(iOS)
        let optionOrder: [AudioComponentInstantiationOptions] = [[], .loadOutOfProcess]
        #else
        let optionOrder: [AudioComponentInstantiationOptions] = [.loadOutOfProcess, []]
        #endif

        var lastError: Error?
        var loaded: AVAudioUnit?
        var loadedName = AudioUnitCatalog.displayName

        func tryDescriptions(_ descriptions: [AudioComponentDescription], name: String) async {
            guard loaded == nil else { return }
            for description in descriptions {
                for options in optionOrder {
                    do {
                        loaded = try await instantiate(description: description, options: options)
                        loadedName = name
                        return
                    } catch {
                        lastError = error
                    }
                }
            }
        }

        // iPhone often never lists the AUv3 in the catalog. Open by code first,
        // the same way Mac already succeeded.
        await tryDescriptions(AudioUnitCatalog.candidateDescriptions, name: AudioUnitCatalog.displayName)

        if loaded == nil, let match = AudioUnitCatalog.resolveSC55() {
            await tryDescriptions([match.audioComponentDescription], name: match.name)
        }

        if loaded == nil {
            let deadline = Date().addingTimeInterval(4)
            while loaded == nil, Date() < deadline {
                try await Task.sleep(nanoseconds: 250_000_000)
                if let match = AudioUnitCatalog.resolveSC55() {
                    await tryDescriptions([match.audioComponentDescription], name: match.name)
                } else {
                    await tryDescriptions(
                        AudioUnitCatalog.candidateDescriptions,
                        name: AudioUnitCatalog.displayName
                    )
                }
            }
        }

        guard let unit = loaded else {
            let available = AudioUnitCatalog.listedInstruments()
                .map(\.name)
                .joined(separator: ", ")
            let detail = lastError?.localizedDescription ?? "component not listed"
            throw AudioUnitAdapterError.instantiationFailed(
                available.isEmpty
                    ? "\(detail)。一覧にも出ていない。SC-55 アプリを一度開いてから STed を再起動する"
                    : "\(detail)。見える音源: \(available)"
            )
        }

        if let previous = instrument {
            engine.disconnectNodeOutput(previous)
            engine.detach(previous)
        }
        instrument = unit
        instrumentName = unit.auAudioUnit.audioUnitName ?? loadedName
        bindMIDITarget(unit)
        wireGraph(unit: unit)
    }

    public func start() throws {
        try activateAudioSessionIfNeeded()
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
        if let unit = instrument {
            bindMIDITarget(unit)
        }
    }

    private func wireGraph(unit: AVAudioUnit) {
        let output = engine.outputNode
        let mixer = engine.mainMixerNode
        if !engine.attachedNodes.contains(unit) {
            engine.attach(unit)
        }

        let unitFormat = unit.outputFormat(forBus: 0)
        let hardwareFormat = output.outputFormat(forBus: 0)
        let format: AVAudioFormat?
        if unitFormat.sampleRate > 0, unitFormat.channelCount > 0 {
            format = unitFormat
        } else if hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0 {
            format = hardwareFormat
        } else {
            format = nil
        }

        engine.connect(unit, to: mixer, format: format)
        ensureClockNode(mixer: mixer, format: format ?? hardwareFormat)
        engine.connect(mixer, to: output, format: nil)
        if output.outputFormat(forBus: 0).sampleRate > 0 {
            renderContext.sampleRate = output.outputFormat(forBus: 0).sampleRate
        } else if let format, format.sampleRate > 0 {
            renderContext.sampleRate = format.sampleRate
        }
    }

    private func ensureClockNode(mixer: AVAudioMixerNode, format: AVAudioFormat?) {
        if clockNode == nil {
            let node = AudioUnitAdapter.makeClockNode(context: renderContext)
            clockNode = node
            engine.attach(node)
        }
        if let node = clockNode {
            engine.connect(node, to: mixer, format: format)
        }
    }

    /// Built off the MainActor so the render block is not actor-isolated.
    /// An isolated observer on the remote AU crashed iPhone with
    /// `_dispatch_assert_queue_fail` on `AURemoteIO::IOThread`.
    nonisolated private static func makeClockNode(context: RenderContext) -> AVAudioSourceNode {
        AVAudioSourceNode { isSilence, timestamp, frameCount, _ in
            isSilence.pointee = true
            audioTick(context: context, timestamp: timestamp, frameCount: frameCount)
            return noErr
        }
    }

    nonisolated private static func audioTick(
        context: RenderContext,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AVAudioFrameCount
    ) {
        let rate = context.sampleRate
        guard rate > 0, frameCount > 0 else { return }
        var hostTime = AUEventSampleTimeImmediate
        if timestamp.pointee.mFlags.contains(.sampleTimeValid) {
            hostTime = AUEventSampleTime(timestamp.pointee.mSampleTime)
        }
        context.clock?.render(frameCount: Int(frameCount), sampleRate: rate) { bytes, offset in
            let time = hostTime == AUEventSampleTimeImmediate
                ? AUEventSampleTimeImmediate
                : hostTime + offset
            context.midiOut.send(bytes, at: time)
        }
    }

    public func stopEngine() {
        if engine.isRunning {
            engine.stop()
        }
    }

    public func send(_ bytes: [UInt8]) {
        renderContext.midiOut.send(bytes)
    }

    public func panic() {
        renderContext.midiOut.panic()
    }

    private func bindMIDITarget(_ unit: AVAudioUnit) {
        renderContext.midiOut.bind(scheduleBlock: unit.auAudioUnit.scheduleMIDIEventBlock)
    }

    private func activateAudioSessionIfNeeded() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        #endif
    }

    private func instantiate(
        description: AudioComponentDescription,
        options: AudioComponentInstantiationOptions
    ) async throws -> AVAudioUnit {
        try await withCheckedThrowingContinuation { continuation in
            AVAudioUnit.instantiate(with: description, options: options) { unit, error in
                if let unit {
                    let box = UncheckedBox(unit)
                    Task { @MainActor in
                        continuation.resume(returning: box.value)
                    }
                    return
                }
                let message = error?.localizedDescription ?? "unknown error"
                Task { @MainActor in
                    continuation.resume(throwing: AudioUnitAdapterError.instantiationFailed(message))
                }
            }
        }
    }
}
