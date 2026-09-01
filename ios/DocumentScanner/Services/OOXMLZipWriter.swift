import Foundation

/// Minimal ZIP archive writer used to package the hand-rolled OOXML parts
/// for DOCX/XLSX/PPTX export (DESIGN_SPEC §5/§9 "Office format export").
/// Foundation has no built-in ZIP writer, and pulling in a compression
/// dependency just to write a few KB of XML isn't worth it — so every entry
/// is written **stored** (uncompressed, compression method 0), which is
/// fully legal per the ZIP spec and universally supported by Word/Excel/
/// PowerPoint/Google's viewers. This trades a slightly larger file for not
/// needing a DEFLATE implementation at all.
struct OOXMLZipWriter {
    private struct Entry {
        let path: String
        let data: Data
        let crc32: UInt32
        let offset: UInt32
    }

    private var entries: [Entry] = []
    private var buffer = Data()

    /// Fixed MS-DOS date/time (2020-01-01 00:00:00) stamped on every entry —
    /// these files are generated fresh each export, so a real timestamp
    /// carries no useful information and a valid-but-arbitrary constant
    /// keeps the writer simple.
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = 0x5021

    mutating func add(path: String, string: String) {
        add(path: path, data: Data(string.utf8))
    }

    mutating func add(path: String, data: Data) {
        let crc = Self.crc32(data)
        let offset = UInt32(buffer.count)
        let nameBytes = Array(path.utf8)

        var local = Data()
        local.appendLE(UInt32(0x04034b50))
        local.appendLE(UInt16(20))
        local.appendLE(UInt16(0))
        local.appendLE(UInt16(0))
        local.appendLE(Self.dosTime)
        local.appendLE(Self.dosDate)
        local.appendLE(crc)
        local.appendLE(UInt32(data.count))
        local.appendLE(UInt32(data.count))
        local.appendLE(UInt16(nameBytes.count))
        local.appendLE(UInt16(0))
        local.append(contentsOf: nameBytes)
        local.append(data)

        buffer.append(local)
        entries.append(Entry(path: path, data: data, crc32: crc, offset: offset))
    }

    /// Finalizes the archive (central directory + end record) and returns
    /// the complete ZIP bytes.
    func finalize() -> Data {
        var result = buffer
        let centralDirectoryStart = UInt32(result.count)

        for entry in entries {
            let nameBytes = Array(entry.path.utf8)
            var record = Data()
            record.appendLE(UInt32(0x02014b50))
            record.appendLE(UInt16(20))
            record.appendLE(UInt16(20))
            record.appendLE(UInt16(0))
            record.appendLE(UInt16(0))
            record.appendLE(Self.dosTime)
            record.appendLE(Self.dosDate)
            record.appendLE(entry.crc32)
            record.appendLE(UInt32(entry.data.count))
            record.appendLE(UInt32(entry.data.count))
            record.appendLE(UInt16(nameBytes.count))
            record.appendLE(UInt16(0))
            record.appendLE(UInt16(0))
            record.appendLE(UInt16(0))
            record.appendLE(UInt16(0))
            record.appendLE(UInt32(0))
            record.appendLE(entry.offset)
            record.append(contentsOf: nameBytes)
            result.append(record)
        }

        let centralDirectorySize = UInt32(result.count) - centralDirectoryStart

        var end = Data()
        end.appendLE(UInt32(0x06054b50))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(0))
        end.appendLE(UInt16(entries.count))
        end.appendLE(UInt16(entries.count))
        end.appendLE(centralDirectorySize)
        end.appendLE(centralDirectoryStart)
        end.appendLE(UInt16(0))
        result.append(end)

        return result
    }

    /// Standard bit-by-bit CRC-32 (IEEE 802.3, polynomial 0xEDB88320) — the
    /// ZIP format's required checksum for each entry. Simplicity over
    /// speed: these files are a handful of small XML parts.
    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFFFFFF
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}

/// Shared XML-escaping helper for the hand-rolled OOXML writers.
enum XMLEscape {
    static func text(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.append(ch)
            }
        }
        return out
    }
}
