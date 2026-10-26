# STARSHIP NEMURU — procedural voyage

A portrait, one-handed, third-person quiet space voyage. All geometry and sound are generated in code; no external models, textures, or audio files are needed.

Current status (2026-10-26): the latest implementation includes Galactic XYZ coordinates, persistent visited-world locations with old-journal backfilling, near-planet holding without auto-steering, and a slowly moving resting star sky. The latest Debug build is installed on the iPhone SE (3rd generation). The Korean [development status and handoff](../../docs/10.%20Projects/STARSHIP%20NEMURU/개발현황.md) records scope, decisions and remaining device checks.

## Run

Open `STARSHIP NEMURU.xcodeproj` in Xcode and run the `STARSHIP NEMURU` scheme on an iPhone or iPhone simulator. The deployment target is iOS 17.6. Physical-device signing uses the development team already configured in the project.

- Hold anywhere in the flight space to gradually slow down.
- Drag to rotate toward the drag direction. Stop dragging while still holding to let rotation settle while staying slow.
- Release to ease back to cruising speed. A nearby planet ahead slows the ship to a hold; turn away or land to continue.
- On supported iPhones, holding to brake produces a soft continuous haptic texture. It eases in, becomes fainter as speed settles, and fades out on release. Opening a sheet, landing, or leaving the foreground stops it.
- Face a planet within landing range and tap **Land somewhere quiet**. Approach slows automatically, fades into a short descent, and settles into the landscape. Tap **Return to the stars** to lift off and resume the voyage.
- Controls and instructions stay at a constant opacity, including after inactivity. There is no app sleep/dim/wake mode. Flight gestures are ignored during rest and transitions.
- The book button opens the quiet voyage log: worlds found/visited, distance in light years (`ly`), longest stay, and the three latest discoveries. Visited worlds also offer expandable Galactic coordinates. **View all worlds** opens a searchable history with All/Visited filters and 40 more records per request, ordered by newest discovery. Distance uses a game scale of 1,000 scene units per light year; stored raw distance is unchanged, so existing voyages use the same scale.
- Three top buttons open the **Voyage log**, toggle **Galactic coordinates**, and open **Voyage settings**, respectively. Settings includes saved layer volumes, sound Pause/Resume, and **Keep sound when locked**. Set a layer to zero to silence it.
- Voyage position, facing, landing/rest/departure state, journal, and settings restore on relaunch. There are no progress popups or rewards.

The playback audio session plays even with the silent switch enabled and owns playback for system media controls; starting Nemuru audio may pause another media app. With **Keep sound when locked** enabled, intended audio and low-frequency background travel continue while the engine is running. Headphone disconnection pauses playback until explicitly resumed. Now Playing Play/Pause handlers are registered, but the controls did not appear in the simulator and still require physical-device verification. Force-quitting the app ends playback and travel. Use a comfortable device volume.

## Galactic coordinates

Tap the top **Galactic coordinates** arrow button to show or hide the panel. Its filled icon and accessibility value indicate the current state. The three signed **X / Y / Z** components are distances in light years from C–18's center, using the game's fixed Cartesian axes. These are fictional chart coordinates, not the ship's heading or a real galaxy's coordinate catalogue. Each 1,000 scene units equals one light year. The toggle is available in Debug and Release and remembers its choice in local preferences (`showVoyagePosition`, retained from the earlier UI).

The panel refreshes about 10 times per second and passes touches through to flight. During a landscape stay it displays that world's recorded center, matching the journal; during flight it displays the ship's position. World records store normalized planet-center positions. Existing records without this optional field are backfilled from their sector's deterministic generation. Expand **Galactic coordinates** under a visited world in the recent list or full history to read it. Voyage save version and generation version remain unchanged; the new field is optional for old-save compatibility.

## Flight tuning — 2026-10-26

Cruise/maximum speed is **24**, doubled from 12 scene units per second; the held-touch slow speed remains **2**. Input gain is 14 (previously 22), yaw/pitch scale is 0.7 (previously 0.8), and steering decay is 6 while holding / 4 after release (previously 5 / 2.5). Small drags therefore turn less, and rotation settles sooner. Planet braking uses 4.8 scene units/s² in its speed envelope to accommodate the higher cruise speed while preserving proximity holds and swept collision protection. Audio, particles, haptic normalization and save validation share the new maximum through `FlightTuning`.

The app-specific **Gentler motion** preference and setting were removed. A legacy saved `gentleMotion` key is ignored when loading; other voyage settings and records are retained. iOS system Reduce Motion is still respected automatically.

## Planet approach and resting sky

Approaching a planet ahead now slows the ship to a stable **HOLDING POSITION** near it, without automatic steering. Turn away to accelerate again, or choose to land. Swept collision protection remains in place. The stop is recomputed from the saved position, heading and speed after relaunch, without inventing offline travel.

The resting scene contains terrain and 1,440 seeded stars, plus short fading orbital arcs behind one in six stars. Points and arcs are batched into nine meshes (six star-color groups and three fading neutral trail groups). The shared rotation axis places the celestial pole in the upper landscape sky, so the circular paths are legible. Rotation is 0.01 radians per rendered second; there is no zoom or flashing. System Reduce Motion freezes the sky without snapping it. A restored landscape seeds its initial phase from accumulated running stay time. Flight stars are hidden while the landscape is visible.

The initial 0.0035 rad/s pass was reported as appearing stationary. Physical-device tracing confirmed 15 Hz updates, advancing applied rotation and Reduce Motion off. After increasing to 0.01 rad/s, the user confirmed visible star motion on the iPhone. Debug `--trace-resting-sky` logs frame time, requested/applied angle and Reduce Motion state every two rendered seconds while the landscape is visible. It uses the normal voyage save policy; it is not a disposable preview flag.

## Planet and star colors — 2026-10-26

Planets use ten muted families: tide, dusk, clay, frost, ochre, moss, rose, indigo, pearl and ember. A separate seed stream varies RGB tint and brightness within each family, using the same resulting low/high colors for the orbital planet and its terrain. Planet color components are capped at 0.72. The palette selection still consumes exactly one draw in the existing world generator; location, size, roughness, name and cluster placement are unchanged. A before/after comparison of 2,023 sectors confirmed these non-color fields are identical. Existing generated planets can change color family after this update; their identity, saved position and journal stay intact. Generation/save versions remain unchanged because the layout is preserved.

Flight stars and resting stars use six fixed tints: amber, pale gold, warm white, mint white, ice blue and lavender. Warm white is most common, with fewer colored accents. Star colors use independent seeded streams, so color selection does not move stars or animate their hue. Clusters use a seeded warm/cool/mint trio while retaining three mesh groups per cluster. The resting sky adds six star-color groups to its three existing neutral trail groups, keeping a fixed nine-group budget. No additional stars, new world objects, flashing or textures are introduced.

## Thruster brightness

The two rear drive panels brighten smoothly during acceleration, settle to a steady cruise glow, dim during braking, and become dark at a full stop or landscape rest. Launch ignites them before liftoff. `ThrusterResponse` uses speed, acceleration, braking and phase, rather than a repeating flash. `ShipThrusters` applies a bounded unlit mint-colored material to the named left/right engine panels only; it does not add dynamic scene lights, flame particles or audio. Brightness fades down faster than it rises and material updates are skipped when the change is negligible.


## Implementation

- `StudioLaunchView`: a brief studio credit on the voyage's dark background, sparse static stars, the supplied pixel wordmark with reduced saturation, and a soft transition into the voyage. It appears on a fresh launch, not every foreground return. The original branding PNG is retained in `StudioLogo`; the system launch screen uses `LaunchBackground`. Debug `--preview-splash` holds the artwork without creating a flight session or accessing its save.
- `FlightSession`: flight/landing lifecycle, saved-state restoration, discovery/rest/distance accounting, low-frequency background voyage, and debounced/periodic persistence.
- `VoyageStore`: validated, versioned Codable state on a utility serial queue; atomic primary writes, one previous-save backup, recovery, and preservation of unreadable/future saves. Files live in Application Support/Nemuru. iOS protection permits access after first unlock.
- `VoyageLog`: unique sector-based world records with first discovery, first/last landing, visit count, resting duration, and total distance. Only logged running time is accumulated; closed-app time is not invented.
- `RestingSkyMotion`: slow seeded sky orientation, elapsed-time motion and a Reduce Motion freeze.
- `SpaceView`: non-AR RealityKit scene, third-person camera, recycled near/far star layers with gentle parallax, and planet-specific resting landscapes.
- `BrakingHaptics`: haptics-only Core Haptics continuous player with low sharpness, speed-dependent strength and a smoothed envelope; unsupported hardware silently skips feedback.
- `Universe`: deterministic 640-unit sectors, a 5×5×5 active neighborhood, integral sector coordinates and bounded Double local offsets. Sector definitions are evicted and regenerated from stable coordinate seeds.
- `UniverseScene`: at most 32 planet and 16 cluster mesh groups, distance-based loading/unloading, gentle distant emergence, and at most one mesh-group build per frame.
- `PolygonFactory`: faceted ship, planets with ten muted color families and seeded per-world tint variations and varying radii/topology/roughness, per-world seeded terrain, and sparse star clusters batched into three meshes each.
- `VoyageAudio`: three independent real-time audio source nodes, a slowly changing engine pitch, and a generated soft touchdown buffer. Filtered seeded noise, low oscillators, and soft signal envelopes; no sample loading or allocation in the per-sample loop.

## Validation

Build on the simulator:

```sh
xcodebuild -project 'STARSHIP NEMURU.xcodeproj' -scheme 'STARSHIP NEMURU' \
  -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/nemuru-stage6-build CODE_SIGNING_ALLOWED=NO build
```

Run the flight and waveform checks on a Mac with Xcode selected:

```sh
python3 scripts/check-poc.py
python3 scripts/check-universe-renderer.py
```

The script compiles the actual flight state and synthesis code with a stub for device audio I/O. It checks hold/release behavior, steering direction and settling, 30/60 fps consistency, two minutes of collision-free idle flight, landing and departure, hidden midpoint camera changes, gradual approach deceleration, one touchdown event per landing, resting controls remaining available after inactivity, transition pause/resume, and approximately 53 seconds per synthesized voice for finite, non-silent samples below clipping. It does not verify device speaker output or perceived comfort.

For repeatable Debug visual/audio QA, add `--preview-landing` to the scheme launch arguments (or pass it to `simctl launch`). This starts a normal landing transition near the current planet. Add `--preview-universe` to start near a different generated world; combine both flags to preview its landing site. Preview runs use an in-memory voyage and never read or replace the real save. `--preview-log` supplies 121 sample worlds to check long-list browsing, filtering and pagination; `--preview-settings` opens settings. These flags are ignored in Release builds. Remove them for a normal voyage.

## Stage 5 validation

- Reproducible content, all ten color families, size variation, negative-coordinate boundaries, and local precision at sector coordinates of ±10¹².
- 1,000-sector outward travel and return: exactly 125 active sector definitions, distant sectors evicted, identical original content regenerated.
- The current one-hour simulated flight at 0.05-second updates includes scripted pilot turns after proximity stops: 167 sector boundary crossings, bounded local offsets and no entry into any planet's safety margin. This is accelerated model testing, not an hour-long device soak.
- A swept collision check also prevents a large displacement from tunneling through a planet.
- Landing/rest/departure on a generated world preserves its identity and resumes flight facing away from that world.
- The actual RealityKit mesh/cache test traverses 200 sector replacements and returns home. It validates all planet palettes and terrain, removes evicted nodes from the scene graph, and verifies mesh-cache bounds. The observed cache was initially 20 groups, peaked at 32, and stayed below the configured 48-group limit. The macOS harness substitutes NSColor for UIColor; the mesh and cache code are otherwise unchanged. It may need to run outside a restricted sandbox for RealityKit to initialize.
- iOS simulator Debug and Release builds, plus visual checks of generated-world landing and departure.

Sector metadata and scene-node counts are bounded by construction. These checks do not establish a device RAM plateau or battery/thermal performance; prolonged physical-device profiling remains part of the product finishing stage.

## Stage 6 validation and remaining device checks

The expanded `check-poc.py` passes real file round trips, landed/in-transition restoration, journal de-duplication and durations, volume/background/motion preferences, corrupt-primary recovery, unsupported-future-file preservation, background pause/resume/opt-out/all-muted logic, and low-frequency damping. The audio device is stubbed in model tests; actual synthesis waveform checks remain included. The simulator app has generated both current/previous saves with live journal progress, and the built Info.plist declares background audio.

Save snapshots occur every 30 simulated seconds, on lifecycle and transition events, and shortly after settings changes. A force kill may lose activity since the most recent snapshot. A closed app does not accumulate distance or resting time. If a process is suspended during an interruption, missed wall-clock time is not simulated as a large jump when it wakes.

Low Power Mode, idle/resting states, thermal pressure, system Reduce Motion, Dynamic Type labels, and named VoiceOver flight actions are handled. The view display link pauses while the scene is backgrounded. Audio transition smoothing uses elapsed time at both foreground and background tick rates.

See [DEVICE_VALIDATION.md](DEVICE_VALIDATION.md) for the reproducible physical-device functional, accessibility, memory, thermal, and battery pass. The log/settings sheets were visually checked and opened/closed through native UI automation, including Pause/Resume sound. The former Gentler motion option has since been removed. A real simulator Release save survived termination, reinstallation, and relaunch with its journal and preferences. During a simulator screen lock, successive saved snapshots advanced by 30 seconds and 360 raw distance units (0.360 ly under the current display scale) with the real audio engine running. Lock-screen Now Playing controls did not appear in this simulator and remain unverified, as do physical headphone/interruption behavior, VoiceOver, and sustained battery/thermal/RAM measurements. Simulator results are not proof of physical-device performance.

## Latest delivery — 2026-10-26

The latest visual pass makes the resting sky orbit more apparent with a visible pole and fading arcs, and links engine brightness to propulsion/braking/stop/launch. Model checks cover the visual throttle and smoothing, while RealityKit checks verify the actual engine material response and six-mesh sky budget.

Automatic HUD dimming was removed at the user's request. The idle-opacity state and both HUD/coordinate-panel opacity bindings were deleted; buttons and instructions remain visible at their normal opacity. Idle display-link throttling remains a resource optimization and does not disable input. The separate launch/landing/departure transitions remain.

The latest tuning pass adds three separate top buttons, removes the app-specific motion option, doubles cruise speed and refines steering. Checks cover 24-unit cruise serialization, small-drag turning and release settling. Native simulator UI checks toggled the standalone coordinate button and opened settings without the removed option.

The current model suite, actual RealityKit sky/cache suite, simulator Debug/Release builds and iPhone Debug build passed. Native simulator UI checks opened a visited world's coordinates, inspected the new landscape, and observed a generated-world approach reaching **HOLDING POSITION / 00 HOLD** with landing still available. The latest build was installed and launched on the iPhone SE (3rd generation). Physical-device feel, long-duration use, audio-route/lock-screen behavior, and accessibility still require the device pass.

## Studio splash delivery — 2026-10-21

The final studio-splash version passed simulator Debug/Release and physical-device Debug builds, and was installed and launched on the connected iPhone SE (3rd generation). The user accepted the studio splash design. The supplied logo PNG is preserved byte for byte; only its on-screen saturation and opacity change. The ordinary intro lasts about 2.2 seconds and was observed to reach the flight UI in the simulator. Splash interruption/lock/resume and Reduce Motion still need a physical-device pass. The original gameplay rendering and audio remain procedural; the studio wordmark is a supplied branding image.

## Current boundaries

The PoC and stage-5 streaming foundation are complete. Sparse star clusters are implemented; galaxies, nebulae and star bands remain design candidates. Terrain varies by world using one landing-site recipe. Music, export/cloud sync, and App Store distribution assets are not included. Stage 6's journal, persistence, background audio/lifecycle and accessibility implementation is present, with device validation documented separately.

Audio lifecycle follows Apple's [background playback guidance](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playback) and [route-change guidance](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes).
