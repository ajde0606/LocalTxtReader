import AVFoundation

@MainActor
final class PCMPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()

    private let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 24_000,
        channels: 1,
        interleaved: false
    )!

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    func play(samples: [Float]) throws {
        guard !samples.isEmpty else { return }

        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try session.setActive(true)
        #endif

        let frameCount = AVAudioFrameCount(samples.count)

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            return
        }

        buffer.frameLength = frameCount

        let channel = buffer.floatChannelData![0]
        samples.withUnsafeBufferPointer { ptr in
            if let base = ptr.baseAddress {
                channel.update(from: base, count: samples.count)
            }
        }

        if !engine.isRunning {
            try engine.start()
        }

        if !player.isPlaying {
            player.play()
        }

        player.scheduleBuffer(buffer, completionHandler: nil)
    }

    func stop() {
        player.stop()
        engine.stop()

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false)
        #endif
    }

    func testTone() throws {
        let sampleRate = 24_000.0
        let duration = 2.0
        let freq = 440.0

        let samples = (0..<Int(sampleRate * duration)).map { i in
            Float(0.2 * sin(2.0 * .pi * freq * Double(i) / sampleRate))
        }

        try play(samples: samples)
    }
}
