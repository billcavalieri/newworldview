import NewWorldROM
import SwiftUI

enum MillHistogramKind: String, CaseIterable, Identifiable {
    case m68k
    case ppc
    case traps

    var id: String { rawValue }

    var title: String {
        switch self {
        case .m68k: return "68k offsets"
        case .ppc: return "PPC offsets"
        case .traps: return "Traps"
        }
    }
}

struct MillHistogramChartView: View {
    let kind: MillHistogramKind
    let report: MillResearchEngine.HistoricalReport
    var maxBars: Int = 24
    var annotationLookup: (ProgramAddress) -> MillAnnotation? = { _ in nil }
    var onSelectOffset: ((UInt64, AddressSpace) -> Void)?

    private var maxCount: Int {
        switch kind {
        case .m68k:
            return report.top68kOffsets.prefix(maxBars).map(\.count).max() ?? 1
        case .ppc:
            return report.topPPCOffsets.prefix(maxBars).map(\.count).max() ?? 1
        case .traps:
            return report.trapObservations.prefix(maxBars).map(\.count).max() ?? 1
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if barItems.isEmpty {
                Text("No data for this series.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(barItems) { item in
                        barRow(item)
                    }
                }
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private struct BarItem: Identifiable {
        var id: String
        var label: String
        var count: Int
        var subtitle: String?
        var offset: UInt64?
        var space: AddressSpace?
        var badge: String?
        var badgeColor: Color
    }

    private var barItems: [BarItem] {
        switch kind {
        case .m68k:
            return report.top68kOffsets.prefix(maxBars).map { entry in
                let address = AddressTranslation.virtualAddress(fromRomOffset: entry.offset, space: entry.space)
                let annotation = annotationLookup(address)
                return BarItem(
                    id: "68k-\(entry.offset)",
                    label: "0x\(String(format: "%X", entry.offset))",
                    count: entry.count,
                    subtitle: entry.symbolName ?? entry.recommendation,
                    offset: entry.offset,
                    space: entry.space,
                    badge: annotation?.classification.recommendedAction.displayName,
                    badgeColor: badgeColor(for: annotation)
                )
            }
        case .ppc:
            return report.topPPCOffsets.prefix(maxBars).map { entry in
                BarItem(
                    id: "ppc-\(entry.offset)",
                    label: "0x\(String(format: "%X", entry.offset))",
                    count: entry.count,
                    subtitle: entry.symbolName,
                    offset: entry.offset,
                    space: entry.space,
                    badge: nil,
                    badgeColor: .clear
                )
            }
        case .traps:
            return report.trapObservations.prefix(maxBars).map { trap in
                BarItem(
                    id: "trap-\(trap.trap)",
                    label: trap.name,
                    count: trap.count,
                    subtitle: trap.noSkipProtected ? "protected" : nil,
                    offset: nil,
                    space: nil,
                    badge: trap.noSkipProtected ? "protected" : nil,
                    badgeColor: .orange.opacity(0.25)
                )
            }
        }
    }

    private func barRow(_ item: BarItem) -> some View {
        HStack(spacing: 10) {
            Button {
                if let offset = item.offset, let space = item.space {
                    onSelectOffset?(offset, space)
                }
            } label: {
                Text(item.label)
                    .font(.caption.monospaced())
                    .frame(width: 88, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(item.offset == nil)

            GeometryReader { proxy in
                let width = proxy.size.width * CGFloat(item.count) / CGFloat(max(maxCount, 1))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.18))
                    Capsule()
                        .fill(Color.accentColor.opacity(0.75))
                        .frame(width: max(width, 2))
                }
            }
            .frame(height: 16)

            Text("\(item.count)×")
                .font(.caption.monospaced())
                .frame(width: 52, alignment: .trailing)

            if let badge = item.badge {
                Text(badge)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(item.badgeColor, in: Capsule())
            }
        }
        .frame(height: 22)
        .help(item.subtitle ?? "")
    }

    private func badgeColor(for annotation: MillAnnotation?) -> Color {
        guard let annotation else { return .clear }
        switch annotation.status {
        case .approved: return .green.opacity(0.25)
        case .rejected: return .red.opacity(0.25)
        case .pending: return .orange.opacity(0.25)
        }
    }
}

struct MillHistogramPanel: View {
    let report: MillResearchEngine.HistoricalReport
    var annotationLookup: (ProgramAddress) -> MillAnnotation? = { _ in nil }
    var onNavigateOffset: (UInt64, AddressSpace) -> Void

    @State private var kind: MillHistogramKind = .m68k

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Histogram", selection: $kind) {
                ForEach(MillHistogramKind.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("Histogram entries") {
                Text(entryCountLabel)
            }

            MillHistogramChartView(
                kind: kind,
                report: report,
                annotationLookup: annotationLookup,
                onSelectOffset: onNavigateOffset
            )
        }
    }

    private var entryCountLabel: String {
        switch kind {
        case .m68k:
            return "\(report.top68kOffsets.count) 68k offsets"
        case .ppc:
            return "\(report.topPPCOffsets.count) PPC offsets"
        case .traps:
            return "\(report.trapObservations.count) traps"
        }
    }
}
