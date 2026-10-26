import AVFoundation
import MediaPlayer

/// Each voice's mutable state belongs exclusively to its audio render callback.
nonisolated private final class SynthVoice: @unchecked Sendable {
    enum Kind { case engine, signal, atmosphere }
    let kind: Kind
    let rate: Double
    private var frame: UInt64 = 0
    private var random: UInt64 = 0x4E454D555255
    private var noise: Double = 0
    private var phase: Double = 0
    private var nextSignal: Double = 9
    private var signalStart: Double = -100
    private var signalFrequency: Double = 370

    init(_ kind: Kind, rate: Double) { self.kind = kind; self.rate = rate }

    private func white() -> Double {
        random = random &* 6364136223846793005 &+ 1442695040888963407
        return Double(random >> 32) / Double(UInt32.max) * 2 - 1
    }

    func render(_ count: UInt32, _ list: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        for i in 0..<Int(count) {
            let t = Double(frame) / rate
            let n = white()
            noise += (n - noise) * (kind == .atmosphere ? 0.014 : 0.035)
            let sample: Double
            switch kind {
            case .engine:
                phase += 2 * .pi * (49 + 0.7 * sin(t * 0.071)) / rate
                if phase > 2 * .pi { phase -= 2 * .pi }
                sample = (sin(phase) * 0.10 + sin(phase * 2) * 0.025 + noise * 0.30)
                    * (0.88 + 0.06 * sin(t * 0.13) + 0.06 * sin(t * 0.047))
            case .signal:
                if t >= nextSignal {
                    signalStart = t
                    signalFrequency = 290 + (white() + 1) * 85
                    nextSignal = t + 13 + (white() + 1) * 10
                }
                let age = t - signalStart
                let envelope = age >= 0 && age < 1.2 ? pow(sin(.pi * age / 1.2), 2) : 0
                sample = sin(2 * .pi * signalFrequency * age) * envelope * 0.075
            case .atmosphere:
                sample = noise * (0.35 + 0.10 * sin(t * 0.10)) + sin(t * 2 * .pi * 36) * 0.025
            }
            let fadeIn = min(1, t / 2)
            let pan = sin(t * 0.055) * 0.12
            for channel in buffers.indices {
                guard let data = buffers[channel].mData?.assumingMemoryBound(to: Float.self) else { continue }
                data[i] = Float(sample * fadeIn * (channel == 0 ? 1 - pan : 1 + pan))
            }
            frame &+= 1
        }
        return noErr
    }
}

/// A soft weight-settling sound, with zero-valued endpoints and no sharp transient.
nonisolated enum LandingSound {
    static let duration = 1.2
    static func sample(at time: Double) -> Float {
        guard time > 0, time < duration else { return 0 }
        let attack = min(1, time / 0.16)
        let envelope = attack * attack * (3 - 2 * attack) * pow(1 - time / duration, 3)
        return Float(sin(2 * .pi * (52 * time - 5 * time * time)) * envelope * 0.13)
    }
}

/// Seamlessly loopable low-level beacon; graph parameters remain on the main actor.
nonisolated enum BeaconSound {
    static let duration = 2.0
    static func sample(at time: Double) -> Float {
        Float((sin(2 * .pi * 256 * time) + 0.25 * sin(2 * .pi * 384 * time)) * 0.035)
    }
}

@MainActor
final class VoyageAudio {
    private let engine = AVAudioEngine()
    private let engineRate = AVAudioUnitVarispeed()
    private let touchdown = AVAudioPlayerNode()
    private let beacon = AVAudioPlayerNode()
    private var beaconBuffer: AVAudioPCMBuffer?
    private var beaconLevel: Float = 0
    private var touchdownBuffer: AVAudioPCMBuffer?
    private var sources: [AVAudioSourceNode] = []
    private var mixers: [AVAudioMixerNode] = []
    private var wantsPlayback = false
    private var observers: [NSObjectProtocol] = []
    private var commands: [(MPRemoteCommand, Any)] = []
    private var interrupted = false
    private(set) var needsUserResume = false
    var isPlaying: Bool { engine.isRunning }
    var onStateChange: ((Bool, String?) -> Void)?
    private var resting = false
    private var current = SIMD3<Float>.zero

    init() {
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == AVAudioSession.InterruptionType.began.rawValue {
                    self.interrupted = true
                    self.engine.pause()
                    self.onStateChange?(false, "Sound is paused by another audio session.")
                    self.updateNowPlaying()
                } else {
                    self.interrupted = false
                    if self.wantsPlayback && !self.needsUserResume,
                       AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                        do { try self.start() }
                        catch { self.onStateChange?(false, "Tap Resume sound to continue.") }
                    } else {
                        self.needsUserResume = true
                        self.onStateChange?(false, "Tap Resume sound to continue.")
                    }
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor [weak self] in
                self?.pauseByUser(message: "Headphones disconnected. Tap Resume sound when you are ready.")
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, self.wantsPlayback, !self.interrupted, !self.needsUserResume else { return }
                do { try self.start() }
                catch { self.onStateChange?(false, "Tap Resume sound to continue.") }
            }
        })
        let center = MPRemoteCommandCenter.shared()
        let play = center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in
                do { try self?.start() }
                catch { self?.onStateChange?(false, "Sound could not resume.") }
            }
            return .success
        }
        let pause = center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pauseByUser() }
            return .success
        }
        commands = [(center.playCommand, play), (center.pauseCommand, pause)]
    }

    private func updateNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "STARSHIP NEMURU",
            MPMediaItemPropertyArtist: resting ? "Somewhere quiet" : "A quiet voyage",
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: engine.isRunning ? 1.0 : 0.0
        ]
    }

    func start() throws {
        wantsPlayback = true
        needsUserResume = false
        guard !interrupted else { return }
        guard !engine.isRunning else { onStateChange?(true, nil); return }
        let session = AVAudioSession.sharedInstance()
        // Own the playback session so the lock screen can expose Play/Pause.
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        if sources.isEmpty {
            let rate = session.sampleRate
            guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format,
                    frameCapacity: AVAudioFrameCount(rate * LandingSound.duration)) else {
                throw CocoaError(.coderInvalidValue)
            }
            buffer.frameLength = buffer.frameCapacity
            for channel in 0..<2 {
                for frame in 0..<Int(buffer.frameLength) {
                    buffer.floatChannelData?[channel][frame] = LandingSound.sample(at: Double(frame) / rate)
                }
            }
            touchdownBuffer = buffer
            engine.attach(engineRate)
            engine.attach(beacon)
            engine.connect(beacon, to: engine.mainMixerNode, format: format)
            if let tone = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(rate * BeaconSound.duration)) {
                tone.frameLength = tone.frameCapacity
                for channel in 0..<2 {
                    for frame in 0..<Int(tone.frameLength) { tone.floatChannelData?[channel][frame] = BeaconSound.sample(at: Double(frame) / rate) }
                }
                beaconBuffer = tone
            }
            engine.attach(touchdown)
            engine.connect(touchdown, to: engine.mainMixerNode, format: format)
            for kind in [SynthVoice.Kind.engine, .signal, .atmosphere] {
                let voice = SynthVoice(kind, rate: rate)
                let source = AVAudioSourceNode(format: format) { _, _, count, buffers in
                    voice.render(count, buffers)
                }
                let mixer = AVAudioMixerNode()
                engine.attach(source)
                engine.attach(mixer)
                if kind == .engine {
                    engine.connect(source, to: engineRate, format: format)
                    engine.connect(engineRate, to: mixer, format: format)
                } else {
                    engine.connect(source, to: mixer, format: format)
                }
                engine.connect(mixer, to: engine.mainMixerNode, format: format)
                mixer.outputVolume = 0
                sources.append(source)
                mixers.append(mixer)
            }
        }
        current = .zero
        for mixer in mixers { mixer.outputVolume = 0 }
        engine.prepare()
        try engine.start()
        beacon.volume = 0
        beaconLevel = 0
        if !beacon.isPlaying, let tone = beaconBuffer {
            beacon.scheduleBuffer(tone, at: nil, options: .loops, completionHandler: nil)
            beacon.play()
        }
        onStateChange?(true, nil)
        updateNowPlaying()
    }

    func setLevels(engine: Float, signal: Float, ambience: Float, speed: Float, rest: Float, approach: Float, elapsed: Float = 0.15) {
        guard mixers.count == 3 else { return }
        let isResting = rest > 0.8
        if resting != isResting { resting = isResting; updateNowPlaying() }
        let cruise = 0.65 + 0.35 * min(1, max(0, speed))
        let target = SIMD3(engine * (cruise * (1 - rest) + 0.12 * rest),
                           signal * (1 - 0.75 * rest), ambience * max(rest, approach * 0.12))
        let pitch = 0.96 + 0.04 * min(1, max(0, speed)) - 0.12 * rest - 0.04 * approach
        let smoothing = 1 - exp(-max(0, elapsed) / 1.4)
        engineRate.rate += (pitch - engineRate.rate) * smoothing
        touchdown.volume = engine * 0.4
        current += (target - current) * smoothing
        // An explicit zero always silences that layer immediately.
        mixers[0].outputVolume = engine == 0 ? 0 : current.x
        mixers[1].outputVolume = signal == 0 ? 0 : current.y
        mixers[2].outputVolume = ambience == 0 ? 0 : current.z
    }

    func setBeacon(strength: Float, pan: Float, volume: Float, elapsed: Float) {
        let target = min(1, max(0, strength)) * min(1, max(0, volume))
        let smoothing = 1 - exp(-max(0, elapsed) / 0.8)
        beaconLevel += (target - beaconLevel) * smoothing
        beacon.volume = volume == 0 ? 0 : beaconLevel
        beacon.pan += (min(0.75, max(-0.75, pan)) - beacon.pan) * smoothing
    }

    func playTouchdown(volume: Float) {
        guard engine.isRunning, let buffer = touchdownBuffer else { return }
        touchdown.stop()
        touchdown.volume = volume * 0.4
        touchdown.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        touchdown.play()
    }

    func pauseByUser(message: String = "Sound paused.") {
        stop()
        needsUserResume = true
        onStateChange?(false, message)
    }

    func stop() {
        wantsPlayback = false
        touchdown.stop()
        beacon.stop()
        beaconLevel = 0
        engine.pause()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        onStateChange?(false, nil)
        updateNowPlaying()
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for (command, target) in commands { command.removeTarget(target) }
    }
}
