import CoreGraphics
import JournalCore
import Vision

/// On-device OCR via Apple Vision. Nothing leaves the Mac.
enum TextRecognizer {
    /// Reading order: top to bottom, then left to right within a row.
    static func lines(in image: CGImage) async -> [TextLine] {
        await Task.detached(priority: .utility) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            // Correction costs ~4× the CPU for little accuracy, and "fixes" code, paths and names.
            request.usesLanguageCorrection = false
            request.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? [])
                .sorted { a, b in
                    abs(a.boundingBox.midY - b.boundingBox.midY) > 0.01
                        ? a.boundingBox.midY > b.boundingBox.midY
                        : a.boundingBox.minX < b.boundingBox.minX
                }
                .compactMap { observation in
                    observation.topCandidates(1).first.map {
                        let box = observation.boundingBox
                        return TextLine(text: $0.string, minX: box.minX, maxX: box.maxX, top: 1 - box.maxY, height: box.height)
                    }
                }
        }.value
    }
}
