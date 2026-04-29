import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var text: String = "今天天气很好。"
    @State private var status: String = "Open a .txt file or type text"
    @State private var isBusy: Bool = false
    @State private var elapsedText: String = "Elapsed: 0.0s"
    @State private var showFileImporter = false

    @StateObject private var tts = TTSService()
    @State private var player = PCMPlayer()

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("Open TXT") {
                    showFileImporter = true
                }

                Button(isBusy ? "Speaking..." : "Speak") {
                    Task {
                        await speakText()
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isBusy)

                Button("Test Tone") {
                    do {
                        try player.testTone()
                        status = "Playing test tone"
                    } catch {
                        status = "Tone error: \(error.localizedDescription)"
                    }
                }

                Button("Stop") {
                    player.stop()
                    status = "Stopped"
                }
            }

            Text(status)
                .font(.callout)
                .multilineTextAlignment(.center)

            Text(elapsedText)
                .font(.system(.body, design: .monospaced))

            TextEditor(text: $text)
                .font(.system(size: 15))
                .border(Color.gray.opacity(0.3))
        }
        .padding()
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }

            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            text = try String(contentsOf: url, encoding: .utf8)
            status = "Loaded \(url.lastPathComponent)"
            elapsedText = "Elapsed: 0.0s"
        } catch {
            status = "Failed to load file: \(error.localizedDescription)"
        }
    }

    private func cleanTextForTTS(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\n+", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]*\\n[ \\t]*", with: "。", options: .regularExpression)
            .replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "[\\u{200B}\\u{200C}\\u{200D}\\u{FEFF}]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "。+", with: "。", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func split(_ text: String, max: Int = 80) -> [String] {
        let cleaned = cleanTextForTTS(text)
        var result: [String] = []
        var current = ""

        for char in cleaned {
            current.append(char)

            if current.count >= max || "。！？!?；;".contains(char) {
                let chunk = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !chunk.isEmpty {
                    result.append(chunk)
                }
                current = ""
            }
        }

        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            result.append(tail)
        }

        return result
    }

    private func dynamicMaxTokens(for chunk: String) -> Int {
        let cleaned = cleanTextForTTS(chunk)

        #if os(iOS)
        return min(80, max(24, cleaned.count * 5))
        #else
        return min(120, max(30, cleaned.count * 8))
        #endif
    }

    @MainActor
    private func speakText() async {
        isBusy = true
        defer { isBusy = false }

        let start = Date()
        elapsedText = "Elapsed: 0.0s"

        let timerTask = Task {
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                await MainActor.run {
                    elapsedText = String(format: "Elapsed: %.1fs", elapsed)
                }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }

        do {
            status = "Loading model..."
            try await tts.loadIfNeeded()

            let chunks = split(text)
            guard !chunks.isEmpty else {
                status = "No readable text found"
                timerTask.cancel()
                return
            }

            player.stop()

            for (index, chunk) in chunks.enumerated() {
                let maxTokens = dynamicMaxTokens(for: chunk)

                print("---- CHUNK \(index + 1)/\(chunks.count) ----")
                print("chunk raw:", chunk)
                print("chars:", chunk.count)
                print("maxTokens:", maxTokens)

                status = "Generating chunk \(index + 1)/\(chunks.count), maxTokens=\(maxTokens)..."

                let samples = try await tts.synthesize(
                    text: chunk,
                    maxTokens: maxTokens
                )

                guard !samples.isEmpty else {
                    status = "Chunk \(index + 1) generated 0 samples"
                    continue
                }

                status = "Speaking chunk \(index + 1)/\(chunks.count)..."
                try player.play(samples: samples)
            }

            let total = Date().timeIntervalSince(start)
            timerTask.cancel()
            elapsedText = String(format: "Elapsed: %.1fs", total)
            status = "Finished generating. Audio is playing."

        } catch {
            timerTask.cancel()
            status = "Error: \(error.localizedDescription)"
        }
    }
}
