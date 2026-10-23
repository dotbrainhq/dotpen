import DotMDCore
import SwiftUI

/// "Folders" with the sort menu, above the outline. The prototype's `.side-head`.
struct ListHeader: View {
    @Binding var sort: FileSortOrder
    @Binding var showTitles: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("Folders")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink4)
            Spacer(minLength: 8)
            Menu {
                Picker("Sort by", selection: $sort) {
                    Text("Last changed").tag(FileSortOrder.lastChanged)
                    Text("Name").tag(FileSortOrder.name)
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Show titles", isOn: $showTitles)
            } label: {
                HStack(spacing: 3) {
                    Text(sort == .lastChanged ? "Last changed" : "Name")
                        .font(.system(size: 11, weight: .medium))
                    Icon("chevron", size: 10)
                }
                .foregroundStyle(Palette.ink3)
                .padding(.vertical, 2)
                .padding(.horizontal, 4)
            }
            .menuStyle(.button)
            .buttonStyle(SidebarButtonStyle(cornerRadius: 5))
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Sort order and names")
            .accessibilityLabel("Sort by")
            .accessibilityValue(sort == .lastChanged ? "Last changed" : "Name")
        }
        .padding(.top, 2)
        .padding(.horizontal, 10)
        // The prototype's 6, less the same half point.
        .padding(.bottom, 5.5)
    }
}

/// Watch a folder, filter text, and the unread and changed toggles, pinned below the outline. The prototype's `.fbar`.
struct FilterBar: View {
    @Binding var filter: FileFilter
    let addFolder: () -> ()

    var body: some View {
        HStack(spacing: 4) {
            Button(action: addFolder) {
                Icon("plus", size: 16)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(SidebarButtonStyle(cornerRadius: 7))
            .help("Watch a folder")
            .accessibilityLabel("Watch a folder")
            FilterField(query: $filter.query)
            Toggle(isOn: $filter.unreadOnly) {
                Icon("unread", size: 16)
            }
            .help("Show only unread files")
            .accessibilityLabel("Unread only")
            Toggle(isOn: $filter.changedOnly) {
                Icon("changed", size: 16)
            }
            .help("Show only files that changed since you read them")
            .accessibilityLabel("Changed only")
        }
        .toggleStyle(FilterToggleStyle())
        .padding(.top, 8)
        .padding(.horizontal, 2)
        .overlay(alignment: .top) {
            Palette.line.frame(height: 0.5)
        }
    }
}

/// The filter text field: a rounded fill with a magnifying glass, no border.
private struct FilterField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 6) {
            Icon("search", size: 13)
                .foregroundStyle(Palette.ink4)
                .accessibilityHidden(true)
            TextField("Filter", text: $query, prompt: Text("Filter").foregroundStyle(Palette.ink4))
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Palette.ink)
                .accessibilityLabel("Filter files")
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 26, maxHeight: 26)
        .background(Palette.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

/// A borderless sidebar button: ink-3 content and a soft fill under the pointer.
struct SidebarButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        HoverFill(cornerRadius: cornerRadius, isOn: false) {
            configuration.label
        }
        .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// A filter toggle: like the add button, and drawn in DotMD's green on the selection wash while on.
struct FilterToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HoverFill(cornerRadius: 7, isOn: configuration.isOn) {
                configuration.label
                    .frame(width: 26, height: 26)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}

private struct HoverFill<Label: View>: View {
    let cornerRadius: CGFloat
    let isOn: Bool
    @ViewBuilder let label: Label
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        label
            .foregroundStyle(isOn ? Palette.accent : Palette.ink3)
            .background(isOn ? Palette.selection : hovering ? Palette.fill : .clear, in: shape)
            .contentShape(shape)
            .onHover { hovering = $0 }
    }
}
