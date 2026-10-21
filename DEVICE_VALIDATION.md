# Device validation

Status as of 2026-10-21: work has ended for the day, and the latest Debug build with the studio splash has been installed and launched on the iPhone SE (3rd generation). Further development awaits user feedback. Remaining tests below are not marked complete.

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

- iPhone 18 Pro / iOS 27: log and settings layout, open/close, Pause/Resume sound, and Gentler motion toggle.
- Release save persists across termination, app reinstallation, and normal relaunch, retaining journal and preferences.
- Screen-lock background execution with the real audio engine: consecutive saves advanced by 30 seconds and about 360 raw distance units (0.360 ly under the current display scale).
- Now Playing controls did not appear on this simulator lock screen. Their registration is implemented, but visible controls and remote commands still need physical-device verification.
- Journal update (2026-10-21): a Debug preview with 121 worlds shows a three-world summary, light-year distance and a separate full history. Native UI checks reached the first 40-record footer, loaded more records, and confirmed that typing `C18` finds names displayed with an en dash. The simulator and physical-device Debug builds passed. All/Visited filtering and larger Dynamic Type still need a manual interaction pass.

- Studio splash (2026-10-21): the original logo asset is unchanged; the final artwork was visually inspected and captured. A normal simulator launch reached the flight UI after the intro. The built Info.plist contains the named launch background. The final simulator Debug/Release and physical-device Debug builds passed; the latter was installed and launched. The user accepted the splash design.

## Completed physical-device haptic check

2026-10-21: The revised haptic build was installed and launched on the connected iPhone SE (3rd generation). The user confirmed that braking vibration is now perceptible. Device logs recorded successful continuous-player starts without haptic errors during that check. Extended holds, loop seams, and the full lifecycle checklist below remain separate checks.

## Functional pass on the device

1. Fly, change all three volumes and both settings, land, and leave the app. Reopen it, then terminate/relaunch it. Verify the world, position, facing, resting state, settings, journal counts, and stay duration. Repeat from the middle of a landing and departure.
2. Open the log. Check found/visited counts, per-world discovery and visit dates, total distance, and longest stay. Returning to a known world must not create a duplicate entry. Reopening a resting voyage must not add another landing or the hours spent with the app closed.
3. Enable **Keep sound when locked**. Lock the iPhone for at least five minutes. Listen for continuity and check the live Now Playing title. Use Play and Pause from the lock screen, unlock, and verify progress in the log and a stable camera.
4. Disable background sound, then lock the phone. Both sound and background travel should stop. Repeat with all three volumes set to zero.
5. With wired or Bluetooth headphones, disconnect the route while locked. Playback must pause without unexpectedly moving to the speaker, and must stay paused until explicitly resumed. Reconnect and resume. Repeat with an interruption from a call or another nonmixable audio app; resume only if the OS permits it.
6. Enable system Reduce Motion, then the app's **Gentler motion**. Verify that banking, bobbing, and nearby particles are removed while steering remains usable. Check the log and settings with large Dynamic Type and VoiceOver. The flight space provides named turn, slow, and resume-drift accessibility actions.
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
