import CoreGraphics

public enum DisplayOrdering {
    /// The display after (or before) `index`, ordered left to right, then top to bottom,
    /// wrapping around at the ends.
    /// - Returns: `nil` when there is no other display.
    public static func index(adjacentTo index: Int, among displays: [CGRect], backward: Bool) -> Int? {
        guard displays.count > 1, displays.indices.contains(index) else { return nil }
        let ordered = displays.indices.sorted {
            (displays[$0].minX, displays[$0].minY) < (displays[$1].minX, displays[$1].minY)
        }
        guard let position = ordered.firstIndex(of: index) else { return nil }
        let step = backward ? -1 : 1
        return ordered[(position + step + ordered.count) % ordered.count]
    }
}
