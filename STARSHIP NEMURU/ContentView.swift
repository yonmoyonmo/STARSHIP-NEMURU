import SwiftUI

struct ContentView: View {
    @StateObject private var flight = FlightSession(store: VoyageStore.applicationStore())
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("showVoyagePosition") private var showVoyagePosition = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                SpaceView(session: flight)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { flight.touch(at: $0.location, size: geometry.size) }
                        .onEnded { _ in flight.release() })
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Nemuru flight space")
                    .accessibilityHint("Hold to slow down. Drag to turn. Release to drift. Flight actions are available.")
                    .accessibilityAction(named: "Turn left") { flight.accessibleTurn([-1, 0]) }
                    .accessibilityAction(named: "Turn right") { flight.accessibleTurn([1, 0]) }
                    .accessibilityAction(named: "Turn up") { flight.accessibleTurn([0, -1]) }
                    .accessibilityAction(named: "Turn down") { flight.accessibleTurn([0, 1]) }
                    .accessibilityAction(named: "Slow down") { flight.accessibleSlow = true }
                    .accessibilityAction(named: "Resume drifting") { flight.accessibleSlow = false }
                LinearGradient(colors: [.black.opacity(0.35), .clear, .black.opacity(0.6)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea().allowsHitTesting(false)
                VStack(alignment: .leading) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NEMURU").font(.system(size: 18, weight: .medium, design: .monospaced)).tracking(5)
                            Text(flight.groundVisible ? "RESTING · \(flight.planetName)" : "QUIET VOYAGE")
                                .font(.system(.caption2, design: .monospaced)).tracking(2).foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                        Button {
                            flight.release()
                            flight.log.refresh()
                            flight.logPresented = true
                        } label: {
                            Image(systemName: "book.closed").font(.system(size: 18))
                                .frame(width: 48, height: 48).background(.white.opacity(0.06), in: Circle())
                        }.accessibilityLabel("Voyage log").disabled(!flight.controlsVisible)
                        Button {
                            flight.release()
                            showVoyagePosition.toggle()
                        } label: {
                            Image(systemName: showVoyagePosition ? "location.fill" : "location")
                                .font(.system(size: 18))
                                .frame(width: 48, height: 48)
                                .background(showVoyagePosition ? .white.opacity(0.16) : .white.opacity(0.06), in: Circle())
                        }
                        .accessibilityLabel("Galactic coordinates")
                        .accessibilityValue(showVoyagePosition ? "Shown" : "Hidden")
                        .accessibilityAddTraits(showVoyagePosition ? .isSelected : [])
                        .disabled(!flight.controlsVisible)
                        Button {
                            flight.release()
                            flight.settingsPresented = true
                        } label: {
                            Image(systemName: "gearshape").font(.system(size: 18))
                                .frame(width: 48, height: 48).background(.white.opacity(0.06), in: Circle())
                        }.accessibilityLabel("Voyage settings")
                            .disabled(!flight.controlsVisible)
                    }
                    Spacer()
                    VStack(alignment: .leading, spacing: 14) {
                        if flight.canLand || flight.phase == .landed {
                            Button(action: flight.landOrLaunch) {
                                HStack(spacing: 12) {
                                    Image(systemName: flight.phase == .landed ? "arrow.up.right" : "arrow.down.right")
                                    Text(flight.phase == .landed ? "RETURN TO THE STARS" : "LAND SOMEWHERE QUIET")
                                        .font(.system(.caption, design: .monospaced).weight(.medium)).tracking(1.5)
                                }
                                .padding(.horizontal, 18).frame(minHeight: 48)
                                .background(.white.opacity(0.08), in: Capsule())
                            }
                        }
                        HStack {
                            Text(status).tracking(2)
                            Spacer()
                            if flight.phase == .flying {
                                Text(String(format: "%02.0f  /  %@", flight.speed, flight.isProximityStopped ? "HOLD" : "DRIFT")).tracking(1)
                            }
                        }.font(.system(.caption2, design: .monospaced)).foregroundStyle(.white.opacity(0.55))
                        Text(instruction)
                            .font(.caption2).foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.horizontal, 25).padding(.top, 16).padding(.bottom, 22)
                if showVoyagePosition {
                    VoyagePositionView(position: flight.position)
                    .padding(.horizontal, 25)
                    .padding(.top, 84)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .allowsHitTesting(false)
                }
                Color.black.opacity(flight.fade).ignoresSafeArea().allowsHitTesting(false)
            }
            .foregroundStyle(Color(red: 0.8, green: 0.87, blue: 0.86))
            .background(.black)
        }
        .statusBarHidden()
        .sheet(isPresented: $flight.settingsPresented, onDismiss: { flight.release(); flight.save() }) {
            soundSettings.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $flight.logPresented, onDismiss: { flight.release() }) {
            VoyageLogView(log: flight.log, storageMessage: flight.storageMessage)
        }
        .onAppear { flight.reduceMotion = reduceMotion; flight.setActive(true) }
        .onDisappear { flight.shutdown() }
        .onChange(of: reduceMotion) { _, value in flight.reduceMotion = value }
        .onChange(of: showVoyagePosition) { _, _ in flight.release() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { flight.setActive(true) }
            else if phase == .background { flight.setActive(false, background: true) }
            else { flight.release() }
        }
        .environment(\.locale, Locale(identifier: "en"))
    }

    private var instruction: String {
        switch flight.phase {
        case .flying: return flight.isProximityStopped ? "Turn away to drift · Land to rest" : "Hold to slow · Drag to turn · Release to drift"
        case .landing: return "Let Nemuru settle."
        case .landed: return "Stay a little. There is nothing to do."
        case .launching: return "The voyage continues."
        }
    }

    private var status: String {
        switch flight.phase {
        case .flying: return flight.isProximityStopped ? "HOLDING POSITION" : (flight.canLand ? "\(flight.planetName) · WITHIN REACH" : "FREE FLIGHT")
        case .landing: return "SETTLING DOWN"
        case .landed: return "\(flight.planetName) · A QUIET PLACE"
        case .launching: return "BACK INTO THE NIGHT"
        }
    }

    private var soundSettings: some View {
        NavigationStack {
            Form {
                Section("Aboard Nemuru") {
                    volume("Engine & cabin", value: $flight.engineVolume)
                    volume("Distant signals", value: $flight.signalVolume)
                    volume("Planet atmosphere", value: $flight.ambienceVolume)
                    Button(flight.soundPlaying ? "Pause sound" : "Resume sound") {
                        if flight.soundPlaying { flight.pauseAudio() }
                        else { flight.startAudio(userInitiated: true) }
                    }
                }
                Section {
                    Toggle("Keep sound when locked", isOn: $flight.backgroundSound)
                } footer: {
                    Text("While sound plays in the background, the voyage continues quietly.")
                }
                Section {
                    Text("Sounds are synthesized aboard. Set a layer to zero to silence it. Your voyage and settings save automatically.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let error = flight.audioError { Text(error).font(.footnote) }
                    if let message = flight.storageMessage { Text(message).font(.footnote) }
                }
            }
            .navigationTitle("Voyage settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Close") { flight.settingsPresented = false } } }
            .tint(Color(red: 0.6, green: 0.78, blue: 0.72))
        }
    }

    private func volume(_ title: String, value: Binding<Float>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline)
            Slider(value: value, in: 0...1).accessibilityLabel(title)
        }
    }
}
