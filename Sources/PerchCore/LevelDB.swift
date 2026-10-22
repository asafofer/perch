import Foundation

/// Just enough of LevelDB to read a Chromium IndexedDB folder: its log files and its table files, newest write of each key
/// wins, deletions honoured. Read only, and nothing is locked: the app goes on writing while Perch reads, so a record cut off
/// mid-write is skipped, never trusted.
enum LevelDB {
    /// Every live key's latest value in `dir`.
    static func read(_ dir: URL) -> [Data: Data] {
        let fm = FileManager.default
        let files = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
        var latest: [Data: (seq: UInt64, value: Data?)] = [:]
        func put(_ key: Data, _ seq: UInt64, _ value: Data?) {
            if let old = latest[key], old.seq > seq { return }
            latest[key] = (seq, value)
        }
        for f in files where f.pathExtension == "ldb" || f.pathExtension == "sst" {
            guard let data = try? Data(contentsOf: f, options: .alwaysMapped) else { continue }
            table([UInt8](data), put)
        }
        for f in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where f.pathExtension == "log" {
            guard let data = try? Data(contentsOf: f, options: .alwaysMapped) else { continue }
            log([UInt8](data), put)
        }
        var out: [Data: Data] = [:]
        for (k, v) in latest { if let value = v.value { out[k] = value } }
        return out
    }

    static func varint(_ b: [UInt8], _ i: inout Int) -> Int? {
        var r = 0, s = 0
        while i < b.count, s < 63 { let c = Int(b[i]); i += 1; r |= (c & 0x7F) << s; s += 7; if c < 0x80 { return r } }
        return nil
    }
    static func u32(_ b: [UInt8], _ i: Int) -> Int { Int(b[i]) | Int(b[i + 1]) << 8 | Int(b[i + 2]) << 16 | Int(b[i + 3]) << 24 }

    /// The write-ahead log: 32 KB blocks of records (7-byte header: checksum, length, type), a record's pieces joined, each
    /// whole record a batch of puts and deletes after its sequence number.
    static func log(_ b: [UInt8], _ put: (Data, UInt64, Data?) -> Void) {
        var pending: [UInt8] = [], block = 0
        while block < b.count {
            var i = block
            let end = min(block + 32_768, b.count)
            while i + 7 <= end {
                let len = Int(b[i + 4]) | Int(b[i + 5]) << 8, type = b[i + 6]
                if type == 0 && len == 0 { break }
                guard i + 7 + len <= end else { break }
                let piece = b[(i + 7)..<(i + 7 + len)]
                i += 7 + len
                switch type {
                case 1: batch(Array(piece), put)
                case 2: pending = Array(piece)
                case 3: pending += piece
                case 4: pending += piece; batch(pending, put); pending = []
                default: break
                }
            }
            block += 32_768
        }
    }

    private static func batch(_ r: [UInt8], _ put: (Data, UInt64, Data?) -> Void) {
        guard r.count >= 12 else { return }
        var seq: UInt64 = 0
        for k in 0..<8 { seq |= UInt64(r[k]) << (8 * UInt64(k)) }
        let n = u32(r, 8)
        var i = 12
        for k in 0..<n {
            guard i < r.count else { return }
            let tag = r[i]; i += 1
            guard let kl = varint(r, &i), i + kl <= r.count else { return }
            let key = Data(r[i..<(i + kl)]); i += kl
            if tag == 1 {
                guard let vl = varint(r, &i), i + vl <= r.count else { return }
                put(key, seq + UInt64(k), Data(r[i..<(i + vl)])); i += vl
            } else {
                put(key, seq + UInt64(k), nil)
            }
        }
    }

    /// A table file: its footer points at the index block, whose entries point at the data blocks. Keys carry eight bytes
    /// after them: the sequence number and whether the entry is a value or a deletion.
    static func table(_ b: [UInt8], _ put: (Data, UInt64, Data?) -> Void) {
        guard b.count >= 48 else { return }
        var i = b.count - 48
        guard varint(b, &i) != nil, varint(b, &i) != nil, let io = varint(b, &i), let isz = varint(b, &i),
              let index = block(b, io, isz) else { return }
        entries(index) { _, handle in
            var j = 0
            guard let off = varint(handle, &j), let size = varint(handle, &j), let data = block(b, off, size) else { return }
            entries(data) { ikey, value in
                guard ikey.count >= 8 else { return }
                var tagged: UInt64 = 0
                for k in 0..<8 { tagged |= UInt64(ikey[ikey.count - 8 + k]) << (8 * UInt64(k)) }
                let key = Data(ikey[0..<(ikey.count - 8)])
                put(key, tagged >> 8, tagged & 0xFF == 1 ? Data(value) : nil)
            }
        }
    }

    /// A block's contents, uncompressed: it is followed by a byte saying how it was stored (0 plain, 1 Snappy) and a checksum.
    private static func block(_ b: [UInt8], _ off: Int, _ size: Int) -> [UInt8]? {
        guard off >= 0, size >= 0, off + size + 5 <= b.count else { return nil }
        let raw = b[off..<(off + size)]
        switch b[off + size] {
        case 0: return Array(raw)
        case 1: return Snappy.decompress(raw)
        default: return nil
        }
    }

    /// A block's entries, each key written as what it shares with the one before and the rest; the restart points at its end.
    private static func entries(_ b: [UInt8], _ each: ([UInt8], [UInt8]) -> Void) {
        guard b.count >= 4 else { return }
        let restarts = u32(b, b.count - 4)
        let end = b.count - 4 - restarts * 4
        guard end >= 0 else { return }
        var i = 0, key: [UInt8] = []
        while i < end {
            guard let shared = varint(b, &i), let rest = varint(b, &i), let vl = varint(b, &i),
                  shared <= key.count, i + rest + vl <= end else { return }
            key = Array(key[0..<shared]) + b[i..<(i + rest)]; i += rest
            each(key, Array(b[i..<(i + vl)])); i += vl
        }
    }
}
