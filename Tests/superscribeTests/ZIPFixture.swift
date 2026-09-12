import Foundation

internal enum ZIPFixture {
    internal struct Entry {
        internal let name: String
        internal var data = Data()
        internal var mode: UInt32 = 0o100644
    }

    internal static func encoderBundle(named name: String) -> Data {
        return Self.archive([Entry(name: name + "/", mode: 0o040755), Entry(name: name + "/model.mil", data: Data("fixture".utf8))])
    }

    internal static func archive(_ entries: [Entry]) -> Data {
        var result = Data()
        var central = Data()
        for entry in entries {
            let name = Data(entry.name.utf8)
            let checksum = Self.crc32(entry.data)
            let offset = UInt32(result.count)
            for value: UInt32 in [0x0403_4b50] { Self.append(value, to: &result) }
            for value: UInt16 in [20, 0x0800, 0, 0, 0] { Self.append(value, to: &result) }
            for value in [checksum, UInt32(entry.data.count), UInt32(entry.data.count)] { Self.append(value, to: &result) }
            for value: UInt16 in [UInt16(name.count), 0] { Self.append(value, to: &result) }
            result.append(name)
            result.append(entry.data)
            Self.append(UInt32(0x0201_4b50), to: &central)
            for value: UInt16 in [0x0314, 20, 0x0800, 0, 0, 0] { Self.append(value, to: &central) }
            for value in [checksum, UInt32(entry.data.count), UInt32(entry.data.count)] { Self.append(value, to: &central) }
            for value: UInt16 in [UInt16(name.count), 0, 0, 0, 0] { Self.append(value, to: &central) }
            Self.append(entry.mode << 16, to: &central)
            Self.append(offset, to: &central)
            central.append(name)
        }
        let start = UInt32(result.count)
        result.append(central)
        Self.append(UInt32(0x0605_4b50), to: &result)
        for value: UInt16 in [0, 0, UInt16(entries.count), UInt16(entries.count)] { Self.append(value, to: &result) }
        Self.append(UInt32(central.count), to: &result)
        Self.append(start, to: &result)
        Self.append(UInt16(0), to: &result)
        return result
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) -> Void {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func crc32(_ bytes: Data) -> UInt32 {
        var result: UInt32 = .max
        for byte in bytes {
            result ^= UInt32(byte)
            for _ in 0 ..< 8 { result = (result >> 1) ^ (result & 1 == 1 ? 0xedb8_8320 : 0) }
        }
        return ~result
    }
}
