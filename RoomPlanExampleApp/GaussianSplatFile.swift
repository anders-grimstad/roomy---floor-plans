import Foundation

enum GaussianSplatFileError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self { case .invalid(let reason): return reason }
    }
}

/// The conventional 3DGS PLY layout: log scales, opacity logits, wxyz rotations,
/// and channel-major spherical harmonics. Parsing is independent of GPU support.
struct GaussianSplatFile: Sendable {
    let count: Int
    let degree: UInt8
    let positions: [Float]
    let scales: [Float]
    let rotations: [Float]
    let opacities: [Float]
    let harmonics: [Float]

    static func read(_ url: URL) throws -> Self {
        try parse(Data(contentsOf: url, options: .mappedIfSafe))
    }

    static func parse(_ data: Data) throws -> Self {
        let terminator = Data("end_header\n".utf8)
        let crlfTerminator = Data("end_header\r\n".utf8)
        let headerRange = data.range(of: terminator) ?? data.range(of: crlfTerminator)
        guard let headerRange,
              let header = String(data: data[..<headerRange.upperBound], encoding: .ascii) else {
            throw GaussianSplatFileError.invalid("This file has no readable PLY header.")
        }
        let lines = header.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first == "ply", lines.contains("format binary_little_endian 1.0") else {
            throw GaussianSplatFileError.invalid("Choose a binary little-endian Gaussian PLY file. ASCII, compressed PLY, and mesh-only PLY files are not supported.")
        }
        struct Element {
            let name: String
            let count: Int
            var stride = 0
            var fields: [String: (offset: Int, type: String)] = [:]
        }
        let widths = ["char": 1, "uchar": 1, "int8": 1, "uint8": 1,
                      "short": 2, "ushort": 2, "int16": 2, "uint16": 2,
                      "float": 4, "float32": 4, "int": 4, "uint": 4, "int32": 4, "uint32": 4,
                      "double": 8, "float64": 8, "int64": 8, "uint64": 8]
        var elements: [Element] = []
        for line in lines.dropFirst() {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let keyword = parts.first else { continue }
            if keyword == "element" {
                guard parts.count == 3, let count = Int(parts[2]), count >= 0 else {
                    throw GaussianSplatFileError.invalid("Invalid PLY element count.")
                }
                elements.append(Element(name: parts[1], count: count))
            } else if keyword == "property" {
                guard parts.count == 3, let width = widths[parts[1]], !elements.isEmpty else {
                    throw GaussianSplatFileError.invalid("PLY properties must be scalar values; list properties are not supported.")
                }
                let index = elements.count - 1
                guard elements[index].fields[parts[2]] == nil else {
                    throw GaussianSplatFileError.invalid("Duplicate PLY property: \(parts[2]).")
                }
                elements[index].fields[parts[2]] = (elements[index].stride, parts[1])
                elements[index].stride += width
            }
        }
        guard let vertexIndex = elements.firstIndex(where: { $0.name == "vertex" }),
              elements[vertexIndex].count > 0 else {
            throw GaussianSplatFileError.invalid("This PLY file contains no splats.")
        }
        var bodyOffset = headerRange.upperBound
        for element in elements.prefix(vertexIndex) {
            guard element.stride > 0, element.count <= (data.count - bodyOffset) / element.stride else {
                throw GaussianSplatFileError.invalid("PLY metadata is truncated.")
            }
            bodyOffset += element.count * element.stride
        }
        let vertex = elements[vertexIndex]
        guard vertex.stride > 0, vertex.count <= (data.count - bodyOffset) / vertex.stride else {
            throw GaussianSplatFileError.invalid("The PLY vertex data is truncated.")
        }
        func offsets(_ names: [String]) throws -> [Int] {
            try names.map { name in
                guard let field = vertex.fields[name], ["float", "float32"].contains(field.type) else {
                    throw GaussianSplatFileError.invalid("Missing float splat property: \(name). A mesh or point cloud is not a Gaussian splat asset.")
                }
                return field.offset
            }
        }
        let positionFields = try offsets(["x", "y", "z"])
        let scaleFields = try offsets((0..<3).map { "scale_\($0)" })
        let rotationFields = try offsets((0..<4).map { "rot_\($0)" })
        let opacityFields = try offsets(["opacity"])
        let diffuseFields = try offsets((0..<3).map { "f_dc_\($0)" })
        let restCount = vertex.fields.keys.filter { $0.hasPrefix("f_rest_") }.count
        guard let degreeIndex = [0, 9, 24, 45].firstIndex(of: restCount) else {
            throw GaussianSplatFileError.invalid("Spherical harmonics must have 0, 9, 24, or 45 higher-order coefficients.")
        }
        let restFields = try offsets((0..<restCount).map { "f_rest_\($0)" })
        let triplets = restCount / 3
        var positions: [Float] = [], scales: [Float] = [], rotations: [Float] = []
        var opacities: [Float] = [], harmonics: [Float] = []
        positions.reserveCapacity(vertex.count * 3)
        scales.reserveCapacity(vertex.count * 3)
        rotations.reserveCapacity(vertex.count * 4)
        opacities.reserveCapacity(vertex.count)
        harmonics.reserveCapacity(vertex.count * (restCount + 3))
        try data.withUnsafeBytes { bytes in
            func value(_ offset: Int, opacity: Bool = false) throws -> Float {
                let bits = bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
                let value = Float(bitPattern: UInt32(littleEndian: bits))
                // A logit of -infinity is a valid fully transparent splat in
                // Apple's sample. GPU buffers require a finite representation.
                if opacity && value.isInfinite { return value.sign == .minus ? -80 : 80 }
                guard value.isFinite else {
                    throw GaussianSplatFileError.invalid("This PLY file contains non-finite splat values.")
                }
                return value
            }
            for index in 0..<vertex.count {
                if index.isMultiple(of: 4096) { try Task.checkCancellation() }
                let base = bodyOffset + index * vertex.stride
                for field in positionFields { positions.append(try value(base + field)) }
                for field in scaleFields { scales.append(try value(base + field)) }
                for field in rotationFields { rotations.append(try value(base + field)) }
                for field in opacityFields { opacities.append(try value(base + field, opacity: true)) }
                for field in diffuseFields { harmonics.append(try value(base + field)) }
                for coefficient in 0..<triplets {
                    for channel in 0..<3 {
                        harmonics.append(try value(base + restFields[channel * triplets + coefficient]))
                    }
                }
            }
        }
        return Self(count: vertex.count, degree: UInt8(degreeIndex), positions: positions,
                    scales: scales, rotations: rotations, opacities: opacities, harmonics: harmonics)
    }
}
