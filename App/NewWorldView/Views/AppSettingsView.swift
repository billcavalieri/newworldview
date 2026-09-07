import SwiftUI

struct AppSettingsView: View {
    var body: some View {
        TabView {
            SyntaxHighlightSettingsView()
                .tabItem {
                    Label("Syntax", systemImage: "paintpalette")
                }

            MillResearchSettingsView()
                .tabItem {
                    Label("Research", systemImage: "chart.bar.doc.horizontal")
                }
        }
        .frame(minWidth: 520, minHeight: 560)
    }
}
