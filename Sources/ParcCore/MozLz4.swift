import Compression
import Foundation

package enum MozLz4 {
    package enum Failure: Error, Equatable { case encrypted, notMozLz4, tooLarge, corrupt }

    static let magic = Data("mozLz40\0".utf8)
    static let encryptedMagic = Data("mozEnc0\0".utf8)
    static let maximumSize = 256 * 1024 * 1024

    package static func decode(_ data: Data) throws -> Data {
        guard data.count >= 12 else { throw Failure.notMozLz4 }
        let header = data.prefix(8)
        if header == encryptedMagic { throw Failure.encrypted }
        guard header == magic else { throw Failure.notMozLz4 }
        let size = data.dropFirst(8).prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        guard size <= maximumSize else { throw Failure.tooLarge }
        guard size > 0 else { return Data() }
        let block = data.dropFirst(12)
        guard !block.isEmpty else { throw Failure.corrupt }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { target in
            block.withUnsafeBytes { source in
                compression_decode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, size,
                                          source.bindMemory(to: UInt8.self).baseAddress!, block.count,
                                          nil, COMPRESSION_LZ4_RAW)
            }
        }
        guard written == size else { throw Failure.corrupt }
        return output
    }

    package static func json(at url: URL) throws -> Any {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? Int ?? .max) <= maximumSize else { throw Failure.tooLarge }
        return try JSONSerialization.jsonObject(with: decode(Data(contentsOf: url)))
    }

    package static func encode(_ data: Data) -> Data {
        guard !data.isEmpty else { return magic + Data(count: 4) }
        var block = Data(count: max(64, data.count + data.count / 255 + 16))
        let capacity = block.count
        let written = block.withUnsafeMutableBytes { target in
            data.withUnsafeBytes { source in
                compression_encode_buffer(target.bindMemory(to: UInt8.self).baseAddress!, capacity,
                                          source.bindMemory(to: UInt8.self).baseAddress!, data.count,
                                          nil, COMPRESSION_LZ4_RAW)
            }
        }
        var size = Data(count: 4)
        for offset in 0..<4 { size[offset] = UInt8((data.count >> (8 * offset)) & 0xFF) }
        return magic + size + block.prefix(written)
    }
}
