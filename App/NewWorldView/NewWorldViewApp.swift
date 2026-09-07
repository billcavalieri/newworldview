import SwiftUI
import UniformTypeIdentifiers

@main
struct NewWorldViewApp: App {
    @StateObject private var syntaxSettings = SyntaxHighlightSettings()
    @StateObject private var millResearchSettings = MillResearchSettings()

    var body: some Scene {
        DocumentGroup(viewing: ROMDocument.self) { file in
            ContentView(document: file.document, fileURL: file.fileURL)
                .environmentObject(syntaxSettings)
                .environmentObject(millResearchSettings)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .saveItem) { }
        }

        Settings {
            AppSettingsView()
                .environmentObject(syntaxSettings)
                .environmentObject(millResearchSettings)
        }
    }
}
