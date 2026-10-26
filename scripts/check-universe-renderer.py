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
sky_motion = (folder / 'RestingSkyMotion.swift').read_text()
star_colors = (folder / 'StarColors.swift').read_text()
thrusters = (folder / 'ShipThrusters.swift').read_text().replace('import UIKit', 'import AppKit')
cosmetics = '\n'.join((folder / name).read_text() for name in ['VoyageScenery.swift', 'SceneryGeometry.swift', 'QuietSceneryGeometry.swift', 'RestingAurora.swift', 'RestingDawn.swift', 'QuietDiscovery.swift', 'QuietActivity.swift', 'ConstellationScene.swift', 'ActivityScene.swift'])
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
        let cosmetics = VoyageScenery()
        for _ in 0..<180 { scene.update(world, dt: 1 / 60); cosmetics.update(world, dt: 1 / 60, reduceMotion: false) }
        check(cosmetics.root.children.contains { $0.name == "dust-river" })
        check(cosmetics.root.children.contains { $0.name == "lonely-comet" })
        check(scene.renderedCount > 0 && scene.buildFailure == nil)
        check(scene.root.children.contains { $0.name == "C–18" })
        check(scene.root.children.contains { simd_length($0.position) > 2400 && $0.isEnabled },
              "Planets beyond the gameplay neighborhood must be visible")
        check(world.sectors.count == Universe.maximumSectorCount, "The horizon must not expand gameplay streaming")
        let remote = scene.root.children.first { simd_length($0.position) > 2400 && $0.isEnabled }!
        let approach = remote.position * (1 - 700 / simd_length(remote.position))
        world.advance(approach)
        for _ in 0..<180 { scene.update(world, dt: 1 / 60) }
        check(scene.root.children.contains { $0 === remote }, "Distant-to-near approach must preserve the actual planet entity")
        check(remote.isEnabled && abs(remote.scale.x - 1) < 0.001)
        world.advance(-approach)
        for _ in 0..<180 { scene.update(world, dt: 1 / 60) }
        check(world.position == UniversePosition())
        print("PASS planets beyond 2,400 units, unchanged 125 gameplay sectors, seamless distant-to-near approach")
        let firstCount = scene.renderedCount
        var maximum = firstCount
        // Many replacements and diagonal/negative sector crossings through the actual cache.
        for step in 0..<100 {
            let displacement = SIMD3<Float>(640, step % 2 == 0 ? 320 : -320, -320)
            world.advance(displacement)
            for _ in 0..<30 { scene.update(world, dt: 1 / 30); cosmetics.update(world, dt: 1 / 30, reduceMotion: false) }
            check(cosmetics.buildFailure == nil)
            check(cosmetics.renderedCount <= VoyageScenery.maximumObjects)
            check(cosmetics.root.children.count == cosmetics.renderedCount)
            check(scene.buildFailure == nil)
            check(scene.renderedCount <= UniverseScene.maximumPlanets + UniverseScene.maximumClusters)
            check(scene.root.children.count == scene.renderedCount, "Evicted meshes must leave the scene graph")
            maximum = max(maximum, scene.renderedCount)
            for child in scene.root.children {
                check(child.position.x.isFinite && child.position.y.isFinite && child.position.z.isFinite)
                check(simd_length(child.position) < 4100)
            }
        }
        check(!scene.root.children.contains { $0.name == "C–18" })
        for step in (0..<100).reversed() {
            world.advance(-SIMD3<Float>(640, step % 2 == 0 ? 320 : -320, -320))
            for _ in 0..<30 { scene.update(world, dt: 1 / 30); cosmetics.update(world, dt: 1 / 30, reduceMotion: false) }
            check(cosmetics.buildFailure == nil)
            check(cosmetics.renderedCount <= VoyageScenery.maximumObjects)
            check(cosmetics.root.children.count == cosmetics.renderedCount)
        }
        check(world.position == UniversePosition())
        for x: Int64 in -25...25 {
            let sector = SectorID(x: x, y: -x, z: x * 2)
            for kind in SceneryDefinition.Kind.allCases {
                check(SceneryDefinition.generate(sector, kind: kind) == SceneryDefinition.generate(sector, kind: kind))
            }
        }
        for name in ["nebula-veil", "ice-garden", "distant-ripple"] {
            check(cosmetics.root.children.contains { $0.name == name }, "Every new origin scenery must render")
        }
        let ice = cosmetics.root.children.first { $0.name == "ice-garden" }!
        let beforeIce = ice.children.first!.orientation
        let ripple = cosmetics.root.children.first { $0.name == "distant-ripple" }!
        let beforeRipple = ripple.children.first!.scale
        cosmetics.update(world, dt: 3, reduceMotion: false)
        check(ice.children.first!.orientation != beforeIce)
        check(ripple.children.first!.scale != beforeRipple)
        let frozenIce = ice.children.first!.orientation
        let frozenRipple = ripple.children.first!.scale
        cosmetics.update(world, dt: 3, reduceMotion: true)
        check(ice.children.first!.orientation == frozenIce)
        check(ripple.children.first!.scale == frozenRipple)
        let cameraAtCrystal = ice.position + ice.children.first!.position * ice.scale.x
        cosmetics.update(world, dt: 0, reduceMotion: true, cameraPosition: cameraAtCrystal)
        check(ice.children.first!.scale.x == 0, "A crystal at the camera must disappear")
        cosmetics.update(world, dt: 0, reduceMotion: true, cameraPosition: ripple.position)
        check(!ripple.isEnabled, "The distant wave must disappear before the camera reaches it")
        let dawn = try RestingDawn(seed: 18)
        check(dawn.available && dawn.root.children.count == 10)
        let glow = dawn.root.children.first as! ModelEntity
        func opacity(_ model: ModelEntity) -> Float {
            if case .transparent(let value) = (model.model!.materials[0] as! UnlitMaterial).blending { return value.scale }
            return 1
        }
        let beforeDawn = opacity(glow)
        dawn.update(dt: 30, reduceMotion: true)
        check(opacity(glow) == beforeDawn)
        dawn.update(dt: 30, reduceMotion: false)
        check(opacity(glow) != beforeDawn)
        let aurora = try RestingAurora(seed: 18)
        check(aurora.available && aurora.root.children.count == 2)
        let strip = aurora.root.children.first!
        let original = strip.transform
        aurora.update(dt: 5, reduceMotion: true)
        check(strip.transform == original, "Reduce Motion freezes aurora")
        aurora.update(dt: 5, reduceMotion: false)
        check(strip.transform != original, "Aurora must visibly drift")
        let duplicate = try RestingAurora(seed: 18)
        check(duplicate.root.children.first!.transform == original)
        cosmetics.update(world, dt: 1, reduceMotion: true)
        check(cosmetics.root.children.filter { $0.name == "dust-river" }.allSatisfy { !$0.isEnabled })
        print("PASS all five seeded scenery types, bounded cosmetic cache over 200 replacements, ice/ripple/aurora motion and Reduce Motion, horizon dawn")
        let activityScene = try ActivityScene()
        let rhythm = QuietActivity(world: .home, kind: .pattern)
        activityScene.update(rhythm, position: UniversePosition(), dt: 1, reduceMotion: false)
        check(activityScene.root.children.count == 3 && activityScene.root.children.allSatisfy { $0.isEnabled })
        let frozenLight = activityScene.root.children.first!.transform
        activityScene.update(rhythm, position: UniversePosition(), dt: 5, reduceMotion: true)
        check(activityScene.root.children.first!.transform == frozenLight)
        activityScene.update(QuietActivity(world: .home, kind: .signal), position: UniversePosition(), dt: 1, reduceMotion: false)
        check(activityScene.root.children.filter { $0.isEnabled }.count == 1)
        activityScene.update(nil, position: UniversePosition(), dt: 1, reduceMotion: false)
        check(!activityScene.root.isEnabled)
        print("PASS signal/pattern geometry, single activity visibility and Reduce Motion freeze")
        let leafScene = ConstellationScene()
        let encounter = QuietConstellation(world: .home)
        leafScene.update(encounter, position: UniversePosition(), forward: simd_normalize(encounter.relative(to: UniversePosition())), dt: 1)
        check(leafScene.root.children.count == 13 && leafScene.root.isEnabled)
        leafScene.update(nil, position: UniversePosition(), forward: [0,0,-1], dt: 10)
        check(!leafScene.root.isEnabled)
        for atmosphere in WorldAtmosphere.allCases {
            let atmosphereSky = try PolygonFactory.restingSky(seed: 18, starVisibility: atmosphere.starVisibility)
            check(atmosphereSky.children.count == 9)
        }
        print("PASS actual leaf lights and four atmosphere sky meshes")
        let sky = try PolygonFactory.restingSky(seed: 18)
        check(sky.children.count == StarColors.tints.count + 3, "Resting stars and fading orbital arcs must be batched into six color meshes and three trail meshes")
        let ship = try PolygonFactory.ship()
        let engines = ["thruster.left", "thruster.right"].compactMap { ship.findEntity(named: $0) as? ModelEntity }
        check(engines.count == 2)
        let drives = ShipThrusters()
        drives.attach(to: ship)
        let dark = (engines[0].model!.materials[0] as! UnlitMaterial).color.tint.greenComponent
        drives.apply(1)
        let bright = (engines[0].model!.materials[0] as! UnlitMaterial).color.tint.greenComponent
        check(bright > dark + 0.5, "Drive brightness must reach the actual engine material")
        drives.apply(0)
        check((engines[0].model!.materials[0] as! UnlitMaterial).color.tint.greenComponent < 0.03)
        let skyBounds = sky.visualBounds(relativeTo: sky)
        check(skyBounds.extents.min() > 600 && skyBounds.extents.max() < 702,
              "Resting stars must form a distant surrounding sky")
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
        print("PASS actual meshes, all palettes/terrain, batched resting sky, 200 streamed replacements and return")
        print("PASS bounded RealityKit cache: initial \(firstCount), peak \(maximum), limit \(UniverseScene.maximumPlanets + UniverseScene.maximumClusters)")
    }
}
'''
with tempfile.TemporaryDirectory(prefix='nemuru-render-check-') as temporary:
    path = Path(temporary)
    source = path / 'Checks.swift'
    source.write_text(universe + '\n' + sky_motion + '\n' + star_colors + '\n' + geometry + '\n' + thrusters + '\n' + renderer + '\n' + cosmetics + '\n' + checks)
    executable = path / 'checks'
    subprocess.run(['xcrun', '--sdk', 'macosx', 'swiftc', '-O', '-parse-as-library',
                    '-default-isolation', 'MainActor', '-module-cache-path', str(path / 'modules'),
                    str(source), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
