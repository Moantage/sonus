import Foundation

/// MD5 (RFC 1321), only for Subsonic's token authentication, which requires it.
///
/// SonusCore builds on Linux, where CryptoKit isn't available, so this is a small portable copy.
/// Never use it for anything that needs a secure hash.
enum MD5 {
    /// Lowercase hex digest of the UTF-8 bytes of `string`.
    static func hex(_ string: String) -> String {
        digest(Array(string.utf8)).map { byte in
            let hex = String(byte, radix: 16)
            return byte < 16 ? "0" + hex : hex
        }.joined()
    }

    static func digest(_ input: [UInt8]) -> [UInt8] {
        var message = input
        let bitLength = UInt64(input.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        for index in 0..<8 {
            message.append(UInt8(truncatingIfNeeded: bitLength >> (8 * UInt64(index))))
        }

        var state: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476]
        var words = [UInt32](repeating: 0, count: 16)
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            for index in 0..<16 {
                let base = chunkStart + index * 4
                words[index] = UInt32(message[base])
                    | UInt32(message[base + 1]) << 8
                    | UInt32(message[base + 2]) << 16
                    | UInt32(message[base + 3]) << 24
            }
            state = compress(state, words: words)
        }

        var output: [UInt8] = []
        output.reserveCapacity(16)
        for word in state {
            for index in 0..<4 {
                output.append(UInt8(truncatingIfNeeded: word >> (8 * UInt32(index))))
            }
        }
        return output
    }

    /// One 64-byte block: the four state words in, the four new state words out.
    private static func compress(_ state: [UInt32], words: [UInt32]) -> [UInt32] {
        var aValue = state[0], bValue = state[1], cValue = state[2], dValue = state[3]
        for step in 0..<64 {
            var mixed: UInt32
            let wordIndex: Int
            switch step {
            case 0..<16:
                mixed = (bValue & cValue) | (~bValue & dValue)
                wordIndex = step
            case 16..<32:
                mixed = (dValue & bValue) | (~dValue & cValue)
                wordIndex = (5 * step + 1) % 16
            case 32..<48:
                mixed = bValue ^ cValue ^ dValue
                wordIndex = (3 * step + 5) % 16
            default:
                mixed = cValue ^ (bValue | ~dValue)
                wordIndex = (7 * step) % 16
            }
            mixed = mixed &+ aValue &+ constants[step] &+ words[wordIndex]
            aValue = dValue
            dValue = cValue
            cValue = bValue
            bValue = bValue &+ ((mixed << shifts[step]) | (mixed >> (32 - shifts[step])))
        }
        return [state[0] &+ aValue, state[1] &+ bValue, state[2] &+ cValue, state[3] &+ dValue]
    }

    private static let shifts: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    ]

    /// floor(abs(sin(i + 1)) * 2^32), as listed in RFC 1321.
    private static let constants: [UInt32] = [
        0xD76A_A478, 0xE8C7_B756, 0x2420_70DB, 0xC1BD_CEEE, 0xF57C_0FAF, 0x4787_C62A, 0xA830_4613, 0xFD46_9501,
        0x6980_98D8, 0x8B44_F7AF, 0xFFFF_5BB1, 0x895C_D7BE, 0x6B90_1122, 0xFD98_7193, 0xA679_438E, 0x49B4_0821,
        0xF61E_2562, 0xC040_B340, 0x265E_5A51, 0xE9B6_C7AA, 0xD62F_105D, 0x0244_1453, 0xD8A1_E681, 0xE7D3_FBC8,
        0x21E1_CDE6, 0xC337_07D6, 0xF4D5_0D87, 0x455A_14ED, 0xA9E3_E905, 0xFCEF_A3F8, 0x676F_02D9, 0x8D2A_4C8A,
        0xFFFA_3942, 0x8771_F681, 0x6D9D_6122, 0xFDE5_380C, 0xA4BE_EA44, 0x4BDE_CFA9, 0xF6BB_4B60, 0xBEBF_BC70,
        0x289B_7EC6, 0xEAA1_27FA, 0xD4EF_3085, 0x0488_1D05, 0xD9D4_D039, 0xE6DB_99E5, 0x1FA2_7CF8, 0xC4AC_5665,
        0xF429_2244, 0x432A_FF97, 0xAB94_23A7, 0xFC93_A039, 0x655B_59C3, 0x8F0C_CC92, 0xFFEF_F47D, 0x8584_5DD1,
        0x6FA8_7E4F, 0xFE2C_E6E0, 0xA301_4314, 0x4E08_11A1, 0xF753_7E82, 0xBD3A_F235, 0x2AD7_D2BB, 0xEB86_D391
    ]
}
