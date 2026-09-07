import AppKit
import NewWorldROM

@MainActor
final class DumpTextSelectionHandler: NSObject, NSTextViewDelegate {
    var addressSpace: AddressSpace?
    var onProgramAddressSelected: ((ProgramAddress) -> Void)?
    var onLineHighlight: ((NSRange) -> Void)?
    private var lastReportedKey: String?
    private var suppressCallbacks = false

    func performProgrammaticSelection(_ action: () -> Void) {
        suppressCallbacks = true
        action()
        DispatchQueue.main.async { [weak self] in
            self?.suppressCallbacks = false
        }
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !suppressCallbacks else { return }
        guard let textView = notification.object as? NSTextView else { return }

        let string = textView.string
        guard !string.isEmpty else { return }

        let location = min(textView.selectedRange.location, max(0, string.utf16.count - 1))
        guard location >= 0 else { return }

        let lineRange = DetailNavigation.lineRange(containingUTF16Index: location, in: string)
        if textView.selectedRange != lineRange {
            textView.setSelectedRange(lineRange)
            return
        }

        onLineHighlight?(lineRange)

        guard let space = addressSpace,
              let onProgramAddressSelected
        else { return }

        let line = (string as NSString).substring(with: lineRange)
        guard let addressValue = DetailNavigation.address(fromDisassemblyLine: line) else { return }

        let address = ProgramAddress(space: space, address: addressValue)
        guard lastReportedKey != address.key else { return }
        lastReportedKey = address.key
        onProgramAddressSelected(address)
    }

    func resetReporting() {
        lastReportedKey = nil
    }
}
