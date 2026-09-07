import Foundation

public enum GrokPackGenerator {
    public struct Snippet: Sendable, Equatable {
        public var title: String
        public var body: String
    }

    public static func makeSnippet(
        address: ProgramAddress,
        parsed: ParsedROM,
        database: AnalysisDatabase,
        macROM: Data?,
        logHits: Int? = nil,
        deterministicHint: String? = nil,
        reachability: MillReachabilityReport? = nil
    ) -> Snippet {
        let context = MillAnalysisContextBuilder.make(
            address: address,
            parsed: parsed,
            database: database,
            macROM: macROM,
            logHits: logHits,
            deterministicHint: deterministicHint,
            reachability: reachability
        )
        return Snippet(title: address.display, body: MillAnalysisContextBuilder.markdown(from: context))
    }

    public static func makeSnippet(
        from logLine: String,
        parsed: ParsedROM,
        database: AnalysisDatabase,
        macROM: Data?,
        logHits: Int? = nil,
        deterministicHint: String? = nil,
        reachability: MillReachabilityReport? = nil
    ) -> Snippet? {
        guard let context = MillAnalysisContextBuilder.make(
            from: logLine,
            parsed: parsed,
            database: database,
            macROM: macROM,
            logHits: logHits,
            deterministicHint: deterministicHint,
            reachability: reachability
        ) else { return nil }
        return Snippet(title: "Log: \(context.address.display)", body: MillAnalysisContextBuilder.markdown(from: context))
    }
}
