//
//  WAVWriter.swift
//  LocalTxtReader
//
//  Created by Janice Yan on 4/27/26.
//


import Foundation

enum WAVWriter {
    static func write(samples: [Float], sampleRate: Int, to url: URL) throws {
        var data = Data()

        let clipped = samples.map { max(-1.0, min(1.0, $0)) }
        let pcm = clipped.map { Int16($0 * Float(Int16.max)) }

        let byteRate = sampleRate * 2
        let blockAlign: UInt16 = 2
        let bitsPerSample: UInt16 = 16
        let subchunk2Size = UInt32(pcm.count * 2)
        let chunkSize = UInt32(36) + subchunk2Size

        func appendString(_ value: String) {
            data.append(value.data(using: .ascii)!)
        }

        func appendUInt32(_ value: UInt32) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: 4))
        }

        func appendUInt16(_ value: UInt16) {
            var little = value.littleEndian
            data.append(Data(bytes: &little, count: 2))
        }

        appendString("RIFF")
        appendUInt32(chunkSize)
        appendString("WAVE")
        appendString("fmt ")
        appendUInt32(16)
        appendUInt16(1)
        appendUInt16(1)
        appendUInt32(UInt32(sampleRate))
        appendUInt32(UInt32(byteRate))
        appendUInt16(blockAlign)
        appendUInt16(bitsPerSample)
        appendString("data")
        appendUInt32(subchunk2Size)

        for sample in pcm {
            var little = sample.littleEndian
            data.append(Data(bytes: &little, count: 2))
        }

        try data.write(to: url)
    }
}