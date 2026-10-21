import CoreGraphics
import Vision

/// On-device OCR via Apple Vision. Nothing leaves the Mac.
enum TextRecognizer {
    static func text(in image: CGImage) async -> String {
        await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? [])
                .sorted { a, b in
                    abs(a.boundingBox.midY - b.boundingBox.midY) > 0.01
                        ? a.boundingBox.midY > b.boundingBox.midY
                        : a.boundingBox.minX < b.boundingBox.minX
                }
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
        }.value
    }
}
