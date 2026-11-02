import Foundation

@main
struct SplatRegression {
    static func main() throws {
        let names = ["x", "y", "z", "f_dc_0", "f_dc_1", "f_dc_2", "opacity", "scale_0", "scale_1", "scale_2", "rot_0", "rot_1", "rot_2", "rot_3"]
        func fixture(_ values: [Float], properties: [String] = names, extraHeader: String = "", prefix: Data = Data()) -> Data {
            let header = "ply\nformat binary_little_endian 1.0\n\(extraHeader)element vertex 1\n" + properties.map { "property float \($0)\n" }.joined() + "end_header\n"
            var data = Data(header.utf8)
            data.append(prefix)
            for value in values {
                var bits = value.bitPattern.littleEndian
                withUnsafeBytes(of: &bits) { data.append(contentsOf: $0) }
            }
            return data
        }
        func require(_ condition: @autoclosure () -> Bool, _ message: String) {
            if !condition() { fatalError(message) }
        }
        func rejects(_ data: Data, _ message: String) {
            do { _ = try GaussianSplatFile.parse(data); fatalError(message) }
            catch { }
        }
        let values: [Float] = [1, 2, 3, 0.1, 0.2, 0.3, 0, -2, -3, -4, 1, 0, 0, 0]
        let cloud = try GaussianSplatFile.parse(fixture(values))
        require(cloud.count == 1, "Valid Gaussian PLY must load its vertex")
        require(cloud.positions == [1, 2, 3], "Positions must preserve scene coordinates")
        require(cloud.scales == [-2, -3, -4], "Log-space scale must not be converted twice")
        require(cloud.rotations == [1, 0, 0, 0], "PLY quaternion order must remain w,x,y,z")
        require(cloud.harmonics == [0.1, 0.2, 0.3], "Degree-zero diffuse coefficients must be retained")
        require(cloud.degree == 0, "No higher coefficients means SH degree zero")
        var invisible = values; invisible[6] = -.infinity
        let hidden = try GaussianSplatFile.parse(fixture(invisible))
        require(hidden.opacities == [-80], "Negative-infinity opacity from Apple's capture must stay effectively transparent")

        let metadata = try GaussianSplatFile.parse(fixture(values, extraHeader: "element metadata 2\nproperty uchar flag\n", prefix: Data([5, 6])))
        require(metadata.positions == [1, 2, 3], "Metadata before vertices must be skipped with its actual byte stride")
        let higherNames = names + (0..<9).map { "f_rest_\($0)" }
        let higher = try GaussianSplatFile.parse(fixture(values + [1, 2, 3, 4, 5, 6, 7, 8, 9], properties: higherNames))
        require(higher.degree == 1, "Nine rest coefficients mean SH degree one")
        require(higher.harmonics == [0.1, 0.2, 0.3, 1, 4, 7, 2, 5, 8, 3, 6, 9], "SH must transpose channel-major PLY into RGB triplets")
        rejects(Data(fixture(values).dropLast()), "Truncated data must not upload past its end")
        rejects(fixture(Array(values.dropLast()), properties: Array(names.dropLast())), "Missing quaternion component must fail")
        var nonfinite = values; nonfinite[0] = .nan
        rejects(fixture(nonfinite), "Non-finite geometry must fail before GPU upload")
        rejects(Data("ply\nformat ascii 1.0\nelement vertex 0\nend_header\n".utf8), "Unsupported PLY encoding must fail clearly")
        rejects(Data("ply\nformat binary_little_endian 1.0\nproperty\nend_header\n".utf8), "Malformed properties must fail without indexing past tokens")
        if CommandLine.arguments.count > 1 {
            let plant = try GaussianSplatFile.read(URL(fileURLWithPath: CommandLine.arguments[1]))
            require(plant.count == 51_352, "Apple's real capture must load every splat")
            require(plant.degree == 3, "Apple plant uses degree-three SH")
            require(plant.positions.count == 154_056, "Real capture geometry must retain full point count")
        }
        print("Splat regression checks passed")
    }
}
