#!/usr/bin/env python3
"""Exercise the actual procedural meshes and bounded RealityKit cache on macOS."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
folder = root / 'STARSHIP NEMURU/Flight'
universe = (folder / 'Universe.swift').read_text()
geometry = (folder / 'PolygonFactory.swift').read_text().replace('import UIKit', 'import AppKit\ntypealias UIColor = NSColor')
renderer = (folder / 'UniverseScene.swift').read_text()
checks = r'''
@main struct RendererChecks {
    static func check(_ value: Bool, _ message: String = "check failed", line: UInt = #line) {
        if !value {
            FileHandle.standardError.write(Data("FAIL line \(line): \(message)\n".utf8))
            exit(1)
        }
    }
    @MainActor static func main() throws {
        let world = Universe()
        let scene = UniverseScene()
        for _ in 0..<80 { scene.update(world, dt: 1 / 60) }
        check(scene.renderedCount > 0 && scene.buildFailure == nil)
        check(scene.root.children.contains { $0.name == "C–18" })
        let firstCount = scene.renderedCount
        var maximum = firstCount
        // Many replacements and diagonal/negative sector crossings through the actual cache.
        for step in 0..<100 {
            let displacement = SIMD3<Float>(640, step % 2 == 0 ? 320 : -320, -320)
            world.advance(displacement)
            for _ in 0..<30 { scene.update(world, dt: 1 / 30) }
            check(scene.buildFailure == nil)
            check(scene.renderedCount <= UniverseScene.maximumPlanets + UniverseScene.maximumClusters)
            check(scene.root.children.count == scene.renderedCount, "Evicted meshes must leave the scene graph")
            maximum = max(maximum, scene.renderedCount)
            for child in scene.root.children {
                check(child.position.x.isFinite && child.position.y.isFinite && child.position.z.isFinite)
                check(simd_length(child.position) < 1300)
            }
        }
        check(!scene.root.children.contains { $0.name == "C–18" })
        for step in (0..<100).reversed() {
            world.advance(-SIMD3<Float>(640, step % 2 == 0 ? 320 : -320, -320))
            for _ in 0..<30 { scene.update(world, dt: 1 / 30) }
        }
        check(world.position == UniversePosition())
        check(scene.root.children.contains { $0.name == "C–18" })
        for palette in PlanetPalette.allCases {
            let definition = PlanetDefinition(sector: .zero, offset: .zero, seed: 48 + UInt64(palette.rawValue),
                radius: 42, roughness: 0.075, palette: palette, name: "TEST")
            let planet = try PolygonFactory.planet(definition)
            let terrain = try PolygonFactory.terrain(definition)
            check(!planet.children.isEmpty && !terrain.children.isEmpty)
            let bound = planet.visualBounds(relativeTo: planet)
            check(bound.extents.max() <= definition.collisionRadius * 2 + 0.01,
                         "Visible planet geometry must fit its collision sphere")
        }
        print("PASS actual meshes, all palettes/terrain, 200 streamed replacements and return")
        print("PASS bounded RealityKit cache: initial \(firstCount), peak \(maximum), limit \(UniverseScene.maximumPlanets + UniverseScene.maximumClusters)")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='nemuru-render-check-') as temporary:
    path = Path(temporary)
    source = path / 'Checks.swift'
    source.write_text(universe + '\n' + geometry + '\n' + renderer + '\n' + checks)
    executable = path / 'checks'
    subprocess.run(['xcrun', '--sdk', 'macosx', 'swiftc', '-O', '-parse-as-library',
                    '-default-isolation', 'MainActor', '-module-cache-path', str(path / 'modules'),
                    str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
