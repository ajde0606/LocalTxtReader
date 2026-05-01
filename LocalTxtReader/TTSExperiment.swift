import Foundation
import CoreML
import Qwen3TTSCoreML

// ── Inputs ────────────────────────────────────────────────────────────────────
// Note: speakerName and instruction are NOT synthesize() parameters in the
// current speech-swift API. Speaker is baked into the model at fromPretrained()
// time via speaker_embedding.npy. Instruction is not supported. They are kept
// here for documentation and for when the API is extended.
struct ExperimentInput {
    var text: String = "今天天气很好。"
    var speakerName: String = "vivan"   // informational only — see note above
    var language: String = "chinese"
    var instruction: String = ""        // informational only — see note above
}

// ── Outputs ───────────────────────────────────────────────────────────────────
struct ExperimentResult {
    // Stage 1: token IDs the Qwen3 tokenizer assigns to the input text.
    // Populated only when Qwen3TTSCoreMLModel exposes synthesizeWithIntermediates().
    let textTokens: [Int]

    // Stage 2: discrete codec token IDs produced by CodeDecoder + MultiCodeDecoder.
    // Shape: [16 codebooks][N frames].
    // Populated only when Qwen3TTSCoreMLModel exposes synthesizeWithIntermediates().
    let speechCodecTokens: [[Int32]]

    // Stage 3: raw PCM float samples from SpeechDecoder.
    let audioSamples: [Float]
    let sampleRate: Int
}

// ── What needs to be added to Qwen3TTSCoreMLModel in speech-swift ─────────────
//
// Add this method alongside synthesize() in Qwen3TTSCoreMLModel.swift:
//
//   public struct SynthesisIntermediates {
//       public let textTokens: [Int]
//       public let codecTokens: [[Int32]]   // [16][N frames]
//       public let audioSamples: [Float]
//   }
//
//   public func synthesizeWithIntermediates(
//       text: String,
//       language: String = "english",
//       temperature: Float = 0.8,
//       topK: Int = 50,
//       maxTokens: Int = 125,
//       repetitionPenalty: Float = 1.05
//   ) throws -> SynthesisIntermediates {
//       // 1. tokenize raw text for logging (PromptBuilder adds extra framing tokens)
//       let textTokens = tokenizer?.encode(text) ?? []
//
//       // 2-3. run the existing synthesis pipeline, but capture allCodebooks
//       //      before passing to speechDecoder.decode(codes:)
//       //      (copy the body of synthesize() and surface allCodebooks)
//       let (codecTokens, audioSamples) = try synthesizeCaptureCodecs(
//           text: text, language: language, temperature: temperature,
//           topK: topK, maxTokens: maxTokens, repetitionPenalty: repetitionPenalty)
//
//       return SynthesisIntermediates(
//           textTokens: textTokens,
//           codecTokens: codecTokens,
//           audioSamples: audioSamples)
//   }
// ─────────────────────────────────────────────────────────────────────────────

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

        // All three stages via synthesizeWithIntermediates() in Qwen3TTSCoreMLModel.
        let intermediates = try model.synthesizeWithIntermediates(
            text: input.text,
            language: input.language,
            maxTokens: 120
        )

        let result = ExperimentResult(
            textTokens: intermediates.textTokens,
            speechCodecTokens: intermediates.codecTokens,
            audioSamples: intermediates.audioSamples,
            sampleRate: intermediates.sampleRate
        )
        printResult(input: input, result: result)
        return result
    }

    private func printResult(input: ExperimentInput, result: ExperimentResult) {
        print("=== TTSExperiment ===")
        print("Input:")
        print("  text        :", input.text)
        print("  speakerName :", input.speakerName, "(baked into model — not a runtime param)")
        print("  language    :", input.language)
        print("  instruction :", input.instruction.isEmpty ? "(empty, not supported by API)" : input.instruction)

        print("Stage 1 — text tokens (\(result.textTokens.count)):")
        if result.textTokens.isEmpty {
            print("  (needs synthesizeWithIntermediates() in Qwen3TTSCoreMLModel — see comment above)")
        } else {
            print(" ", result.textTokens)
        }

        print("Stage 2 — speech codec tokens (\(result.speechCodecTokens.count) codebooks):")
        if result.speechCodecTokens.isEmpty {
            print("  (needs synthesizeWithIntermediates() in Qwen3TTSCoreMLModel — see comment above)")
        } else {
            for (i, book) in result.speechCodecTokens.enumerated() {
                print(String(format: "  codebook[%2d] %d tokens: %@ …", i, book.count, "\(book.prefix(8))"))
            }
        }

        print("Stage 3 — audio:")
        print("  sampleRate  :", result.sampleRate, "Hz")
        print("  samples     :", result.audioSamples.count)
        let mn = result.audioSamples.min() ?? 0
        let mx = result.audioSamples.max() ?? 0
        let rms = sqrt(result.audioSamples.reduce(0.0) { $0 + Double($1 * $1) } / Double(max(result.audioSamples.count, 1)))
        print(String(format: "  min=%.5f  max=%.5f  rms=%.5f", mn, mx, rms))
        print("  first 16   :", Array(result.audioSamples.prefix(16)))
        print("=== end ===")
    }
}
