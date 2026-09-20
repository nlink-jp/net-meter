public enum GraphScale {
    /// 100 KB/s. Without a floor, trickle traffic on an idle link fills the graph.
    public static let defaultFloor = 100_000.0

    /// The rate drawn at full height: the largest value in the window, upstream
    /// and downstream together so the two can be compared, but never below `floor`.
    public static func fullScale(down: [Double], up: [Double], floor: Double = defaultFloor) -> Double {
        let peak = max(down.max() ?? 0, up.max() ?? 0)
        return max(floor, peak.isFinite ? peak : 0)
    }

    /// Height of `value` as a fraction of full scale, clamped to 0...1.
    public static func fraction(of value: Double, fullScale: Double) -> Double {
        guard fullScale > 0, value.isFinite, value > 0 else { return 0 }
        return min(value / fullScale, 1)
    }
}
