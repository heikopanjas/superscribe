/// Holds only the unfinished overlap between consecutive isolation sections.
internal struct IsolationOverlap {
    internal let frames: Int
    private var pending: [Float] = []

    internal init(frames: Int) {
        self.frames = frames
    }

    internal mutating func append(_ samples: [Float], final: Bool) -> [Float] {
        var output = samples
        let count = min(self.pending.count, output.count)
        for index in 0 ..< count {
            let weight = Float(index + 1) / Float(count + 1)
            output[index] = self.pending[index] * (1 - weight) + output[index] * weight
        }
        let retained = final ? 0 : min(self.frames, output.count)
        self.pending = Array(output.suffix(retained))
        return Array(output.dropLast(retained))
    }
}
