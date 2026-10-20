import DotMDRender
import SwiftUI

struct ReadingOptionsPopover: View {
    @Binding var options: ReadingOptions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let sizes = ReadingOptions.Size.allCases

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            sizeRow
            section("Font") {
                HStack(spacing: 8) {
                    fontTile(.serif, sample: Font.system(size: 20, weight: .semibold, design: .serif), name: "New York")
                    fontTile(.sans, sample: Font.system(size: 20, weight: .semibold), name: "SF Pro")
                    fontTile(.mono, sample: Font.system(size: 18, weight: .semibold, design: .monospaced), name: "SF Mono")
                }
            }
            section("Line width") {
                Picker("Line width", selection: $options.width) {
                    Text("Narrow").tag(ReadingOptions.Width.narrow)
                    Text("Medium").tag(ReadingOptions.Width.medium)
                    Text("Wide").tag(ReadingOptions.Width.wide)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            section("Page") {
                HStack(spacing: 12) {
                    paperSwatch(.auto, name: "Auto", fill: AnyShapeStyle(LinearGradient(colors: [.white, .black], startPoint: .topLeading, endPoint: .bottomTrailing)))
                    paperSwatch(.white, name: "White", fill: AnyShapeStyle(Color.white))
                    paperSwatch(.paper, name: "Paper", fill: AnyShapeStyle(Color(red: 0.97, green: 0.95, blue: 0.91)))
                    paperSwatch(.night, name: "Night", fill: AnyShapeStyle(Color(red: 0.07, green: 0.09, blue: 0.09)))
                }
            }
        }
        .padding(14)
        .frame(width: 300)
        .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.35, dampingFraction: 0.85), value: options)
    }

    private var sizeRow: some View {
        HStack {
            Button { step(-1) } label: {
                Text("A").font(.system(size: 12, weight: .semibold, design: .serif)).frame(width: 36, height: 28)
            }
            .disabled(options.size == sizes.first)
            .help("Smaller text")
            Spacer()
            HStack(spacing: 10) {
                ForEach(sizes, id: \.self) { size in
                    Circle()
                        .fill(size == options.size ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(width: 7, height: 7)
                        .scaleEffect(size == options.size ? 1.25 : 1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Text size")
            .accessibilityValue(options.size.rawValue)
            Spacer()
            Button { step(1) } label: {
                Text("A").font(.system(size: 19, weight: .semibold, design: .serif)).frame(width: 36, height: 28)
            }
            .disabled(options.size == sizes.last)
            .help("Bigger text")
        }
    }

    private func step(_ delta: Int) {
        guard let index = sizes.firstIndex(of: options.size) else { return }
        options.size = sizes[min(max(index + delta, 0), sizes.count - 1)]
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    private func fontTile(_ font: ReadingOptions.Font, sample: Font, name: String) -> some View {
        let selected = options.font == font
        return Button { options.font = font } label: {
            VStack(spacing: 2) {
                Text("Ag").font(sample)
                Text(name).font(.caption2).foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func paperSwatch(_ paper: ReadingOptions.Paper, name: String, fill: AnyShapeStyle) -> some View {
        let selected = options.paper == paper
        return Button { options.paper = paper } label: {
            VStack(spacing: 4) {
                Circle()
                    .fill(fill)
                    .frame(width: 30, height: 30)
                    .overlay(Circle().strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selected ? 2 : 0.5))
                Text(name).font(.caption2).foregroundStyle(selected ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
