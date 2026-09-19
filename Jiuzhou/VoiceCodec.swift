import Foundation

enum VoiceCodec {
    enum Failure: Error { case invalidAMR, unavailable }
    private static let header = Data("#!AMR\n".utf8)

    static func encode(_ samples: [Int16]) throws -> Data {
        guard let state = Encoder_Interface_init(0) else { throw Failure.unavailable }
        defer { Encoder_Interface_exit(state) }
        var data = header
        for start in stride(from: 0, to: samples.count, by: 160) {
            var frame = Array(samples[start..<min(start + 160, samples.count)])
            frame += Array(repeating: 0, count: 160 - frame.count)
            var encoded = [UInt8](repeating: 0, count: 32)
            let length = Encoder_Interface_Encode(state, MR122, &frame, &encoded, 0)
            guard length > 0, length <= 32 else { throw Failure.invalidAMR }
            data.append(contentsOf: encoded.prefix(Int(length)))
        }
        return data
    }

    static func decode(_ data: Data) throws -> [Int16] {
        guard data.starts(with: header), let state = Decoder_Interface_init() else { throw Failure.invalidAMR }
        defer { Decoder_Interface_exit(state) }
        let bytes = Array(data)
        let lengths = [13, 14, 16, 18, 20, 21, 27, 32, 6, 0, 0, 0, 0, 0, 0, 1]
        var offset = header.count
        var samples: [Int16] = []
        while offset < bytes.count {
            let length = lengths[Int((bytes[offset] >> 3) & 15)]
            guard length > 0, offset + length <= bytes.count else { throw Failure.invalidAMR }
            var frame = Array(bytes[offset..<offset + length])
            frame += Array(repeating: 0, count: 32 - frame.count)
            var decoded = [Int16](repeating: 0, count: 160)
            Decoder_Interface_Decode(state, &frame, &decoded, bytes[offset] & 4 == 0 ? 1 : 0)
            samples += decoded
            offset += length
        }
        return samples
    }

    #if DEBUG
    static func verify() {
        let samples = (0..<1600).map { Int16(sin(Double($0) * 0.2) * 10000) }
        guard let encoded = try? encode(samples), let decoded = try? decode(encoded),
              decoded.count == samples.count, decoded.contains(where: { $0 != 0 }) else {
            preconditionFailure("AMR codec failed round-trip verification")
        }
        precondition((try? decode(Data("not amr".utf8))) == nil)
        precondition((try? decode(encoded.dropLast())) == nil)
    }
    #endif
}
