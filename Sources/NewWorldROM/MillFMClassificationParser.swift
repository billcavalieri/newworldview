import Foundation

/// Normalizes Apple FM structured output when kind/action fields are swapped or mislabeled.
public enum MillFMClassificationParser {
    public static func parse(
        kind: String,
        recommendedAction: String,
        confidence: Double,
        reasoning: String,
        suggestedSymbolName: String? = nil,
        evidenceUsed: [String] = []
    ) -> MillClassification {
        let repaired = repair(kind: kind, recommendedAction: recommendedAction)
        let boundedConfidence = min(max(confidence, 0), 1)
        return MillClassification(
            kind: repaired.kind,
            confidence: boundedConfidence,
            recommendedAction: repaired.action,
            reasoning: reasoning,
            suggestedSymbolName: suggestedSymbolName,
            evidenceUsed: evidenceUsed
        )
    }

    private static func repair(
        kind: String,
        recommendedAction: String
    ) -> (kind: MillClassificationKind, action: MillRecommendedAction) {
        var kindText = kind
        var actionText = recommendedAction

        var parsedKind = matchKind(kindText)
        var parsedAction = matchAction(actionText)

        if parsedKind == nil, let actionFromKind = matchAction(kindText) {
            parsedAction = parsedAction ?? actionFromKind
            parsedKind = matchKind(actionText) ?? defaultKind(for: actionFromKind)
        }

        if parsedAction == nil, let kindFromAction = matchKind(actionText) {
            parsedKind = parsedKind ?? kindFromAction
            parsedAction = matchAction(kindText) ?? .investigate
        }

        return (
            kind: parsedKind ?? .unknown,
            action: parsedAction ?? .investigate
        )
    }

    private static func defaultKind(for action: MillRecommendedAction) -> MillClassificationKind {
        switch action {
        case .skipCandidate:
            return .millableSpin
        case .revert:
            return .protected
        case .keep, .investigate:
            return .unknown
        }
    }

    private static func tokenKey(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private static func matchKind(_ raw: String) -> MillClassificationKind? {
        let key = tokenKey(raw)
        guard !key.isEmpty else { return nil }

        for kind in MillClassificationKind.allCases {
            if tokenKey(kind.rawValue) == key || tokenKey(kind.displayName) == key {
                return kind
            }
        }

        switch key {
        case "spin", "millable", "skip68k", "skip68kspin", "slothelper", "slothelperspin":
            return .millableSpin
        case "ui", "uipath", "protectedpath", "dialog", "getccursor":
            return .uiPath
        case "jt", "jtglue", "glue", "jumptable":
            return .jtGlue
        case "protected", "noskip", "trap":
            return .protected
        default:
            return nil
        }
    }

    private static func matchAction(_ raw: String) -> MillRecommendedAction? {
        let key = tokenKey(raw)
        guard !key.isEmpty else { return nil }

        for action in MillRecommendedAction.allCases {
            if tokenKey(action.rawValue) == key || tokenKey(action.displayName) == key {
                return action
            }
        }

        switch key {
        case "skip", "skip68k", "skipcandidate", "candidate", "mill":
            return .skipCandidate
        case "block", "deny", "protect":
            return .revert
        case "review", "escalate", "grok":
            return .investigate
        default:
            return nil
        }
    }
}
