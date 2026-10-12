import Foundation

/// What panels reserve at the screen's edges on Linux (EWMH's _NET_WM_STRUT_PARTIAL), per display. A strut counts from
/// the edge of the whole X screen (all displays together), along a span of the other axis, so a top panel on one display
/// leaves a display beside it whole, and one below a taller neighbour is not cut at all. Rects are in X's coordinates
/// (top-left origin).
public enum PanelStruts {
    /// `m` less what the struts reserve over it. Each strut is twelve numbers: left, right, top, bottom, then the start and
    /// end of the left, right, top and bottom spans (UInt.max as an end means the whole edge).
    public static func free(_ m: CGRect, root: CGSize, struts: [[UInt]]) -> CGRect {
        var minX = m.minX, maxX = m.maxX, minY = m.minY, maxY = m.maxY
        func overlaps(_ a: UInt, _ b: UInt, _ lo: CGFloat, _ hi: CGFloat) -> Bool { CGFloat(a) < hi && (b == .max || CGFloat(b) >= lo) }
        for s in struts where s.count >= 12 {
            let left = CGFloat(s[0]), right = CGFloat(s[1]), top = CGFloat(s[2]), bottom = CGFloat(s[3])
            if top > 0, overlaps(s[8], s[9], m.minX, m.maxX), top > m.minY { minY = max(minY, min(top, m.maxY)) }
            if bottom > 0, overlaps(s[10], s[11], m.minX, m.maxX), root.height - bottom < m.maxY { maxY = min(maxY, max(root.height - bottom, m.minY)) }
            if left > 0, overlaps(s[4], s[5], m.minY, m.maxY), left > m.minX { minX = max(minX, min(left, m.maxX)) }
            if right > 0, overlaps(s[6], s[7], m.minY, m.maxY), root.width - right < m.maxX { maxX = min(maxX, max(root.width - right, m.minX)) }
        }
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }
}
