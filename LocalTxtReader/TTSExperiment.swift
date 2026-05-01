import Foundation
import Qwen3TTSCoreML

struct ExperimentInput {
    var text: String = "今天天气很好。"
    var speakerName: String = "vivan"
    var language: String = "chinese"
    var instruction: String = ""
}

struct ExperimentResult {
    // stage 1: text → token IDs fed into the LLM
    let textTokens: [Int]

    // stage 2: LLM output → discrete codec token IDs (one [Int] per codebook)
    let speechCodecTokens: [[Int]]

    // stage 3: codec → raw PCM
    let audioSamples: [Float]
    let sampleRate: Int
}

@MainActor
final class TTSExperimentRunner {
    private var model: Qwen3TTSCoreMLModel?

    func run(_ input: ExperimentInput) async throws -> ExperimentResult {
        if model == nil {
            print("[Experiment] Loading model…")
            model = try await Qwen3TTSCoreMLModel.fromPretrained(
                computeUnits: .all,
                progressHandler: { p, s in print("[Experiment] load", s, Int(p * 100), "%") }
            )
            print("[Experiment] Model loaded")
        }

        guard let model else { throw NSError(domain: "TTSExperiment", code: -1) }

        // ── Stage 1: text tokens ──────────────────────────────────────────────
        // TODO: replace with the real tokenizer call once the API is confirmed.
        // Likely candidate:
        //   let textTokens = try model.tokenize(
        //       text: input.text,
        //       language: input.language,
        //       speaker: input.speakerName,
        //       instruction: input.instruction
        //   )
        let textTokens: [Int] = []

        // ── Stage 2: speech codec tokens ─────────────────────────────────────
        // TODO: replace with the step-by-step call once the API is confirmed.
        // Likely candidate:
        //   let speechCodecTokens = try await model.generateCodecTokens(
        //       text: input.text,
        //       language: input.language,
        //       speaker: input.speakerName,
        //       instruction: input.instruction,
        //       maxTokens: 120
        //   )
        let speechCodecTokens: [[Int]] = []

        // ── Stage 3: audio ────────────────────────────────────────────────────
        // Current high-level API; works on Mac today.
        // TODO: add speaker / instruction params once confirmed:
        //   model.synthesize(text:language:speaker:instruction:maxTokens:)
        let audioSamples = try model.synthesize(
            text: input.text,
            language: input.language,
            maxTokens: 120
        )

        let result = ExperimentResult(
            textTokens: textTokens,
            speechCodecTokens: speechCodecTokens,
            audioSamples: audioSamples,
            sampleRate: 24_000
        )

        printResult(input: input, result: result)
        return result
    }

    private func printResult(input: ExperimentInput, result: ExperimentResult) {
        print("=== TTSExperiment ===")
        print("Input:")
        print("  text        :", input.text)
        print("  speakerName :", input.speakerName)
        print("  language    :", input.language)
        print("  instruction :", input.instruction.isEmpty ? "(empty)" : input.instruction)
        print("Stage 1 — text tokens (\(result.textTokens.count)):")
        print(" ", result.textTokens.isEmpty ? "(stub — see TODO in TTSExperiment.swift)" : "\(result.textTokens)")
        print("Stage 2 — speech codec tokens (\(result.speechCodecTokens.count) codebooks):")
        if result.speechCodecTokens.isEmpty {
            print("  (stub — see TODO in TTSExperiment.swift)")
        } else {
            for (i, book) in result.speechCodecTokens.enumerated() {
                print("  codebook[\(i)] \(book.count) tokens:", book.prefix(8), "…")
            }
        }
        print("Stage 3 — audio:")
        print("  sampleRate  :", result.sampleRate)
        print("  samples     :", result.audioSamples.count)
        let mn = result.audioSamples.min() ?? 0
        let mx = result.audioSamples.max() ?? 0
        let rms = sqrt(result.audioSamples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(result.audioSamples.count, 1)))
        print(String(format: "  min=%.5f  max=%.5f  rms=%.5f", mn, mx, rms))
        print("  first 16   :", Array(result.audioSamples.prefix(16)))
        print("=== end ===")
    }
}
