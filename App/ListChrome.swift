import DotMDCore
import SwiftUI

/// "Folders" with the sort menu, above the list.
struct ListHeader: View {
    @Binding var sort: FileSortOrder
    @Binding var showTitles: Bool

    var body: some View {
        HStack {
            Text("Folders")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Picker("Sort by", selection: $sort) {
                    Text("Last changed").tag(FileSortOrder.lastChanged)
                    Text("Name").tag(FileSortOrder.name)
                }
                .pickerStyle(.inline)
                Divider()
                Toggle("Show titles", isOn: $showTitles)
            } label: {
                Text(sort == .lastChanged ? "Last changed" : "Name")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Sort order and names")
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 2)
    }
}

/// Watch a folder, filter text, and the unread and changed toggles, below the list.
struct FilterBar: View {
    @Binding var filter: FileFilter
    let addFolder: () -> ()

    var body: some View {
        HStack(spacing: 6) {
            Button(action: addFolder) {
                Image(systemName: "plus")
            }
            .help("Watch a folder")
            .accessibilityLabel("Watch a folder")
            TextField("Filter", text: $filter.query)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
            Toggle(isOn: $filter.unreadOnly) {
                Image(systemName: "circle.fill").imageScale(.small)
            }
            .help("Show only unread files")
            .accessibilityLabel("Unread only")
            Toggle(isOn: $filter.changedOnly) {
                Image(systemName: "arrow.triangle.2.circlepath").imageScale(.small)
            }
            .help("Show only files that changed since you read them")
            .accessibilityLabel("Changed only")
        }
        .toggleStyle(.button)
        .buttonStyle(.borderless)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Divider() }
    }
}
