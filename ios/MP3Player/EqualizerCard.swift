import SonusCore
import SwiftUI

/// The Equaliser card in Playback controls: on/off, the response curve, presets and six bands.
///
/// Choosing a preset or moving a band switches the equaliser on. Double-tap a band to put it back
/// to 0 dB. Each band is an adjustable control for VoiceOver (swipe up or down for ±1 dB).
struct EqualizerCard: View {
    @ObservedObject private var equalizer = EqualizerController.shared

    private var settings: EqualizerSettings { equalizer.settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            EqualizerCurve(settings: settings)
                .frame(height: ScreenMetrics.isCompact ? 56 : 72)
                .opacity(settings.isEnabled ? 1 : 0.35)
                .accessibilityHidden(true)

            presets

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(0..<EqualizerSettings.bandCount, id: \.self) { band in
                    EqualizerBandSlider(
                        label: Self.bandLabel(band),
                        gain: settings.gains[band],
                        isEnabled: settings.isEnabled
                    ) { gain in
                        equalizer.setGain(gain, forBand: band)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: ScreenMetrics.isCompact ? 150 : 176)

            Text("Applies to everything you play on this iPhone. AirPlay plays without it.")
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .emberCard(cornerRadius: Theme.Radius.tile)
        .haptic(.selection, trigger: settings.presetID)
    }

    private var header: some View {
        HStack {
            Label("Equaliser", systemImage: "slider.vertical.3")
                .font(.system(.headline).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if settings.isEnabled && !settings.isFlat {
                Button("Reset") { equalizer.reset() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityHint("Sets every band to 0 dB")
            }
            Toggle("Equaliser", isOn: Binding(get: { settings.isEnabled }, set: { equalizer.setEnabled($0) }))
                .labelsHidden()
                .tint(Theme.accent)
        }
    }

    private var presets: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(EqualizerPreset.all) { preset in
                    FilterPill(title: preset.name, isSelected: settings.isEnabled && settings.presetID == preset.id) {
                        equalizer.choose(preset)
                    }
                }
            }
        }
    }

    static func bandLabel(_ band: Int) -> String {
        let frequency = EqualizerSettings.frequencies[band]
        if frequency >= 1000 {
            let kilohertz = frequency / 1000
            return kilohertz == kilohertz.rounded() ? "\(Int(kilohertz))k" : String(format: "%.1fk", kilohertz)
        }
        return "\(Int(frequency))"
    }
}

/// The equaliser's frequency response from 20 Hz to 20 kHz, ±12 dB, with a 0 dB line.
struct EqualizerCurve: View {
    let settings: EqualizerSettings

    var body: some View {
        GeometryReader { geometry in
            let points = EqualizerResponse.curve(for: settings, points: 80)
            let size = geometry.size
            let path = Self.path(points, in: size)
            ZStack {
                Path { line in
                    line.move(to: CGPoint(x: 0, y: size.height / 2))
                    line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                }
                .stroke(Theme.textMuted.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))

                path.fill.fill(LinearGradient(
                    colors: [Theme.accent.opacity(0.35), Theme.accent.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
                path.line.stroke(Theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            .animation(Theme.Motion.snappy, value: settings)
        }
    }

    /// The curve as a line, plus the area between it and the 0 dB line.
    private static func path(_ points: [(frequency: Double, gainDB: Double)], in size: CGSize) -> (line: Path, fill: Path) {
        let range = Double(EqualizerSettings.maxGain)
        func point(_ index: Int, _ gain: Double) -> CGPoint {
            let x = size.width * CGFloat(index) / CGFloat(max(1, points.count - 1))
            let clamped = min(range, max(-range, gain))
            let y = size.height / 2 - CGFloat(clamped / range) * (size.height / 2 - 2)
            return CGPoint(x: x, y: y)
        }
        var line = Path()
        for (index, sample) in points.enumerated() {
            let location = point(index, sample.gainDB)
            if index == 0 { line.move(to: location) } else { line.addLine(to: location) }
        }
        var fill = line
        fill.addLine(to: CGPoint(x: size.width, y: size.height / 2))
        fill.addLine(to: CGPoint(x: 0, y: size.height / 2))
        fill.closeSubpath()
        return (line, fill)
    }
}

/// One vertical band: drag to set ±12 dB in 0.5 dB steps, double-tap for 0 dB.
struct EqualizerBandSlider: View {
    let label: String
    let gain: Float
    let isEnabled: Bool
    let onChange: (Float) -> Void

    private let thumbSize: CGFloat = 22

    var body: some View {
        VStack(spacing: 8) {
            Text(Self.format(gain))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isEnabled ? Theme.textPrimary : Theme.textMuted)
                .frame(height: 14)

            GeometryReader { geometry in
                let height = geometry.size.height
                let travel = height - thumbSize
                let centreY = height / 2
                let thumbY = centreY - CGFloat(gain / EqualizerSettings.maxGain) * travel / 2
                ZStack(alignment: .top) {
                    Capsule()
                        .fill(Theme.surfaceRaised)
                        .frame(width: 4)
                        .frame(maxHeight: .infinity)
                    Capsule()
                        .fill(isEnabled ? Theme.accent : Theme.textMuted)
                        .frame(width: 4, height: abs(thumbY - centreY))
                        .offset(y: min(thumbY, centreY))
                    Circle()
                        .fill(isEnabled ? Theme.accent : Theme.textSubtle)
                        .frame(width: thumbSize, height: thumbSize)
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .offset(y: thumbY - thumbSize / 2)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = (centreY - value.location.y) / max(1, travel / 2)
                            let raw = Float(fraction) * EqualizerSettings.maxGain
                            onChange((raw * 2).rounded() / 2)
                        }
                )
                .simultaneousGesture(TapGesture(count: 2).onEnded { onChange(0) })
            }

            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSubtle)
        }
        .accessibilityElement()
        .accessibilityLabel("\(label) hertz")
        .accessibilityValue(Self.format(gain) + " decibels")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(EqualizerSettings.maxGain, gain + 1))
            case .decrement: onChange(max(-EqualizerSettings.maxGain, gain - 1))
            @unknown default: break
            }
        }
    }

    static func format(_ gain: Float) -> String {
        if abs(gain) < 0.05 { return "0" }
        let text = gain == gain.rounded() ? String(Int(gain)) : String(format: "%.1f", gain)
        return gain > 0 ? "+" + text : text
    }
}
