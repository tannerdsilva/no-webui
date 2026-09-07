// MARK: - Constant-time comparison

// constant-time equality over byte sequences. the length check short-circuits
// (lengths are public for MACs and tokens), but an equal-length comparison
// accumulates the XOR across the entire input without early exit, so a
// timing oracle cannot recover prefix bytes.

public func constantTimeEquals<L: Sequence, R: Sequence>(_ lhs: L, _ rhs: R) -> Bool
    where L.Element == UInt8, R.Element == UInt8
{
    let a = Array(lhs)
    let b = Array(rhs)
    guard a.count == b.count else { return false }
    var diff: UInt8 = 0
    for i in 0..<a.count {
        diff |= a[i] ^ b[i]
    }
    return diff == 0
}
