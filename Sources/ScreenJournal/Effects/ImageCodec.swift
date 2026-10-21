import CoreGraphics
import Foundation
import ImageIO
import JournalCore
import UniformTypeIdentifiers

enum ImageCodec {
    /// Grayscale thumbnail for change detection.
    static func thumbnail(of image: CGImage, width: Int = 96, height: Int = 60) -> Thumbnail {
        var luma = [UInt8](repeating: 0, count: width * height)
        luma.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
            context?.interpolationQuality = .low
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return Thumbnail(width: width, height: height, luma: luma)
    }

    /// HEIC, long side capped so a week stays a few GB.
    static func writeHEIC(_ image: CGImage, to url: URL, maxPixelSize: Int = 1600, quality: Double = 0.5) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        let longSide = max(image.width, image.height)
        let scaled = longSide > maxPixelSize ? resized(image, by: Double(maxPixelSize) / Double(longSide)) : image
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func resized(_ image: CGImage, by scale: Double) -> CGImage {
        let width = Int(Double(image.width) * scale), height = Int(Double(image.height) * scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
