import DarkbloomTelemetry
import SwiftUI

struct MenuBarSettingsLegend: View {
    let store: MonitorStore?
    let isVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Current indicators").font(.headline)
                Spacer(minLength: 12)
                if let store {
                    MenuBarStatusView(store: store, isVisible: isVisible)
                        .frame(width: MenuBarLabel.width, height: MenuBarLabel.height)
                        .padding(10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                } else {
                    Text("Readings unavailable")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            legendRow("Model", detail: "Spins during inference.") {
                DarkbloomLogo(image: DarkbloomLogoAsset.sourceImage, tint: .secondary)
            }
            legendRow("GPU", detail: "Ring fill shows whole-Mac GPU usage.") {
                Image(systemName: "cpu").foregroundStyle(.secondary)
            }
            legendRow("Cooling", detail: "Ring fill shows the highest measured fan speed.") {
                Image(systemName: "thermometer.medium").foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Model and cooling colors").font(.subheadline.weight(.medium))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { temperatureRanges }
                    VStack(alignment: .leading, spacing: 6) { temperatureRanges }
                }
                Text("Colors follow the latest GPU temperature. Faded readings are old; dashed GPU or fan rings have no reading.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("About these readings") {
                Text("Fan speed is measured RPM as a percentage of the fan’s reported maximum, using the highest value across fans. GPU usage includes all apps. Color boundaries are Bloomy display cues. Motion follows your Mac’s Reduce Motion setting. Hover over the indicators for current values and capture times.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
        }
        .padding(.vertical, 4)
    }

    private func legendRow<Icon: View>(_ title: String, detail: String,
                                       @ViewBuilder icon: () -> Icon) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon().frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var temperatureRanges: some View {
        let thresholds = MenuBarGPURing.Thresholds.standard
        let yellow = thresholds.yellowAtCelsius.formatted(.number.precision(.fractionLength(0)))
        let red = thresholds.redAtCelsius.formatted(.number.precision(.fractionLength(0)))
        range("Below \(yellow) °C", color: .green, spoken: "Green below \(yellow) degrees Celsius")
        range("\(yellow) to below \(red) °C", color: .yellow,
              spoken: "Yellow from \(yellow) to below \(red) degrees Celsius")
        range("\(red) °C and up", color: .red, spoken: "Red at \(red) degrees Celsius and above")
    }

    private func range(_ text: String, color: Color, spoken: String) -> some View {
        Label {
            Text(text).fixedSize()
        } icon: {
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .font(.caption)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}
