import SwiftUI

struct SyntaxHighlightSettingsView: View {
    @EnvironmentObject private var syntaxSettings: SyntaxHighlightSettings

    var body: some View {
        Form {
            Section {
                samplePreview
            } header: {
                Text("Preview")
            }

            Section {
                ForEach(SyntaxHighlightColorRole.allCases) { role in
                    colorRow(role)
                }
            } header: {
                Text("Syntax colors")
            } footer: {
                Text("Changes apply immediately to open document windows. Use NewWorldView → Settings (⌘,) to reopen this panel.")
            }

            Section {
                Button("Reset to System Defaults") {
                    syntaxSettings.resetToDefaults()
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 560)
        .navigationTitle("Syntax Highlighting")
    }

    private func colorRow(_ role: SyntaxHighlightColorRole) -> some View {
        LabeledContent {
            ColorPicker(
                "",
                selection: binding(for: role),
                supportsOpacity: true
            )
            .labelsHidden()
            .frame(width: 44)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(role.displayName)
                Text(role.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for role: SyntaxHighlightColorRole) -> Binding<Color> {
        Binding(
            get: { syntaxSettings.color(for: role) },
            set: { syntaxSettings.setColor($0, for: role) }
        )
    }

    private var samplePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            previewLine(
                "50326564:  900107d4  stw  r3, 0x7d4(r1)  ; call->sub_50331000",
                style: .disassembly
            )
            previewLine(
                "h# 00001234 constant bootscript-offset",
                style: .bootscript
            )
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
    }

    private func previewLine(_ text: String, style: DumpSyntaxStyle) -> some View {
        Text(AttributedString(DumpSyntaxHighlighter.highlight(text, style: style, palette: syntaxSettings.resolvedPalette)))
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
