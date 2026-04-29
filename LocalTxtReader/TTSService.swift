import Foundation
import Combine
import CoreML
import Qwen3TTSCoreML

@MainActor
final class TTSService: ObservableObject {
    private var model: Qwen3TTSCoreMLModel?

    func loadIfNeeded() async throws {
        if model != nil {
            print("TTS model already loaded; reusing in-memory model")
            return
        }

        print("Loading CoreML TTS model...")

        model = try await Qwen3TTSCoreMLModel.fromPretrained(
            computeUnits: .all,
            progressHandler: { progress, status in
                print("TTS load:", status, Int(progress * 100), "%")
            }
        )

        print("TTS model loaded")
    }

    func synthesize(text rawText: String, maxTokens: Int) async throws -> [Float] {
        try await loadIfNeeded()

        guard let model else {
            throw NSError(domain: "TTS", code: -1)
        }

        let cleaned = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        print("Qwen synth input raw=[\(rawText)] cleaned=[\(cleaned)] chars=\(cleaned.count) language=chinese maxTokens=\(maxTokens)")

        let samples = try model.synthesize(
            text: cleaned,
            language: "chinese",
            maxTokens: maxTokens
        )

        let minValue = samples.min() ?? 0
        let maxValue = samples.max() ?? 0
        let rms = sqrt(samples.reduce(0) { $0 + Double($1 * $1) } / Double(max(samples.count, 1)))

        print(String(format: "Qwen synth output samples=%d min=%.5f max=%.5f rms=%.5f first=%@",
                     samples.count,
                     minValue,
                     maxValue,
                     rms,
                     Array(samples.prefix(16)).description))

        return samples
    }
}
