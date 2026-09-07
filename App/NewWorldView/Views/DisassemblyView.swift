import NewWorldROM
import SwiftUI

struct DisassemblyView: View {
    let data: Data
    let isa: DisassemblyISA
    let baseAddress: UInt64
    var space: AddressSpace = .unknown
    var database: AnalysisDatabase = .empty
    var scrollTarget: DetailScrollTarget?
    var onProgramAddressSelected: ((ProgramAddress) -> Void)?

    @State private var listing = "Disassembling…"

    var body: some View {
        TextContentView(
            text: listing,
            syntax: .disassembly,
            scrollLinePrefix: scrollTarget.map { DetailNavigation.scrollLinePrefix(for: $0.address) },
            scrollRequestID: scrollTarget?.requestID,
            addressSpace: space,
            onProgramAddressSelected: onProgramAddressSelected
        )
        .task(id: taskID) {
            let snapshot = data
            let isa = isa
            let baseAddress = baseAddress
            let space = space
            let database = database
            listing = await Task.detached(priority: .userInitiated) {
                let result = DisassemblyService.disassemble(
                    snapshot,
                    isa: isa,
                    baseAddress: baseAddress
                )
                if database.xrefs.isEmpty && database.symbols.isEmpty {
                    return DisassemblyService.listing(
                        snapshot,
                        isa: isa,
                        baseAddress: baseAddress
                    )
                }
                var lines: [String] = []
                if result.truncated {
                    lines.append("# Disassembly truncated to \(DisassemblyService.defaultByteLimit) bytes of \(snapshot.count)")
                }
                lines.append(AnalysisEngine.annotatedListing(result.instructions, space: space, database: database))
                return lines.joined(separator: "\n")
            }.value
        }
    }

    private var taskID: String {
        "\(isa.rawValue)-\(space.rawValue)-\(baseAddress)-\(data.count)-\(database.xrefs.count)-\(data.first ?? 0)"
    }
}
