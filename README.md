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

Cruise/maximum speed is now **16** scene units per second (reduced from 24); the held-touch slow speed remains **2**. Input gain is 14 (previously 22), yaw/pitch scale is 0.7 (previously 0.8), and steering decay is 6 while holding / 4 after release (previously 5 / 2.5). Small drags therefore turn less, and rotation settles sooner. Planet braking uses 4.8 scene units/s² in its speed envelope to accommodate the higher cruise speed while preserving proximity holds and swept collision protection. Audio, particles, haptic normalization and save validation share the new maximum through `FlightTuning`.

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
- `UniverseScene`: at most 24 planet (12 near + 12 distant) and 16 cluster mesh groups, a 4,000-unit planetary horizon, gentle emergence, and at most one mesh-group build per frame.
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

The PoC and stage-5 streaming foundation are complete. Sparse star clusters are implemented; galaxies and star bands remain design candidates; procedural nebula veils are implemented. Terrain varies by world using one landing-site recipe. Music, export/cloud sync, and App Store distribution assets are not included. Stage 6's journal, persistence, background audio/lifecycle and accessibility implementation is present, with device validation documented separately.

Audio lifecycle follows Apple's [background playback guidance](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playback) and [route-change guidance](https://developer.apple.com/documentation/avfaudio/responding-to-audio-route-changes).

## Quiet scenery — 2026-10-26

The registered app icon is the 1024px opaque low-poly spacecraft artwork in `AppIcon.appiconset`.

Three procedural scenery additions use independent seeds without changing planet/cluster definitions, collision, voyage coordinates or the save format:

- **Dust rivers**: winding, sparse fields of 540 small tetrahedra, batched into three shades. Present in about 32% of sectors, plus the origin. Translation through them produces parallax; no per-particle animation is needed.
- **Lonely comets**: a small pale core with two intersecting tapered, fading tail sheets. About 12% of sectors, plus the origin. A slow bounded drift is cosmetic; its animation phase restarts on app relaunch and is not a recorded orbital simulation.
- **Resting aurora**: two continuous translucent, faceted curtains on about 42% of worlds, including C–18. Ten vertical fade layers per curtain soften the edges; only whole-curtain transforms animate. Colors are seeded muted mint or violet. The star sky continues its existing rotation independently.

`VoyageScenery` keeps at most six dust fields, three comets, two nebula veils, two ice gardens and one distant ripple (14 objects total), refreshes selection every half second or sector change, builds at most one scenery object per frame, and removes evicted entities. Existing planet/cluster construction retains its own one-build budget. Cosmetic geometry is not added to the voyage log and does not require interaction. System Reduce Motion hides dust rivers and freezes comet/aurora drift; background rendering pauses with the existing display link. No extra sounds or haptics were added.

Debug `--preview-scenery` starts a disposable origin voyage without reading/writing the real voyage store. `--preview-landing` shows C–18's aurora through the normal landing transition. Neither flag changes Release behavior.

Validation includes actual RealityKit meshes, 200 sector replacements and return with cosmetic cache/scene-graph bounds, deterministic regeneration, aurora movement and Reduce Motion freeze, and the existing flight/save/audio model checks. Simulator images are a visual check; sustained device frame rate, battery and thermal behavior still need real use.

## Further quiet scenery — 2026-10-26

- **Nebula veils**: five overlapping faceted, translucent clouds in a seeded teal/violet/rose family, with eight outward fade bands. A roughly 15% sector chance; at most two fields. Stars remain visible through them and there is no full-screen fog filter.
- **Ice gardens**: 12 small faceted translucent crystals per field. Roughly 18% sector chance; at most two fields. Each crystal turns at a gentle seeded rate. They have no collision; crystals shrink smoothly between 32 and 12 units from the camera and vanish at close range.
- **Distant light ripples**: two staggered elliptical waves with 96-second expansion/fade cycles, smooth zero-brightness endpoints and five soft edge bands. Roughly 5.5% sector chance; at most one field. They disappear between 320 and 180 units from the camera to remain a distant phenomenon.
- **Resting dawn**: a softly fading, warm horizon glow on C–18 and roughly 32% of generated worlds. Its brightness varies slowly over about four minutes and stays subtle behind the terrain. This is a cosmetic horizon light, not a simulated day/night clock or terrain light source.

All new fields have deterministic independent seeds and origin examples in separate directions. The original dust/comet seed salts, planet/cluster generation and save format remain unchanged. Geometry is constructed once when cached; no per-frame procedural mesh rebuilds. Ripple material updates are limited to about 10 Hz, dawn to 2 Hz. System Reduce Motion freezes crystal rotation, light-wave expansion/fading and dawn breathing as well as the existing animations. The nebula itself is static.

Debug `--preview-nebula`, `--preview-ice` and `--preview-ripple` each start a disposable slow voyage facing the origin example. `--preview-landing` includes the horizon dawn and aurora. These previews do not read/write the real voyage store and are ignored in Release.

Actual RealityKit checks now include all five flight-scenery types over 200 sector changes and return, deterministic regeneration, crystal/wave animation and Reduce Motion freeze, camera proximity disappearance, and dawn material freeze/change. Simulator Debug/Release and iPhone Debug builds pass; installation on the physical device remains deferred at the user's request.

## Distant planetary horizon — 2026-10-26

Planet visibility expands from the old 900–1,100-unit emergence band to a 3,200–4,000-unit band (4 ly at the game scale). The camera far plane is 5,000. Planet meshes are capped at 24 instead of 32: 12 nearby gameplay planets and 12 stable distant selections spread across the sky. The distant budget initially favors bodies around 2,800 units away, rather than filling every slot with the next-nearest bodies. All distant bodies use their real seeded positions, radii, names and palettes; they are not decorative copies or enlarged markers.

The horizon scans a bounded ±7-sector cube only when the gameplay sector changes, skipping sector centers beyond 4,300 units. It uses `Universe.generate` independently; the gameplay/collision/discovery neighborhood remains exactly 125 sectors. Distant selection persists while approaching and hands over to the nearby budget without replacing its entity. Newly loaded planet groups grow in over 1.5 seconds; far groups shrink smoothly near the outer horizon. Cluster visibility is unchanged. The total planet/cluster object budget falls from 48 to 40.

Renderer checks verify visible planets beyond 2,400 units, unchanged gameplay-sector bounds, identity-preserving distant-to-near approach, and 200 sector replacements and return (observed peak 36 groups, configured limit 40). Existing flight/save/audio checks and simulator Debug/Release/iPhone builds pass. Debug `--preview-horizon` starts a disposable voyage and turns once toward a loaded distant planet; it never reads or writes the real voyage archive. Physical installation remains deferred.

## A leaf of light, places and return courses — 2026-10-26

The first quiet observation loop is implemented: **find a leaf of light → follow its place → name/keep the world → return later**.

- One nearby constellation encounter is active at a time: C–18 and roughly one in five seeded worlds can host it. Seven pale lights settle into a leaf as the ship faces them; six dim connecting edges appear as alignment improves. A nearby hint is optional guidance, not a quest panel.
- Facing the pattern within about 5.5 degrees accumulates three seconds of observation. Looking away or opening a sheet pauses progress without a penalty or countdown. It only advances during active foreground flight. Unfinished focus is session-local and is discarded after leaving the encounter range; completed discovery is saved once per world.
- Discovery records the world and its leaf in the journal, then sets a manual course to its actual center. A quiet name/distance/bearing panel and corner marks identify the destination. There is no auto-steering, teleportation, score, failure state or new reward sound. The course can be dismissed at any time.
- The journal offers a world detail page with its atmosphere, discovery/visit details and coordinates. Give it a personal name (up to 40 characters) and toggle **Keep this place**. The original chart name remains visible. Kept places appear near the top; the paginated full history searches both names and adds a Kept filter while preserving its initial browsing order.
- After landing, **Name or keep this place** opens the same detail. **Set course to this place** provides the way back on a later voyage. Personal names, kept places, completed leaves and the chosen course persist through relaunch. The initial leaf observation is now joined by signal finding and repeating-light patterns (see below).

The save format remains version 1 with optional `nickname`, `favorite`, `constellationFoundAt` fields on world records and optional `destination` on the voyage archive. Legacy archives lacking them decode successfully. Existing world IDs/positions, collision and movement are unchanged. Names are trimmed, restricted to 40 characters and stripped of newline/ASCII control characters; empty names restore the chart name.

## Planet atmospheres — 2026-10-26

Landing sky is seeded independently per world: subdued blue, amber, pale gray haze or airless black. The same world keeps the same sky on return. Background color changes under the existing black landing/launch midpoint; ordinary flight returns to the original dark space background.

Atmospheric worlds use transparent pale stars rather than darkened opaque points, and hide the long star trails so they do not become black marks against brighter skies. Airless worlds keep the existing fully visible star sky and orbital arcs. Aurora and dawn are hidden on airless worlds; their original seeded availability applies to atmospheric worlds. Terrain colors and planet placement are unchanged. These are artistic atmosphere types, not physical weather or day/night simulation.

Debug `--preview-discovery` starts a disposable origin voyage aligned with the leaf. `--preview-sky-0` through `--preview-sky-3` land on actual nearby worlds with blue/amber/haze/airless atmospheres respectively. All preview flags bypass the real save store and are ignored in Release.

Validation: actual FlightSession leaf completion/course/save/relaunch; pause/look-away behavior; names/kept worlds/course round trips; old optional-field-free archives; deterministic coverage of all four sky types; actual leaf meshes and atmosphere sky batches; existing flight/save/audio and 200-sector renderer checks. Native simulator UI confirmed discovering C–18, saving the test name Leaf Haven and adding it to Places to return to. Simulator Debug/Release and iPhone Debug builds pass. Physical installation and sustained-device evaluation remain deferred at the user's request.

## Remaining observation activities — 2026-10-26

The proposed observation families are now implemented: a leaf constellation, finding a signal source, reading a light sequence, and returning to named/kept places using the existing manual course guide. One observation is active at a time. C–18 retains its leaf; other worlds use stable seed groups for leaf/signal/pattern eligibility. Completed activities are not offered again on that world. After a discovery there are 20 foreground seconds of quiet before another observation is selected.

**Signal source:** turn and drift toward a pale source. A generated 256/384-Hz tone becomes stronger with alignment and proximity, with gently smoothed stereo panning toward the source. Screen text offers Faint/Nearer/Clear, so sound is optional. Four accumulated seconds of clear observation record the source and set its world's course. Looking away or opening a sheet does not punish accumulated focus. The tone follows the existing Distant signals volume (zero mutes it), pause/interruption and foreground policies. The two-second PCM loop is generated once, not loaded from a sample file; no audio data is allocated in a render callback.

**Repeating lights:** face three small shapes and read five displayed symbols. Choose the sixth from Circle/Triangle/Diamond. Seeded repeating units include two-symbol alternation, a three-symbol cycle and a repeated-pair motif, with rotated symbol assignments. The world lights slowly emphasize the same repeating unit; the static sequence remains available with Reduce Motion. A different answer keeps the same problem and offers a gentle retry sentence. There is no countdown, score, life loss or time penalty. Correct observation records the world and sets a course.

Both results appear in world details and journal rows and use the existing name/keep/return flow. Optional `signalFoundAt` and `patternFoundAt` record first discovery dates; old archives without them still load. Planet generation, movement, collision and the save version are unchanged. Unfinished observation state is session-local; leaving its 1,200-unit encounter range lets it go. Background/menu/rest states do not complete activities.

Debug `--preview-signal` and `--preview-pattern` use actual nearby generated worlds in a disposable slow voyage, aligned with the relevant source. They never read/write the real voyage store and are ignored in Release.

Validation includes direction/pause signal checks, all seeded pattern rules, wrong-choice and menu guards, actual FlightSession completion/course/save/relaunch for both kinds, first-discovery timestamps, old-save compatibility, the generated loop's finite/quiet/continuous waveform, and RealityKit shape/visibility/Reduce Motion checks. Native Device Hub UI confirmed a different answer retains the sequence and a correct answer creates L–167's course. Debug/Release simulator and signed iPhone builds pass. Physical installation remains deferred; real-device directional hearing/comfort and ordinary-control encounter difficulty still need user play feedback.

## Cruise speed adjustment — 2026-10-26

Maximum/cruise speed is 16, held-touch slow speed remains 2. Steering and braking tuning are unchanged. Historical version-1 saves with velocity/approach speed up to 24 still validate and restore their voyage; both speeds clamp to 16 on restoration. Audio, particles and thrusters use the shared current cruise speed.

## Held-touch full stop — 2026-10-26

Holding now brakes to exactly zero; once the exponential easing reaches 0.02 units/s it settles to zero rather than drifting asymptotically. Continued holding preserves position and dragging can turn in place. Release eases back to the 16-unit cruise speed. The HUD shows HOLDING POSITION / HOLD and a release hint at a manual stop. The 2-unit launch kickoff remains part of the departure transition, not the held-touch minimum. Checks verify exact stop, stationary holding/turning and release acceleration.
