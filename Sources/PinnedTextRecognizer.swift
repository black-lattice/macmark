import AppKit
@preconcurrency import Vision
import VisionKit

struct PinnedTextRecognition {
    let text: String
    let analysis: ImageAnalysis?
}

@MainActor protocol PinnedTextRecognizing {
    func recognize(_ image: CGImage) async throws -> PinnedTextRecognition
}

@MainActor final class PinnedTextRecognizer: PinnedTextRecognizing {
    private static let analyzer = ImageAnalyzer()
    private let useLiveText: Bool
    init(useLiveText: Bool = ImageAnalyzer.isSupported) { self.useLiveText = useLiveText }

    func recognize(_ image: CGImage) async throws -> PinnedTextRecognition {
        try Task.checkCancellation()
        if useLiveText {
            do {
                var configuration = ImageAnalyzer.Configuration(.text)
                let languages = ImageAnalyzer.supportedTextRecognitionLanguages
                configuration.locales = ["zh-Hans", "zh-Hant", "en-US"].filter { languages.contains($0) }
                let analysis = try await Self.analyzer.analyze(image, orientation: .up, configuration: configuration)
                try Task.checkCancellation()
                return PinnedTextRecognition(text: analysis.transcript, analysis: analysis)
            } catch {
                // Unsupported devices or a failed Live Text analysis can still copy the OCR transcript.
                try Task.checkCancellation()
            }
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let languages = try request.supportedRecognitionLanguages()
        request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"].filter { languages.contains($0) }
        let text: String = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
                        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                        continuation.resume(returning: text)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { request.cancel() }
        try Task.checkCancellation()
        return PinnedTextRecognition(text: text, analysis: nil)
    }
}
