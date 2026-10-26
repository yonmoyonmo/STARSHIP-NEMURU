# Device validation

Status as of 2026-10-26: Galactic XYZ coordinates, visited-world positions, near-planet holds and a moving resting sky are implemented. The latest Debug build has been installed and launched on the iPhone SE (3rd generation). Remaining physical-device tests below are not marked complete.

Use an iPhone with a Release build. Record the iPhone model, iOS version, app build, battery health, room temperature, brightness, audio route, and system volume before comparing runs. The iOS simulator verifies behavior but is not a battery, thermal, or radio-route measurement.

## Completed automated checks

- Journal discovery de-duplication, visits, distance, and resting duration.
- Save/load of position, heading, volume preferences, motion/background preferences, landed state, and an in-progress landing.
- No extra visit or invented stay duration from time spent with the process closed.
- Serial atomic writes, previous-save recovery, invalid-state rejection, and preservation of unsupported future saves.
- Background model advances only when background sound is enabled and the audio engine is running. Pausing, opting out, or muting all layers stops background simulation.
- 15/30/60 Hz flight damping consistency and existing one-hour simulated all-body collision/sector-budget checks.
- iOS simulator build contains `UIBackgroundModes = [audio]`.

These model tests use a stub for device audio I/O; they do not establish physical lock-screen, interruption, speaker, or Bluetooth behavior.

## Completed simulator checks

- iPhone 18 Pro / iOS 27: log and settings layout, open/close, Pause/Resume sound, and the then-existing Gentler motion toggle (removed in the latest tuning pass).
- Release save persists across termination, app reinstallation, and normal relaunch, retaining journal and preferences.
- Screen-lock background execution with the real audio engine: consecutive saves advanced by 30 seconds and about 360 raw distance units (0.360 ly under the current display scale).
- Now Playing controls did not appear on this simulator lock screen. Their registration is implemented, but visible controls and remote commands still need physical-device verification.
- Journal update (2026-10-21): a Debug preview with 121 worlds shows a three-world summary, light-year distance and a separate full history. Native UI checks reached the first 40-record footer, loaded more records, and confirmed that typing `C18` finds names displayed with an en dash. The simulator and physical-device Debug builds passed. All/Visited filtering and larger Dynamic Type still need a manual interaction pass.

- Studio splash (2026-10-21): the original logo asset is unchanged; the final artwork was visually inspected and captured. A normal simulator launch reached the flight UI after the intro. The built Info.plist contains the named launch background. The final simulator Debug/Release and physical-device Debug builds passed; the latter was installed and launched. The user accepted the splash design.

## Galactic coordinates and world update — 2026-10-26

The user chose fixed Cartesian **Galactic coordinates: X / Y / Z** in light years, relative to C–18. Model checks cover axis signs across sector boundaries and far coordinates, visited-planet center serialization, legacy JSON with the new location field absent, and backfilling centers without changing journal counts or distance. The landing position display matches the recorded planet center.

Approach checks now cover a full stable stop, no unsolicited heading change, pilot turning to leave, and restoration of a stopped voyage. The one-hour traversal uses scripted pilot turns when stopped and crossed 167 sector boundaries after the 24-unit speed update. It is not an unattended auto-avoidance test. Existing collision safeguards, landing/departure, saves, background and waveform checks also pass.

Resting sky checks cover slow rotation, no motion with system Reduce Motion, phase initialization from saved stay time, and the actual batched RealityKit star mesh/cache limits. The simulator landscape was inspected without the duplicated planet; the journal coordinate disclosure was opened through native UI automation. A generated-world approach reached HOLDING POSITION / 00 HOLD with landing available. Final simulator Debug/Release and iPhone Debug builds passed, and the iPhone build was installed and launched.

Physical checks still required: approach and leave at different angles, stops with background sound enabled, landing and departure near another planet, visited coordinates after a real-device relaunch, readability of signed XYZ values, and visual continuity of the moving/frozen sky. Existing thermal/battery, headphone, lock-screen media controls and accessibility checks remain outstanding.

## Three buttons and flight tuning — 2026-10-26

The app-specific Gentler motion setting and saved preference were removed; system Reduce Motion remains automatic. Old JSON containing `gentleMotion: true` is accepted and the unknown setting is ignored. The top row now has standalone log, coordinate toggle and settings buttons. Native simulator interaction verified the coordinate button's Hidden/Shown state and settings without the removed option. Model checks pass for cruise speed 24, serialization at that speed, precise five-point drags, release settling and the existing full collision/hold/landing/save suite. Debug simulator, Release simulator and iPhone Debug builds passed.

Physical-device assessment of the new steering feel and higher-speed approach is still required. The lower small-drag sensitivity and shorter steering tail are intentional; no user-configurable sensitivity setting was added.

## Automatic HUD dimming removed — 2026-10-26

Idle-dependent HUD opacity and the coordinate panel's dimming binding were removed. Controls retain their normal opacity after inactivity. The model check now verifies that resting controls remain available after a long stay rather than testing fade/wake behavior. Idle frame-rate throttling still does not disable input. Verify all three buttons, landing/departure controls and steering after at least 30 seconds untouched. The simulator was left untouched, its normal HUD opacity was visually confirmed, and the settings button opened the sheet on the first click without a wake-up touch. Model checks and simulator Debug/Release plus iPhone Debug builds passed. The fix was installed and launched on the iPhone SE (3rd generation). OS auto-lock and the separate scene-transition fades are unchanged.

## Orbital sky and drive panels — 2026-10-26

The sky now rotates about a pole visible in the upper landscape at 0.01 rad/s. A sparse subset of stars has short fading arcs; the sky remains bounded to nine meshes after the color expansion (six point-color groups, three neutral trail groups). Model checks verify visual drive levels for acceleration, cruise, braking, stop/rest, launch-before-liftoff and 30/60 Hz smoothing. Actual RealityKit checks attach the driver to both named engine panels, verify bright and dark material colors, and check the sky geometry budget.

Simulator visual checks confirmed the resting sky arcs, dark drive panels while resting, and lit panels after launch/cruise. Final simulator Debug/Release and iPhone Debug builds passed, and the iPhone build was installed and launched.

Physical checks: watch the resting sky for at least one minute, verify circular motion rather than camera motion, enable system Reduce Motion and check it freezes without a jump, then compare drive brightness while accelerating, holding to slow, auto-holding near a planet, resting and taking off. Check low device brightness for both readable quiet glow and sufficiently dark stopped panels. No dynamic light, flame particle or extra audio effect is added.

## Resting-sky perceptibility follow-up — 2026-10-26

The user reported no visible movement after the earlier visual pass. On the actual iPhone SE (3rd generation), a short Debug trace confirmed approximately 15 Hz landscape updates, changing requested/applied rotation, and both app/system Reduce Motion false. The simulator's actual before/after sky images also showed displaced star centroids. Increasing rotation from 0.0035 to 0.01 rad/s was then installed and launched normally, and the user confirmed that the stars visibly move. A five-second off-pole displacement assertion was added to the passing model suite. Debug `--trace-resting-sky` remains available for diagnostics and is excluded from Release; no new UI setting or save-schema change was introduced.

## Color variety — 2026-10-26

Ten planet families and independent seeded per-world tints are implemented. Model checks cover deterministic color regeneration, intra-family differences, bounded RGB values, all ten generated families and weighted coverage of all six star tints. Actual RealityKit checks build the ten planet/terrain families and the nine-mesh resting sky, and retain the existing planet/cluster cache bounds. A before/after run over 2,023 sectors matched all non-color generation fields (planet/cluster presence and centers, radius, roughness, name and seed). Existing save and journal checks pass.

Simulator review confirmed a newly generated ochre planet, matching terrain and mixed warm/cool stars. Final Debug/Release simulator and iPhone Debug builds passed; the iPhone build was installed and launched.

Manual review should include warm/cold planets and terrain, natural-looking colored stars, night-time device brightness and the absence of color flicker while stars recycle or the sky rotates. Colors are cosmetic; no new gameplay classification or astronomical claim is attached to them.

## Completed physical-device haptic check

2026-10-21: The revised haptic build was installed and launched on the connected iPhone SE (3rd generation). The user confirmed that braking vibration is now perceptible. Device logs recorded successful continuous-player starts without haptic errors during that check. Extended holds, loop seams, and the full lifecycle checklist below remain separate checks.

## Functional pass on the device

1. Fly, change all three volumes and both settings, land, and leave the app. Reopen it, then terminate/relaunch it. Verify the world, position, facing, resting state, settings, journal counts, and stay duration. Repeat from the middle of a landing and departure.
2. Open the log. Check found/visited counts, per-world discovery and visit dates, total distance, and longest stay. Returning to a known world must not create a duplicate entry. Reopening a resting voyage must not add another landing or the hours spent with the app closed.
3. Enable **Keep sound when locked**. Lock the iPhone for at least five minutes. Listen for continuity and check the live Now Playing title. Use Play and Pause from the lock screen, unlock, and verify progress in the log and a stable camera.
4. Disable background sound, then lock the phone. Both sound and background travel should stop. Repeat with all three volumes set to zero.
5. With wired or Bluetooth headphones, disconnect the route while locked. Playback must pause without unexpectedly moving to the speaker, and must stay paused until explicitly resumed. Reconnect and resume. Repeat with an interruption from a call or another nonmixable audio app; resume only if the OS permits it.
6. Enable system Reduce Motion. Verify that banking, bobbing, and nearby particles are removed while steering remains usable. Check the log and settings with large Dynamic Type and VoiceOver. The flight space provides named turn, slow, and resume-drift accessibility actions.
7. On a haptics-capable iPhone, hold to brake for at least 15 seconds: feel a soft continuous vibration without repeated taps or loop seams, tapering as speed settles. Release and check a smooth fade. Repeat rapid press/release, steering while held, opening either sheet, landing, and locking/backgrounding: no stuck vibration. Resume after unlock or an interruption and check that feedback works on the next hold. Verify that voyage audio continues normally. Simulator builds compile this path but cannot establish its tactile strength or continuity.

8. Cold-launch the app and verify that the studio logo fades into the voyage, with audio starting as the voyage appears. Background/lock during the intro, return, and check that it finishes without getting stuck or replaying on later foreground returns. Repeat with Reduce Motion enabled. Intro visuals and ordinary transition were checked in the simulator; these lifecycle/accessibility cases still need physical-device verification.

## Resource pass

Use Xcode Instruments (Allocations/Leaks, Time Profiler, Energy Log where available) and Xcode's memory/energy diagnostics. Capture the same configuration for each run.

| Scenario | Duration | Observe |
|---|---:|---|
| Active turns and repeated landing/departure | 15 min | Frame pacing, allocation spikes, audio dropouts |
| Untouched foreground flight through many sectors | 60 min | Memory settles after warm-up; evicted scene nodes are not retained |
| Resting on one world | 30 min | Lower CPU update frequency, stable scene, no repeated touchdown sound |
| Locked background voyage | 60 min | No display-link scene updates; low-frequency model work and continuous intended audio |
| Background sound disabled | 15 min | No background voyage timer or active engine |

The app requests 60 Hz while interacting, 30 Hz during idle/Low Power Mode, 15 Hz on a resting landscape, and 20 Hz under serious/critical thermal pressure. These are simulation/display-link update limits; RealityKit's internal renderer and the OS decide actual rendering and scheduling. Background simulation ticks approximately once per second while audio runs. Save snapshots occur every 30 simulated seconds and on lifecycle/transition/settings changes.

Record battery percentage before/after, peak and settled app memory, CPU/energy observations, thermal-state changes, audio interruptions, and any dropped frames. Do not infer an acceptable battery budget or claim an absence of leaks from simulator/model tests alone. Use these measurements to set a device-specific baseline before making performance claims.

## Evidence still required

A sustained physical-device thermal/battery run, actual screen-lock/Now Playing controls, real headphone disconnects and interruptions, and manual VoiceOver/Dynamic Type checks. The host was unlocked and the new sheets passed native UI interaction and layout checks. Simulator lock-screen Now Playing controls remain unresolved; verify them on a physical device before treating that feature as accepted.

## Quiet scenery pass — 2026-10-26

- AppIcon: 1024×1024 opaque PNG registered and included in successful builds.
- Simulator Debug/Release and signed iPhone Debug builds passed with dust rivers, comets and resting aurora.
- Actual RealityKit checks passed: deterministic scenery, cache removal/bounds during 200 sector replacements and return, continuous aurora construction, animation and Reduce Motion freeze. Existing flight/save/audio model checks passed.
- Simulator visual inspection caught and corrected gaps between aurora strips and an opaque comet-tail edge. The final curtains are continuous and the tail fades through transparency.
- Physical installation was attempted but the device transport disconnected. The user explicitly deferred installation; no claim of device visual/performance validation is made for these additions.
- Pending on device: observe a dust crossing while cruising/braking, comet visibility during turns, slow aurora motion, background/foreground and Reduce Motion, and extended frame-rate/thermal/battery checks.

## Remaining scenery pass — 2026-10-26

Nebula veils, ice gardens, distant ripples and resting dawn were added with independent seeds. Simulator visual QA and Debug/Release builds, iPhone Debug compilation, existing model checks and the expanded RealityKit cache/animation/proximity tests passed. Physical installation remains deferred per user request.

On-device follow-up: check subtle nebula/dawn visibility at normal screen brightness; inspect ice rotation and close-range disappearance while steering; observe a complete 96-second wave cycle; confirm Reduce Motion/background freeze; profile extended flight frame rate, memory, battery and thermal load with the expanded 14-object cosmetic cache.

## Planet horizon pass — 2026-10-26

The planetary horizon now reaches 4,000 units, with 12 near + 12 distant planets and 16 clusters maximum. The gameplay neighborhood remains 125 sectors. Actual RealityKit checks confirm enabled distant bodies beyond 2,400 units, entity continuity during approach, and 200 streaming changes and return (peak 36 / limit 40). Existing flight/collision/landing/save checks pass. Physical installation remains deferred; verify long-distance planet readability and sustained performance on device later.

## First observation/place loop and atmosphere pass — 2026-10-26

Model checks cover three-second forgiving focus, no progress during paused/background observation, pause without loss when looking away, actual FlightSession completion and course creation, one-time discovery through save/relaunch, personal names and kept-place/course round trips, and legacy saves missing all added optional fields. Actual RealityKit checks include the leaf lights, four atmosphere sky batches and existing streaming bounds. Native Device Hub UI confirmed Leaf Haven naming and Keep this place registration in the disposable discovery preview.

Visual QA inspected blue/amber/haze/airless landscapes. Opaque dark star trails against bright skies were corrected: atmospheric star points blend transparently and atmospheric trails are hidden. Airless sky retains the original orbiting points/arcs and hides aurora/dawn.

Simulator Debug/Release and signed iPhone Debug builds pass. Physical installation remains deferred. Next device pass: discover a leaf with ordinary one-handed controls, leave it and resume, name and keep a visited world, relaunch and set a course back, inspect long names/Dynamic Type/VoiceOver and atmosphere brightness, verify landing/launch sky changes and prolonged performance.

## Signal and repeating-light pass — 2026-10-26

The remaining proposed observation families are implemented. Model checks cover directional/proximity signal focus, pause/look-away behavior, stable seeded repeating units and correct/different selections, menu guards, both actual FlightSession completion/course/save/relaunch paths, first-discovery timestamps and legacy optional-field compatibility. The generated low-level beacon loop is finite, bounded below 0.05 and continuous at its two-second boundary. Device audio I/O is still stubbed in model tests.

RealityKit checks cover the actual signal/pattern shapes, one-activity visibility, hidden state and Reduce Motion freeze. Native Device Hub UI retained the pattern after a different answer and created L–167's course after the correct answer. Simulator screenshots capture both activity families. Simulator Debug/Release and signed iPhone Debug builds passed; physical installation remains deferred.

Device follow-up: hear source direction/clarity with headphones and phone speakers, verify Distant signals zero/Pause/Resume/interruptions/lock behavior, locate and answer with ordinary one-handed controls, check small-screen/Dynamic Type layout, and evaluate whether the 20-second quiet interval and encounter density feel restful during a full session.
