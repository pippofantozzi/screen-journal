/// A small grayscale copy of a screen, used only to detect change.
public struct Thumbnail: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let luma: [UInt8]

    public init(width: Int, height: Int, luma: [UInt8]) {
        self.width = width
        self.height = height
        self.luma = luma
    }

    /// Fraction of pixels whose brightness moved more than `tolerance`. 1 when sizes differ.
    public func changeRatio(to other: Thumbnail, tolerance: UInt8 = 12) -> Double {
        guard width == other.width, height == other.height, !luma.isEmpty else { return 1 }
        let changed = zip(luma, other.luma).count { a, b in (a > b ? a - b : b - a) > tolerance }
        return Double(changed) / Double(luma.count)
    }
}
