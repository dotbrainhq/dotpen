import CryptoKit
import Foundation

/// Copies of the text a person read, stored compressed and named by the SHA-256 of their bytes.
enum Snapshots {
    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func compress(_ data: Data) -> Data {
        (try? (data as NSData).compressed(using: .zlib) as Data) ?? data
    }

    static func decompress(_ data: Data) -> Data? {
        try? (data as NSData).decompressed(using: .zlib) as Data
    }
}
