import AppKit
import NewWorldROM
import SwiftUI

struct BinaryHexView: View {
    let data: Data
    var baseOffset: Int = 0
    var scrollToByteOffset: Int?
    var scrollRequestID: UUID?
    var addressSpace: AddressSpace?
    var programBase: UInt64?
    var skipHighlightByteOffsets: Set<Int> = []
    var onProgramAddressSelected: ((ProgramAddress) -> Void)?

    @EnvironmentObject private var syntaxSettings: SyntaxHighlightSettings

    var body: some View {
        HexDumpView(
            data: data,
            baseOffset: baseOffset,
            scrollToByteOffset: scrollToByteOffset,
            scrollRequestID: scrollRequestID,
            addressSpace: addressSpace,
            programBase: programBase,
            skipHighlightByteOffsets: skipHighlightByteOffsets,
            palette: syntaxSettings.resolvedPalette,
            onProgramAddressSelected: onProgramAddressSelected
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}

private struct HexDumpView: NSViewRepresentable {
    var data: Data
    var baseOffset: Int
    var scrollToByteOffset: Int?
    var scrollRequestID: UUID?
    var addressSpace: AddressSpace?
    var programBase: UInt64?
    var skipHighlightByteOffsets: Set<Int> = []
    var palette: SyntaxHighlightPalette
    var onProgramAddressSelected: ((ProgramAddress) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(data: data, baseOffset: baseOffset)
    }

    func makeNSView(context: Context) -> DumpColumnView {
        let column = DumpScrollSupport.makeColumn()
        let scrollView = column.scrollView

        let tableView = NSTableView()
        tableView.headerView = nil
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.backgroundColor = .textBackgroundColor
        tableView.gridStyleMask = []
        tableView.intercellSpacing = .zero
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 16
        tableView.selectionHighlightStyle = .regular
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.columnAutoresizingStyle = .noColumnAutoresizing
        tableView.style = .plain
        tableView.autoresizingMask = []
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator

        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hex"))
        tableColumn.width = context.coordinator.columnWidth
        tableColumn.minWidth = tableColumn.width
        tableColumn.maxWidth = tableColumn.width
        tableView.addTableColumn(tableColumn)

        scrollView.documentView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.lineNumberGutter = DumpLineNumberRulerSupport.attachTableGutter(
            to: column,
            tableView: tableView,
            rowHeight: 16
        )
        sizeDocument(in: scrollView, coordinator: context.coordinator)
        return column
    }

    func updateNSView(_ column: DumpColumnView, context: Context) {
        let scrollView = column.scrollView
        let dataChanged = context.coordinator.baseOffset != baseOffset
            || context.coordinator.data.count != data.count
            || context.coordinator.data.first != data.first
            || context.coordinator.data.last != data.last
        if dataChanged {
            context.coordinator.data = data
            context.coordinator.baseOffset = baseOffset
            context.coordinator.addressSpace = addressSpace
            context.coordinator.programBase = programBase
            context.coordinator.palette = palette
            context.coordinator.onProgramAddressSelected = onProgramAddressSelected
            context.coordinator.tableView?.reloadData()
            context.coordinator.lineNumberGutter?.refresh(lineCount: context.coordinator.rowCount)
            sizeDocument(in: scrollView, coordinator: context.coordinator)
            scrollView.contentView.scroll(to: .zero)
            return
        }
        context.coordinator.addressSpace = addressSpace
        context.coordinator.programBase = programBase
        context.coordinator.skipHighlightByteOffsets = skipHighlightByteOffsets
        context.coordinator.onProgramAddressSelected = onProgramAddressSelected
        if context.coordinator.palette != palette {
            context.coordinator.palette = palette
            context.coordinator.tableView?.reloadData()
        }
        scrollToTargetIfNeeded(in: scrollView, coordinator: context.coordinator)
    }

    private func scrollToTargetIfNeeded(in scrollView: DumpScrollView, coordinator: Coordinator) {
        guard let scrollRequestID, scrollRequestID != coordinator.lastScrollRequestID else { return }
        guard let byteOffset = scrollToByteOffset, let tableView = coordinator.tableView else { return }
        coordinator.lastScrollRequestID = scrollRequestID
        let row = max(0, min(coordinator.rowCount - 1, byteOffset / coordinator.bytesPerRow))
        let rowsToReload = IndexSet([coordinator.highlightedRow, row].compactMap { $0 })
        coordinator.highlightedRow = row
        coordinator.resetAddressReporting()
        DispatchQueue.main.async {
            tableView.scrollRowToVisible(row)
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            if !rowsToReload.isEmpty {
                tableView.reloadData(forRowIndexes: rowsToReload, columnIndexes: IndexSet(integer: 0))
            }
        }
    }

    private func sizeDocument(in scrollView: DumpScrollView, coordinator: Coordinator) {
        let rows = CGFloat(max(coordinator.rowCount, 1))
        scrollView.intrinsicDocumentSize = NSSize(
            width: coordinator.columnWidth,
            height: rows * 16
        )
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var data: Data
        var baseOffset: Int
        var addressSpace: AddressSpace?
        var programBase: UInt64?
        var skipHighlightByteOffsets: Set<Int> = []
        var palette: SyntaxHighlightPalette = .systemDefaults
        var onProgramAddressSelected: ((ProgramAddress) -> Void)?
        weak var tableView: NSTableView?
        weak var lineNumberGutter: DumpLineNumberGutterView?
        var lastScrollRequestID: UUID?
        var highlightedRow: Int?
        private var lastReportedAddressKey: String?

        let bytesPerRow = 16
        private let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

        var columnWidth: CGFloat {
            let sample = "00000000  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00 |................|"
            let width = (sample as NSString).size(withAttributes: [.font: font]).width
            return ceil(width) + 24
        }

        var rowCount: Int {
            if data.isEmpty { return 0 }
            return (data.count + bytesPerRow - 1) / bytesPerRow
        }

        init(data: Data, baseOffset: Int) {
            self.data = data
            self.baseOffset = baseOffset
        }

        func resetAddressReporting() {
            lastReportedAddressKey = nil
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = NSUserInterfaceItemIdentifier("hex-cell")
            let field: NSTextField
            if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? NSTextField {
                field = reused
            } else {
                field = NSTextField(labelWithString: "")
                field.identifier = identifier
                field.font = font
                field.textColor = .textColor
                field.backgroundColor = .textBackgroundColor
                field.drawsBackground = true
                field.lineBreakMode = .byClipping
            }
            field.isSelectable = false
            field.isEditable = false
            let line = line(for: row)
            field.attributedStringValue = DumpSyntaxHighlighter.highlightHexLine(
                line,
                font: font,
                palette: palette
            )
            let rowByteOffset = row * bytesPerRow
            let isSkipRow = skipHighlightByteOffsets.contains(rowByteOffset)
            let isHighlighted = row == highlightedRow || tableView.selectedRow == row
            let colors = DumpNavigationHighlight.highlightColors(forHighlighted: isHighlighted && !isSkipRow)
            if isHighlighted {
                let mutable = NSMutableAttributedString(attributedString: field.attributedStringValue)
                mutable.addAttribute(
                    .foregroundColor,
                    value: isSkipRow ? NSColor.labelColor : colors.foreground,
                    range: NSRange(location: 0, length: mutable.length)
                )
                field.attributedStringValue = mutable
            }
            if isSkipRow {
                field.backgroundColor = NSColor.systemOrange.withAlphaComponent(isHighlighted ? 0.45 : 0.22)
            } else {
                field.backgroundColor = colors.background
            }
            field.drawsBackground = true
            return field
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rowCount
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            let row = tableView.selectedRow
            guard row >= 0 else { return }

            let previous = highlightedRow
            highlightedRow = row
            reloadHighlightRows(previous: previous, current: row, in: tableView)

            guard let space = addressSpace,
                  let base = programBase,
                  let onProgramAddressSelected
            else { return }

            let offset = row * bytesPerRow
            let address = ProgramAddress(space: space, address: base + UInt64(offset))
            guard lastReportedAddressKey != address.key else { return }
            lastReportedAddressKey = address.key
            onProgramAddressSelected(address)
        }

        private func reloadHighlightRows(previous: Int?, current: Int, in tableView: NSTableView) {
            let rows = IndexSet([previous, current].compactMap { $0 })
            guard !rows.isEmpty else { return }
            tableView.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
        }

        private func line(for row: Int) -> String {
            let start = row * bytesPerRow
            let address = String(format: "%08X", baseOffset + start)
            guard start < data.count else { return address }

            let end = min(start + bytesPerRow, data.count)
            let slice = data[data.startIndex + start ..< data.startIndex + end]
            var hex = ""
            var ascii = ""
            for (index, byte) in slice.enumerated() {
                if index == 8 { hex += " " }
                hex += String(format: "%02X ", byte)
                ascii.append((32...126).contains(byte) ? Character(UnicodeScalar(byte)) : ".")
            }
            hex = hex.padding(toLength: 49, withPad: " ", startingAt: 0)
            return "\(address)  \(hex)|\(ascii)|"
        }
    }
}
