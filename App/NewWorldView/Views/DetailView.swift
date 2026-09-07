import NewWorldROM
import SwiftUI

enum DetailViewMode: String, CaseIterable, Identifiable {
    case automatic
    case text
    case hex
    case disassembly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Auto"
        case .text: return "Text"
        case .hex: return "Hex"
        case .disassembly: return "Disasm"
        }
    }
}

struct DetailView: View {
    let node: ROMNode?
    let database: AnalysisDatabase
    @Binding var mode: DetailViewMode
    var scrollTarget: DetailScrollTarget?
    var skipHighlightByteOffsets: Set<Int> = []
    var onProgramAddressSelected: ((ProgramAddress, ROMNode) -> Void)?

    private var activeScrollTarget: DetailScrollTarget? {
        guard let node, let scrollTarget, scrollTarget.nodeID == node.id else { return nil }
        return scrollTarget
    }

    var body: some View {
        Group {
            if let node {
                content(for: node)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                centeredUnavailable(
                    "Select a ROM item",
                    systemImage: "memorychip",
                    description: Text("Choose a node in the sidebar to inspect it. The ROM is never modified.")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(for node: ROMNode) -> some View {
        switch resolvedMode(for: node) {
        case .text:
            TextContentView(
                text: node.displayText ?? placeholder(for: node, expecting: "text"),
                syntax: syntaxStyle(for: node)
            )
        case .hex:
            if node.data.isEmpty {
                centeredUnavailable("No binary payload", systemImage: "doc")
            } else {
                BinaryHexView(
                    data: node.data,
                    baseOffset: node.containerOffset ?? 0,
                    scrollToByteOffset: byteOffset(in: node),
                    scrollRequestID: activeScrollTarget?.requestID,
                    addressSpace: addressSpace(for: node),
                    programBase: programBase(for: node),
                    skipHighlightByteOffsets: skipHighlightByteOffsets,
                    onProgramAddressSelected: programAddressHandler(for: node)
                )
            }
        case .disassembly:
            if let isa = node.kind.isa {
                let space = AnalysisEngine.space(for: node, isa: isa)
                DisassemblyView(
                    data: node.data,
                    isa: isa,
                    baseAddress: AnalysisEngine.baseAddress(for: node, space: space),
                    space: space,
                    database: database,
                    scrollTarget: activeScrollTarget,
                    onProgramAddressSelected: programAddressHandler(for: node)
                )
            } else {
                TextContentView(text: placeholder(for: node, expecting: "disassembly"))
            }
        case .automatic:
            EmptyView()
        }
    }

    private func byteOffset(in node: ROMNode) -> Int? {
        guard let activeScrollTarget else { return nil }
        return AnalysisEngine.byteOffset(for: activeScrollTarget.address, in: node)
    }

    private func addressSpace(for node: ROMNode) -> AddressSpace? {
        guard let isa = node.kind.isa else { return nil }
        return AnalysisEngine.space(for: node, isa: isa)
    }

    private func programBase(for node: ROMNode) -> UInt64? {
        guard let space = addressSpace(for: node) else { return nil }
        return AnalysisEngine.baseAddress(for: node, space: space)
    }

    private func programAddressHandler(for node: ROMNode) -> ((ProgramAddress) -> Void)? {
        guard onProgramAddressSelected != nil else { return nil }
        return { address in
            onProgramAddressSelected?(address, node)
        }
    }

    private func syntaxStyle(for node: ROMNode) -> DumpSyntaxStyle {
        if node.name == "Bootscript" {
            return .bootscript
        }
        if node.text?.contains("<CHRP-BOOT>") == true {
            return .bootscript
        }
        return .auto
    }

    private func resolvedMode(for node: ROMNode) -> DetailViewMode {
        switch mode {
        case .automatic:
            if node.kind.allowsDisassembly { return .disassembly }
            if node.displayText != nil { return .text }
            if !node.data.isEmpty { return .hex }
            return .text
        case .text, .hex, .disassembly:
            return mode
        }
    }

    @ViewBuilder
    private func centeredUnavailable(
        _ title: LocalizedStringKey,
        systemImage: String,
        description: Text? = nil
    ) -> some View {
        Group {
            if let description {
                ContentUnavailableView(title, systemImage: systemImage, description: description)
            } else {
                ContentUnavailableView(title, systemImage: systemImage)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(for node: ROMNode, expecting: String) -> String {
        switch expecting {
        case "text":
            return "No text representation for \(node.name)."
        case "disassembly":
            return "\(node.name) is not a known code region. Switch to Hex to inspect raw bytes."
        default:
            return "Nothing to display."
        }
    }
}
