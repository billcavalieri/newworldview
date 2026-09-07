import NewWorldROM
import SwiftUI

struct ROMTreeRevealRequest: Equatable {
    var nodeID: ROMNode.ID
    var requestID: UUID
}

struct ROMTreeView: View {
    let root: ROMNode
    @Binding var selection: ROMNode.ID
    @Binding var search: String
    var revealRequest: ROMTreeRevealRequest?

    @State private var expandedIDs: Set<ROMNode.ID> = []
    @State private var scrollPosition: ROMNode.ID?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter tree", text: $search)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            List(selection: listSelection) {
                if isSearching {
                    ForEach(searchResults) { node in
                        nodeRow(node)
                            .tag(node.id)
                            .id(node.id)
                    }
                } else {
                    ROMTreeRows(nodes: [root], expandedIDs: $expandedIDs)
                }
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 220)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .onAppear {
            if expandedIDs.isEmpty {
                expandedIDs.insert(root.id)
            }
        }
        .onChange(of: revealRequest) { _, request in
            guard let request else { return }
            reveal(nodeID: request.nodeID)
        }
    }

    /// List tries to emit `nil` after programmatic selection from the inspector.
    private var listSelection: Binding<ROMNode.ID?> {
        Binding(
            get: { selection },
            set: { newValue in
                guard let newValue else { return }
                selection = newValue
            }
        )
    }

    private var isSearching: Bool {
        !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchResults: [ROMNode] {
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [root] }
        return root.descendants.filter { node in
            node.name.localizedCaseInsensitiveContains(needle)
                || (node.text?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    private func reveal(nodeID: ROMNode.ID) {
        guard root.node(id: nodeID) != nil else { return }
        if let ancestors = root.ancestorIDs(of: nodeID) {
            expandedIDs.formUnion(ancestors)
        }
        selection = nodeID
        scrollPosition = nodeID
    }

    private func nodeRow(_ node: ROMNode) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .lineLimit(1)
                Text(subtitle(node))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon(for: node.kind))
        }
    }

    private func subtitle(_ node: ROMNode) -> String {
        if node.kind == .folder {
            return "\(node.children.count) items"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(node.size), countStyle: .file)
    }

    private func icon(for kind: ROMContentKind) -> String {
        switch kind {
        case .folder: return "folder"
        case .text: return "doc.plaintext"
        case .binary: return "doc"
        case .disassemblable(.powerPC): return "cpu"
        case .disassemblable(.m68k): return "memorychip"
        }
    }
}

private struct ROMTreeRows: View {
    let nodes: [ROMNode]
    @Binding var expandedIDs: Set<ROMNode.ID>

    var body: some View {
        ForEach(nodes) { node in
            ROMTreeRow(node: node, expandedIDs: $expandedIDs)
        }
    }
}

private struct ROMTreeRow: View {
    let node: ROMNode
    @Binding var expandedIDs: Set<ROMNode.ID>

    var body: some View {
        if let children = node.listChildren {
            DisclosureGroup(isExpanded: isExpanded) {
                ROMTreeRows(nodes: children, expandedIDs: $expandedIDs)
            } label: {
                nodeLabel
            }
            .tag(node.id)
            .id(node.id)
        } else {
            nodeLabel
                .tag(node.id)
                .id(node.id)
        }
    }

    private var isExpanded: Binding<Bool> {
        Binding(
            get: { expandedIDs.contains(node.id) },
            set: { expanded in
                if expanded {
                    expandedIDs.insert(node.id)
                } else {
                    expandedIDs.remove(node.id)
                }
            }
        )
    }

    private var nodeLabel: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
        }
    }

    private var subtitle: String {
        if node.kind == .folder {
            return "\(node.children.count) items"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(node.size), countStyle: .file)
    }

    private var icon: String {
        switch node.kind {
        case .folder: return "folder"
        case .text: return "doc.plaintext"
        case .binary: return "doc"
        case .disassemblable(.powerPC): return "cpu"
        case .disassemblable(.m68k): return "memorychip"
        }
    }
}

private extension ROMNode {
    var listChildren: [ROMNode]? {
        children.isEmpty ? nil : children
    }
}
