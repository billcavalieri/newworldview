import Foundation
import FoundationModels
import NewWorldROM

@Generable
struct FMMillClassification {
    @Guide(description: "Category only: millableSpin, uiPath, jtGlue, protected, or unknown. Never skipCandidate.")
    var kind: String

    @Guide(description: "Confidence from 0.0 to 1.0")
    var confidence: Double

    @Guide(description: "Action only: keep, revert, investigate, or skipCandidate. skipCandidate belongs here, not in kind.")
    var recommendedAction: String

    @Guide(description: "Short reasoning citing evidence keys from the context only")
    var reasoning: String

    @Guide(description: "Optional suggested symbol name")
    var suggestedSymbolName: String?

    @Guide(description: "Evidence keys referenced, such as tag:skip-slot-helper or logHits")
    var evidenceUsed: [String]
}

final class AppleFMProvider: MillAnalysisModelProvider {
    private(set) var unavailableReason: String?

    var isAvailable: Bool {
        unavailableReason == nil
    }

    init() {
        unavailableReason = Self.availabilityIssue()
    }

    func classify(context: MillAnalysisContext) async throws -> MillModelClassification {
        guard isAvailable else {
            throw MillAnalysisServiceError.modelUnavailable(unavailableReason ?? "Apple Intelligence unavailable.")
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let contextJSON = String(data: try encoder.encode(context), encoding: .utf8) ?? "{}"

        let instructions = """
        You classify Mac OS ROM addresses for macemu skip-68k milling.
        Use only evidence present in the JSON context. Do not invent addresses or traps.
        Prefer revert/protected for UI paths and NO_SKIP traps.
        Output two separate fields:
        - kind: millableSpin | uiPath | jtGlue | protected | unknown
        - recommendedAction: keep | revert | investigate | skipCandidate
        Never put skipCandidate in kind. Never put millableSpin in recommendedAction.
        """

        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: """
            Classify this mill analysis context:
            \(contextJSON)
            """,
            generating: FMMillClassification.self
        )

        let classification = Self.map(response.content)
        let tokenUsage = await Self.measureTokenUsage(from: response)
        return MillModelClassification(classification: classification, tokenUsage: tokenUsage)
    }

    private static func measureTokenUsage(
        from response: LanguageModelSession.Response<FMMillClassification>
    ) async -> MillTokenUsage? {
        if #available(macOS 26.4, *) {
            return await tokenUsageFromTranscript(from: response)
        }
        return nil
    }

    @available(macOS 26.4, *)
    private static func tokenUsageFromTranscript(
        from response: LanguageModelSession.Response<FMMillClassification>
    ) async -> MillTokenUsage? {
        let model = SystemLanguageModel.default
        var inputEntries: [Transcript.Entry] = []
        var outputEntries: [Transcript.Entry] = []
        for entry in response.transcriptEntries {
            switch entry {
            case .instructions, .prompt, .toolCalls, .toolOutput:
                inputEntries.append(entry)
            case .response:
                outputEntries.append(entry)
            @unknown default:
                break
            }
        }
        do {
            let inCount = try await model.tokenCount(for: inputEntries)
            let outCount = try await model.tokenCount(for: outputEntries)
            guard inCount > 0 || outCount > 0 else { return nil }
            return MillTokenUsage(inTokens: inCount, outTokens: outCount)
        } catch {
            return nil
        }
    }

    private static func map(_ generated: FMMillClassification) -> MillClassification {
        MillFMClassificationParser.parse(
            kind: generated.kind,
            recommendedAction: generated.recommendedAction,
            confidence: generated.confidence,
            reasoning: generated.reasoning,
            suggestedSymbolName: generated.suggestedSymbolName,
            evidenceUsed: generated.evidenceUsed
        )
    }

    private static func availabilityIssue() -> String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            return String(describing: reason)
        @unknown default:
            return "Apple Intelligence model unavailable."
        }
    }
}
