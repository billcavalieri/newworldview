import NewWorldROM
import SwiftUI

struct AnalysisInspector: View {
    let database: AnalysisDatabase
    let isAnalyzing: Bool
    var selection: AnalysisSelection?
    @Binding var trapFilter: GhidraExport.TrapExportFilter
    var onNavigate: (AnalysisSelection, ROMNode.ID, ProgramAddress) -> Void
    @State private var query = ""
    @State private var scrollPosition: AnalysisSelection.ID?
    @State private var displayedFunctions: [RecoveredFunction] = []
    @State private var displayedXRefs: [XRef] = []
    @State private var displayedTraps: [XRef] = []
    @State private var trapFilteredSource: [XRef] = []
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if isAnalyzing {
                ProgressView("Building xref database…")
                    .padding()
                Spacer()
            } else {
                List {
                    Section("Functions") {
                        ForEach(displayedFunctions) { function in
                            analysisRow(
                                selection: .function(function.id),
                                action: {
                                    onNavigate(.function(function.id), function.nodeID, function.address)
                                }
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(function.name)
                                        .font(.system(.body, design: .monospaced))
                                    Text(function.address.display)
                                        .font(.caption)
                                        .foregroundStyle(selection == .function(function.id) ? AppColors.selectedForeground.opacity(0.85) : .secondary)
                                }
                            }
                            .id(AnalysisSelection.function(function.id).id)
                        }
                    }
                    Section("A-traps used") {
                        ForEach(displayedTraps, id: \.id) { xref in
                            analysisRow(
                                selection: .trap(xref.id),
                                action: {
                                    onNavigate(.trap(xref.id), xref.fromNodeID, xref.from)
                                }
                            ) {
                                Text("\(xref.toSymbol ?? xref.to.display)  (\(xref.from.display))")
                                    .font(.system(.caption, design: .monospaced))
                            }
                            .id(AnalysisSelection.trap(xref.id).id)
                        }
                    }
                    Section("Xrefs") {
                        ForEach(displayedXRefs) { xref in
                            analysisRow(
                                selection: .xref(xref.id),
                                action: {
                                    onNavigate(.xref(xref.id), xref.fromNodeID, xref.from)
                                }
                            ) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(xref.kind.displayName)  \(xref.from.display) → \(xref.toSymbol ?? xref.to.display)")
                                        .font(.system(.caption, design: .monospaced))
                                    if let from = xref.fromSymbol {
                                        Text(from)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .id(AnalysisSelection.xref(xref.id).id)
                        }
                    }
                }
                .listStyle(.sidebar)
                .scrollPosition(id: $scrollPosition, anchor: .center)
                .onChange(of: selection?.id) { _, newValue in
                    scrollPosition = newValue
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { rebuildTrapFilteredSource() }
        .onChange(of: databaseSignature) { _, _ in rebuildTrapFilteredSource() }
        .onChange(of: trapFilter) { _, _ in rebuildTrapFilteredSource() }
        .onChange(of: query) { _, _ in applyQueryFilter() }
        .onDisappear { refreshTask?.cancel() }
    }

    private var databaseSignature: String {
        "\(database.functions.count)-\(database.xrefs.count)-\(database.symbols.count)"
    }

    private func rebuildTrapFilteredSource() {
        refreshTask?.cancel()
        let functions = database.functions
        let xrefs = database.xrefs
        let filter = trapFilter
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        refreshTask = Task {
            let filteredSource = Self.trapFilteredXRefs(from: xrefs, filter: filter)
            let functionsResult = Self.filteredFunctions(from: functions, needle: needle)
            let xrefsResult = Self.filteredXRefs(from: filteredSource, needle: needle)
            let trapsResult = Self.usedTraps(from: filteredSource)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                trapFilteredSource = filteredSource
                displayedFunctions = functionsResult
                displayedXRefs = xrefsResult
                displayedTraps = trapsResult
            }
        }
    }

    private func applyQueryFilter() {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        displayedFunctions = Self.filteredFunctions(from: database.functions, needle: needle)
        displayedXRefs = Self.filteredXRefs(from: trapFilteredSource, needle: needle)
        displayedTraps = Self.usedTraps(from: trapFilteredSource)
    }

    private func analysisRow<Label: View>(
        selection item: AnalysisSelection,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(selection == item ? AppColors.selectedForeground : AppColors.label)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(selection == item ? AppColors.selectedBackground : AppColors.controlBackground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Analysis")
                .font(.headline)
            Text("\(database.functions.count) functions · \(displayedXRefs.count) xrefs · \(database.symbols.count) symbols")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Trap filter", selection: $trapFilter) {
                Text("All traps").tag(GhidraExport.TrapExportFilter.all)
                Text("Mill-critical").tag(GhidraExport.TrapExportFilter.millCritical)
                Text("NO_SKIP UI").tag(GhidraExport.TrapExportFilter.noSkipUI)
            }
            .pickerStyle(.menu)
            TextField("Filter symbols and xrefs", text: $query)
                .textFieldStyle(.roundedBorder)
            Text("GetNewDialog: overlay id=\(G3MillClassification.overlayResourceID) (not on toast) vs Splash id=\(G3MillClassification.splashResourceID) (\(G3MillClassification.splashWindowSize.width)×\(G3MillClassification.splashWindowSize.height)). LoadSeg seg=66 is kajr false path.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
    }

    private static func filteredFunctions(from functions: [RecoveredFunction], needle: String) -> [RecoveredFunction] {
        if needle.isEmpty { return Array(functions.prefix(400)) }
        return functions.filter {
            $0.name.localizedCaseInsensitiveContains(needle)
                || $0.address.display.localizedCaseInsensitiveContains(needle)
        }
    }

    private static func filteredXRefs(from source: [XRef], needle: String) -> [XRef] {
        let filtered: [XRef]
        if needle.isEmpty {
            filtered = Array(source.prefix(400))
        } else {
            filtered = source.filter { xref in
                xref.kind.displayName.localizedCaseInsensitiveContains(needle)
                    || xref.from.display.localizedCaseInsensitiveContains(needle)
                    || xref.to.display.localizedCaseInsensitiveContains(needle)
                    || (xref.toSymbol?.localizedCaseInsensitiveContains(needle) ?? false)
                    || (xref.fromSymbol?.localizedCaseInsensitiveContains(needle) ?? false)
            }
        }
        return Array(filtered.prefix(400))
    }

    private static func trapFilteredXRefs(from xrefs: [XRef], filter: GhidraExport.TrapExportFilter) -> [XRef] {
        switch filter {
        case .all:
            return xrefs
        case .millCritical:
            return xrefs.filter { xref in
                guard xref.kind == .trap else { return true }
                return MillCriticalTraps.all.contains(UInt16(xref.to.address & 0xFFFF))
            }
        case .noSkipUI:
            return xrefs.filter { xref in
                guard xref.kind == .trap else { return true }
                return ATrapTable.noSkipUITraps.contains(UInt16(xref.to.address & 0xFFFF))
            }
        }
    }

    private static func usedTraps(from xrefs: [XRef]) -> [XRef] {
        var seen = Set<UInt64>()
        var result: [XRef] = []
        for xref in xrefs where xref.kind == .trap {
            if seen.insert(xref.to.address).inserted {
                result.append(xref)
            }
        }
        return result.sorted { ($0.toSymbol ?? "") < ($1.toSymbol ?? "") }
    }
}
