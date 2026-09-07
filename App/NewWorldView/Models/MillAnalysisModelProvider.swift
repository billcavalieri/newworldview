import Foundation
import NewWorldROM

struct MillModelClassification {
    var classification: MillClassification
    var tokenUsage: MillTokenUsage?
}

protocol MillAnalysisModelProvider {
    var isAvailable: Bool { get }
    var unavailableReason: String? { get }
    func classify(context: MillAnalysisContext) async throws -> MillModelClassification
}

struct UnavailableMillAnalysisModelProvider: MillAnalysisModelProvider {
    let unavailableReason: String?

    var isAvailable: Bool { false }

    func classify(context: MillAnalysisContext) async throws -> MillModelClassification {
        throw MillAnalysisServiceError.modelUnavailable(unavailableReason ?? "Model unavailable.")
    }
}

struct MockMillAnalysisModelProvider: MillAnalysisModelProvider {
    var classification: MillClassification
    var tokenUsage: MillTokenUsage?
    var isAvailable: Bool { true }
    var unavailableReason: String? { nil }

    func classify(context: MillAnalysisContext) async throws -> MillModelClassification {
        MillModelClassification(classification: classification, tokenUsage: tokenUsage)
    }
}
