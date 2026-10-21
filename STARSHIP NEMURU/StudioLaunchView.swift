import SwiftUI

struct StudioLaunchView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var markVisible = false
    @State private var voyageVisible = false
    @State private var coverVisible = true
    @State private var coverOpacity = 1.0

    private var preview: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("--preview-splash")
        #else
        false
        #endif
    }

    private var skipIntro: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains {
            ["--preview-landing", "--preview-universe", "--preview-log", "--preview-settings"].contains($0)
        }
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            if preview {
                StudioSplashArtwork(markVisible: true)
            } else if skipIntro {
                ContentView()
            } else {
                ZStack {
                    Color("LaunchBackground").ignoresSafeArea()
                    if voyageVisible {
                        ContentView().allowsHitTesting(!coverVisible).accessibilityHidden(coverVisible)
                    }
                    if coverVisible {
                        StudioSplashArtwork(markVisible: markVisible)
                            .opacity(coverOpacity)
                            .zIndex(1)
                    }
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active, coverVisible else { return }
                    do {
                        if !voyageVisible {
                            withAnimation(.easeIn(duration: reduceMotion ? 0.25 : 0.65)) { markVisible = true }
                            try await Task.sleep(for: .seconds(1.4))
                            try Task.checkCancellation()
                            // Start the voyage and its audio only as the studio card fades away.
                            voyageVisible = true
                            withAnimation(.easeInOut(duration: reduceMotion ? 0.25 : 0.8)) { coverOpacity = 0 }
                        }
                        try await Task.sleep(for: .seconds(reduceMotion ? 0.25 : 0.8))
                        try Task.checkCancellation()
                        coverVisible = false
                    } catch {
                        // Resume the unfinished intro when the app becomes active again.
                    }
                }
            }
        }
        .statusBarHidden()
    }
}

private struct StudioSplashArtwork: View {
    let markVisible: Bool

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color("LaunchBackground")
                // Static, sparse stars: no zoom, flash, or movement before the voyage.
                Canvas { context, size in
                    let stars: [(CGFloat, CGFloat, CGFloat, Double)] = [
                        (0.16, 0.17, 1.4, 0.28), (0.78, 0.12, 1, 0.18),
                        (0.86, 0.31, 1.6, 0.22), (0.09, 0.61, 1, 0.19),
                        (0.72, 0.73, 1.4, 0.24), (0.28, 0.81, 1, 0.2),
                        (0.57, 0.24, 1, 0.12), (0.91, 0.89, 1, 0.12)
                    ]
                    for (x, y, side, opacity) in stars {
                        let rect = CGRect(x: size.width * x, y: size.height * y, width: side, height: side)
                        context.fill(Path(rect), with: .color(Color(red: 0.58, green: 0.72, blue: 0.72).opacity(opacity)))
                    }
                }.accessibilityHidden(true)

                VStack(spacing: 22) {
                    Image("StudioLogo")
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(width: min(geometry.size.width * 0.72, 300))
                        .saturation(0.12)
                        .opacity(0.86)
                        .blendMode(.screen)
                    Text("presents")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .tracking(4)
                        .foregroundStyle(Color(red: 0.49, green: 0.61, blue: 0.61))
                }
                .opacity(markVisible ? 1 : 0)
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.46)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Yowenomo Studio presents Starship Nemuru")

                VStack {
                    Spacer()
                    Text("STARSHIP NEMURU")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .tracking(3)
                        .foregroundStyle(Color(red: 0.35, green: 0.46, blue: 0.47))
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 24) + 24)
                }
                .opacity(markVisible ? 1 : 0)
                .accessibilityHidden(true)
            }
            .ignoresSafeArea()
        }
    }
}
