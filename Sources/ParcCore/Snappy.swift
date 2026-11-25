import Foundation

package enum Snappy {
    package static let maximumLength = 64 * 1024 * 1024

    package static func decompress(_ input: [UInt8], maximumLength: Int = maximumLength) -> [UInt8]? {
        var cursor = ByteCursor(input)
        guard let declared = cursor.varint(maximumBytes: 5), let length = Int(exactly: declared), length <= maximumLength else { return nil }
        var output: [UInt8] = []
        output.reserveCapacity(length)
        while let tag = cursor.byte() {
            switch tag & 3 {
            case 0:
                var literal = Int(tag >> 2)
                if literal >= 60 {
                    guard let range = cursor.take(literal - 59) else { return nil }
                    literal = 0
                    for (shift, index) in range.enumerated() { literal |= Int(input[index]) << (8 * shift) }
                }
                guard let range = cursor.take(literal + 1), range.count <= length - output.count else { return nil }
                output.append(contentsOf: input[range])
            case 1:
                guard let low = cursor.byte() else { return nil }
                guard copy(count: 4 + Int((tag >> 2) & 7), offset: Int(tag >> 5) << 8 | Int(low), into: &output, length: length) else { return nil }
            case 2:
                guard let range = cursor.take(2) else { return nil }
                let offset = Int(input[range.lowerBound]) | Int(input[range.lowerBound + 1]) << 8
                guard copy(count: 1 + Int(tag >> 2), offset: offset, into: &output, length: length) else { return nil }
            default:
                guard let offset = cursor.fixed32() else { return nil }
                guard copy(count: 1 + Int(tag >> 2), offset: Int(offset), into: &output, length: length) else { return nil }
            }
        }
        return output.count == length ? output : nil
    }

    private static func copy(count: Int, offset: Int, into output: inout [UInt8], length: Int) -> Bool {
        guard offset > 0, offset <= output.count, count <= length - output.count else { return false }
        let start = output.count - offset
        for index in 0..<count { output.append(output[start + index]) }
        return true
    }
}
