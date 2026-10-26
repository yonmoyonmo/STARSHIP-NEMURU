import SwiftUI

struct VoyagePositionView: View {
    let position: UniversePosition

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("GALACTIC COORDINATES")
                .font(.system(.caption2, design: .monospaced)).tracking(1.5)
                .foregroundStyle(.white.opacity(0.65))
            GalacticCoordinateReadings(position: position)
            Text("Origin · C–18").font(.caption2).foregroundStyle(.white.opacity(0.45))
        }
        .padding(14)
        .frame(maxWidth: 280)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct GalacticCoordinateReadings: View {
    let position: UniversePosition

    var body: some View {
        let address = VoyagePosition(position)
        VStack(spacing: 7) {
            reading("X", value: address.x)
            reading("Y", value: address.y)
            reading("Z", value: address.z)
        }.font(.system(.caption, design: .monospaced))
    }

    private func reading(_ axis: String, value: Double) -> some View {
        LabeledContent(axis) {
            Text(VoyagePosition.format(value)).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Galactic " + axis)
        .accessibilityValue(value.formatted(.number.precision(.fractionLength(3))) + " light years")
    }
}
