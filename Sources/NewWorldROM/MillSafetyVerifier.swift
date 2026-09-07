import Foundation

public enum MillSafetyVerifier {
    public static let defaultConfidenceThreshold = 0.75

    public static func precheck(
        context: MillAnalysisContext,
        reachability: MillReachabilityReport
    ) -> MillVerificationResult? {
        if context.tags.contains("get-new-dialog-stub") {
            return MillVerificationResult(
                classification: .protected(
                    reason: "Protected UI path (GetNewDialog overlay 0x5C86C–0x5C8C0); do not add skip-68k here.",
                    evidence: ["tag:get-new-dialog-stub"]
                ),
                status: .approved,
                source: .deterministic,
                skippedModel: true
            )
        }

        if context.tags.contains("no-skip-ui-trap") {
            return MillVerificationResult(
                classification: .protected(
                    reason: "Trap is in NO_SKIP_68K_OPS; keep native execution.",
                    evidence: ["tag:no-skip-ui-trap"]
                ),
                status: .approved,
                source: .deterministic,
                skippedModel: true
            )
        }

        if reachability.verdict == .protectedPath {
            return MillVerificationResult(
                classification: .protected(
                    reason: "Incoming path touches protected UI trap or GetNewDialog overlay range.",
                    evidence: ["reachability:protectedPath"]
                ),
                status: .approved,
                source: .deterministic,
                skippedModel: true
            )
        }

        return nil
    }

    public static func verify(
        context: MillAnalysisContext,
        reachability: MillReachabilityReport,
        modelClassification: MillClassification,
        confidenceThreshold: Double = defaultConfidenceThreshold
    ) -> MillVerificationResult {
        if context.tags.contains("get-new-dialog-stub") {
            return MillVerificationResult(
                classification: .protected(
                    reason: "Protected UI path (GetNewDialog overlay 0x5C86C–0x5C8C0); do not add skip-68k here.",
                    evidence: ["tag:get-new-dialog-stub"]
                ),
                status: .approved,
                source: .deterministic,
                skippedModel: true
            )
        }

        if context.tags.contains("no-skip-ui-trap") {
            return MillVerificationResult(
                classification: .protected(
                    reason: "Trap is in NO_SKIP_68K_OPS; keep native execution.",
                    evidence: ["tag:no-skip-ui-trap"]
                ),
                status: .approved,
                source: .deterministic,
                skippedModel: true
            )
        }

        var classification = modelClassification
        var suggestsEscalation = false

        if classification.recommendedAction == .skipCandidate,
           reachability.verdict == .protectedPath {
            classification.recommendedAction = .investigate
            classification.kind = .protected
            classification.reasoning += " Overridden: reachability reports protected path."
            suggestsEscalation = true
        }

        if classification.kind == .unknown || classification.confidence < confidenceThreshold {
            suggestsEscalation = true
        }

        if classification.recommendedAction == .investigate {
            suggestsEscalation = true
        }

        return MillVerificationResult(
            classification: classification,
            status: .pending,
            source: .appleFM,
            suggestsEscalation: suggestsEscalation,
            skippedModel: false
        )
    }

    public static func mergeDeterministicHint(
        into classification: inout MillClassification,
        hint: String?
    ) {
        guard let hint else { return }
        if hint.localizedCaseInsensitiveContains("do not") {
            classification.recommendedAction = .revert
            if classification.kind == .unknown {
                classification.kind = .protected
            }
        } else if hint.localizedCaseInsensitiveContains("candidate") {
            if classification.recommendedAction == .keep {
                classification.recommendedAction = .skipCandidate
            }
        }
        classification.evidenceUsed.append("deterministicHint")
    }

    public static func allowsApprovedSkipCandidate(
        _ annotation: MillAnnotation,
        reachability: MillReachabilityReport
    ) -> Bool {
        guard annotation.classification.recommendedAction == .skipCandidate else { return true }
        return reachability.verdict != .protectedPath
            && !annotation.contextSnapshot.tags.contains("get-new-dialog-stub")
            && !annotation.contextSnapshot.tags.contains("no-skip-ui-trap")
    }
}
