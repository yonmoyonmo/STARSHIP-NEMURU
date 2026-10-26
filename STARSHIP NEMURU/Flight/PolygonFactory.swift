import RealityKit
import UIKit
import simd

@MainActor
enum PolygonFactory {
    static func material(_ color: UIColor) -> UnlitMaterial { UnlitMaterial(color: color) }

    /// Separate triangle vertices preserve deliberately flat, independently colored faces.
    static func mesh(_ triangles: [[SIMD3<Float>]]) throws -> MeshResource {
        var descriptor = MeshDescriptor()
        let vertices = triangles.flatMap { $0 }
        descriptor.positions = MeshBuffers.Positions(vertices)
        descriptor.primitives = .triangles((0..<UInt32(vertices.count)).map { $0 })
        descriptor.normals = MeshBuffers.Normals(triangles.flatMap { face -> [SIMD3<Float>] in
            let cross = simd_cross(face[1] - face[0], face[2] - face[0])
            let n = simd_length(cross) > 0.0001 ? simd_normalize(cross) : SIMD3<Float>(0, 1, 0)
            return [n, n, n]
        })
        return try MeshResource.generate(from: [descriptor])
    }

    static func ship() throws -> Entity {
        let root = Entity()
        let nose: SIMD3<Float> = [0, 0, -2.8]
        let top: SIMD3<Float> = [0, 0.65, 0.65]
        let bottom: SIMD3<Float> = [0, -0.35, 1.15]
        let left: SIMD3<Float> = [-0.85, 0, 1.5]
        let right: SIMD3<Float> = [0.85, 0, 1.5]
        let faces = [[nose, top, left], [nose, right, top], [nose, left, bottom],
                     [nose, bottom, right], [top, right, left], [left, right, bottom]]
        let colors: [UIColor] = [UIColor(red: 0.52, green: 0.65, blue: 0.65, alpha: 1),
                                 UIColor(red: 0.29, green: 0.40, blue: 0.43, alpha: 1),
                                 UIColor(red: 0.17, green: 0.24, blue: 0.29, alpha: 1)]
        for (i, face) in faces.enumerated() {
            let model = ModelEntity(mesh: try mesh([face, face.reversed().map { $0 }]), materials: [material(colors[i % colors.count])])
            root.addChild(model)
        }
        for side: Float in [-1, 1] {
            let wing: [SIMD3<Float>] = [[side * 0.5, 0, -0.6], [side * 2.2, -0.15, 1.8], [side * 0.65, 0.1, 1.4]]
            root.addChild(ModelEntity(mesh: try mesh([wing, wing.reversed().map { $0 }]), materials: [material(colors[1])]))
            let engine = ModelEntity(mesh: .generateBox(size: [0.32, 0.23, 0.12]),
                                     materials: [material(UIColor(red: 0.012, green: 0.022, blue: 0.025, alpha: 1))])
            engine.name = side < 0 ? "thruster.left" : "thruster.right"
            engine.position = [side * 0.53, 0.02, 1.52]
            root.addChild(engine)
        }
        let cabin = ModelEntity(mesh: .generateBox(size: [0.5, 0.18, 0.8]),
                                materials: [material(UIColor(red: 0.10, green: 0.20, blue: 0.23, alpha: 1))])
        cabin.position = [0, 0.45, -0.25]
        root.addChild(cabin)
        return root
    }

    static func planet(_ definition: PlanetDefinition = .home) throws -> Entity {
        let root = Entity()
        var random = SeededRandom(seed: definition.seed)
        let paletteColors = definition.colors
        let rows = 8 + Int(definition.seed % 5), columns = 14 + Int((definition.seed >> 4) % 7)
        func point(_ row: Int, _ col: Int) -> SIMD3<Float> {
            let latitude = Float(row) / Float(rows) * .pi
            let longitude = Float(col) / Float(columns) * 2 * .pi
            let shape = 1 + definition.roughness * sin(latitude * 3) * sin(longitude * 4 + Float(definition.seed % 31))
            return SIMD3(sin(latitude) * cos(longitude), cos(latitude), sin(latitude) * sin(longitude)) * definition.radius * shape
        }
        var groups = Array(repeating: [[SIMD3<Float>]](), count: 6)
        for row in 0..<rows {
            for col in 0..<columns {
                let a = point(row, col), b = point(row + 1, col), c = point(row + 1, col + 1), d = point(row, col + 1)
                let shade = min(5, Int((a.y / definition.radius * 0.15 + a.x / definition.radius * 0.22 + random.range(0.15, 0.65)) * 6))
                if row > 0 { groups[max(0, shade)].append([a, d, b]) }
                if row < rows - 1 { groups[max(0, shade)].append([b, d, c]) }
            }
        }
        for (index, faces) in groups.enumerated() where !faces.isEmpty {
            let color = paletteColors.low + (paletteColors.high - paletteColors.low) * Float(index) / 5
            root.addChild(ModelEntity(mesh: try mesh(faces), materials: [material(uiColor(color))]))
        }
        root.orientation = simd_quatf(angle: 0.3, axis: [0, 0, 1])
        return root
    }

    static func uiColor(_ rgb: SIMD3<Float>) -> UIColor {
        UIColor(red: CGFloat(rgb.x), green: CGFloat(rgb.y), blue: CGFloat(rgb.z), alpha: 1)
    }

    static func cluster(_ definition: ClusterDefinition) throws -> Entity {
        let root = Entity()
        var random = SeededRandom(seed: definition.seed)
        var groups = Array(repeating: [[SIMD3<Float>]](), count: 3)
        let corners: [SIMD3<Float>] = [[-1,-1,-1], [1,-1,-1], [1,1,-1], [-1,1,-1],
                                      [-1,-1,1], [1,-1,1], [1,1,1], [-1,1,1]]
        let faces = [[0,2,1], [0,3,2], [4,5,6], [4,6,7], [0,1,5], [0,5,4],
                     [3,7,6], [3,6,2], [0,4,7], [0,7,3], [1,2,6], [1,6,5]]
        for index in 0..<(80 + Int(definition.seed % 61)) {
            func bell(_ random: inout SeededRandom) -> Float {
                (random.value() + random.value() + random.value() - 1.5) / 1.5
            }
            let position = SIMD3(bell(&random) * 95, bell(&random) * 45, bell(&random) * 65)
            let size = random.range(0.3, 0.9)
            for face in faces { groups[index % 3].append(face.map { position + corners[$0] * size }) }
        }
        let colors = StarColors.cluster(seed: definition.seed)
        for (index, triangles) in groups.enumerated() {
            root.addChild(ModelEntity(mesh: try mesh(triangles), materials: [material(uiColor(colors[index]))]))
        }
        root.orientation = simd_quatf(angle: random.range(-1, 1), axis: simd_normalize(SIMD3<Float>(1, 2, 1)))
        return root
    }

    static func restingSky(seed: UInt64, starVisibility: Float = 1) throws -> Entity {
        let root = Entity()
        var random = SeededRandom(seed: seed ^ 0x534B59)
        var groups = Array(repeating: [[SIMD3<Float>]](), count: StarColors.tints.count)
        var colorRandom = SeededRandom(seed: seed ^ 0x53544152434F4C)
        var trails = Array(repeating: [[SIMD3<Float>]](), count: 3)
        let corners: [SIMD3<Float>] = [[1,0,0], [-1,0,0], [0,1,0], [0,-1,0], [0,0,1], [0,0,-1]]
        let faces = [[0,2,4], [2,1,4], [1,3,4], [3,0,4], [2,0,5], [1,2,5], [3,1,5], [0,3,5]]
        for index in 0..<1440 {
            let y = random.range(-1, 1)
            let angle = random.range(0, 2 * .pi)
            let ring = sqrt(max(0, 1 - y * y))
            let center = SIMD3(ring * cos(angle), y, ring * sin(angle)) * 350
            let size = random.range(0.25, 0.7)
            let colorIndex = StarColors.index(sample: colorRandom.value())
            for face in faces { groups[colorIndex].append(face.map { center + corners[$0] * size }) }
            // Short, fading arcs behind a sparse subset of stars reveal the sky's common orbit.
            if index.isMultiple(of: 6) {
                for step in 0..<9 {
                    let a = simd_quatf(angle: -0.055 * Float(step) / 9, axis: RestingSkyMotion.axis).act(center)
                    let b = simd_quatf(angle: -0.055 * Float(step + 1) / 9, axis: RestingSkyMotion.axis).act(center)
                    let tangent = b - a
                    guard simd_length(tangent) > 0.00001 else { continue }
                    let side = simd_normalize(simd_cross(tangent, a)) * size * 0.65
                    let first = [a - side, b - side, a + side]
                    let second = [a + side, b - side, b + side]
                    trails[step / 3] += [first, second, first.reversed().map { $0 }, second.reversed().map { $0 }]
                }
            }
        }
        let colors = StarColors.tints
        for (index, triangles) in groups.enumerated() {
            var tint = material(uiColor(colors[index]))
            if starVisibility < 1 { tint.blending = .transparent(opacity: .init(floatLiteral: starVisibility)) }
            root.addChild(ModelEntity(mesh: try mesh(triangles), materials: [tint]))
        }
        for (index, triangles) in trails.enumerated() {
            let strength: Float = [0.48, 0.28, 0.14][index]
            let trail = ModelEntity(mesh: try mesh(triangles),
                materials: [material(uiColor(SIMD3<Float>(0.50, 0.60, 0.61) * strength))])
            trail.isEnabled = starVisibility > 0.9
            root.addChild(trail)
        }
        return root
    }

    static func terrain(_ definition: PlanetDefinition = .home) throws -> Entity {
        let root = Entity()
        var random = SeededRandom(seed: definition.seed &* 100)
        let paletteColors = definition.colors
        let size = 18
        var heights = Array(repeating: Array(repeating: Float.zero, count: size + 1), count: size + 1)
        for x in 0...size {
            for z in 0...size {
                let distance = hypot(Float(x - size / 2), Float(z - size / 2))
                heights[x][z] = distance < 2 ? -1 : -1 + random.range(0, 1) * min(distance, 6) * 0.65
            }
        }
        var groups = Array(repeating: [[SIMD3<Float>]](), count: 5)
        func point(_ x: Int, _ z: Int) -> SIMD3<Float> {
            [Float(x - size / 2) * 7, heights[x][z], Float(z - size / 2) * 7]
        }
        for x in 0..<size {
            for z in 0..<size {
                let i = Int(random.range(0, 4.99))
                groups[i].append([point(x, z), point(x, z + 1), point(x + 1, z)])
                groups[i].append([point(x + 1, z), point(x, z + 1), point(x + 1, z + 1)])
            }
        }
        for (i, faces) in groups.enumerated() {
            let color = paletteColors.low * 0.65 + (paletteColors.high - paletteColors.low) * Float(i) / 4 * 0.4
            root.addChild(ModelEntity(mesh: try mesh(faces), materials: [material(uiColor(color))]))
        }
        return root
    }
}
