import Foundation

public enum MillClassificationKind: String, Codable, Sendable, CaseIterable {
    case millableSpin
    case uiPath
    case jtGlue
    case protected
    case unknown

    public var displayName: String {
        switch self {
        case .millableSpin: return "Millable spin"
        case .uiPath: return "UI path"
        case .jtGlue: return "JT glue"
        case .protected: return "Protected"
        case .unknown: return "Unknown"
        }
    }
}

public enum MillRecommendedAction: String, Codable, Sendable, CaseIterable {
    case keep
    case revert
    case investigate
    case skipCandidate

    public var displayName: String {
        switch self {
        case .keep: return "Keep"
        case .revert: return "Revert"
        case .investigate: return "Investigate"
        case .skipCandidate: return "Skip candidate"
        }
    }
}

public struct MillTokenUsage: Codable, Sendable, Equatable {
    public var inTokens: Int
    public var outTokens: Int
    public var totalTokens: Int

    public init(inTokens: Int = 0, outTokens: Int = 0, totalTokens: Int? = nil) {
        self.inTokens = inTokens
        self.outTokens = outTokens
        self.totalTokens = totalTokens ?? (inTokens + outTokens)
    }

    enum CodingKeys: String, CodingKey {
        case inTokens = "in"
        case outTokens = "out"
        case totalTokens = "total"
    }

    public static let zero = MillTokenUsage()

    public static func + (lhs: MillTokenUsage, rhs: MillTokenUsage) -> MillTokenUsage {
        MillTokenUsage(
            inTokens: lhs.inTokens + rhs.inTokens,
            outTokens: lhs.outTokens + rhs.outTokens,
            totalTokens: lhs.totalTokens + rhs.totalTokens
        )
    }
}

public struct MillClassification: Codable, Sendable, Equatable {
    public var kind: MillClassificationKind
    public var confidence: Double
    public var recommendedAction: MillRecommendedAction
    public var reasoning: String
    public var suggestedSymbolName: String?
    public var evidenceUsed: [String]

    public init(
        kind: MillClassificationKind,
        confidence: Double,
        recommendedAction: MillRecommendedAction,
        reasoning: String,
        suggestedSymbolName: String? = nil,
        evidenceUsed: [String] = []
    ) {
        self.kind = kind
        self.confidence = confidence
        self.recommendedAction = recommendedAction
        self.reasoning = reasoning
        self.suggestedSymbolName = suggestedSymbolName
        self.evidenceUsed = evidenceUsed
    }

    public static func protected(reason: String, evidence: [String] = []) -> MillClassification {
        MillClassification(
            kind: .protected,
            confidence: 1.0,
            recommendedAction: .revert,
            reasoning: reason,
            evidenceUsed: evidence
        )
    }
}

public enum MillReachabilityVerdict: String, Codable, Sendable {
    case safeCandidate
    case protectedPath
    case ambiguous
}

public struct MillReachabilityReport: Codable, Sendable, Equatable {
    public var verdict: MillReachabilityVerdict
    public var paths: [[MillPathStep]]
    public var touchesProtectedTrap: Bool
    public var touchesGetNewDialogStub: Bool

    public init(
        verdict: MillReachabilityVerdict,
        paths: [[MillPathStep]] = [],
        touchesProtectedTrap: Bool = false,
        touchesGetNewDialogStub: Bool = false
    ) {
        self.verdict = verdict
        self.paths = paths
        self.touchesProtectedTrap = touchesProtectedTrap
        self.touchesGetNewDialogStub = touchesGetNewDialogStub
    }
}

public struct MillPathStep: Codable, Sendable, Equatable, Identifiable {
    public var id: String { address.key }
    public var address: ProgramAddress
    public var symbolName: String?
    public var edgeKind: XRefKind?

    public init(address: ProgramAddress, symbolName: String? = nil, edgeKind: XRefKind? = nil) {
        self.address = address
        self.symbolName = symbolName
        self.edgeKind = edgeKind
    }
}

public struct MillXRefSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String { "\(fromDisplay)>\(kind.rawValue)" }
    public var fromDisplay: String
    public var kind: XRefKind
    public var fromSymbol: String?

    public init(fromDisplay: String, kind: XRefKind, fromSymbol: String? = nil) {
        self.fromDisplay = fromDisplay
        self.kind = kind
        self.fromSymbol = fromSymbol
    }
}

public struct MillAnalysisContext: Codable, Sendable, Equatable {
    public var address: ProgramAddress
    public var romOffset: UInt64?
    public var nodeName: String?
    public var symbolName: String?
    public var logHits: Int?
    public var logLine: String?
    public var tags: [String]
    public var incomingXrefs: [MillXRefSummary]
    public var outgoingTraps: [String]
    public var disasmLines: [String]
    public var heartbeatPath: [MillPathStep]
    public var reachability: MillReachabilityReport?
    public var deterministicHint: String?

    public init(
        address: ProgramAddress,
        romOffset: UInt64? = nil,
        nodeName: String? = nil,
        symbolName: String? = nil,
        logHits: Int? = nil,
        logLine: String? = nil,
        tags: [String] = [],
        incomingXrefs: [MillXRefSummary] = [],
        outgoingTraps: [String] = [],
        disasmLines: [String] = [],
        heartbeatPath: [MillPathStep] = [],
        reachability: MillReachabilityReport? = nil,
        deterministicHint: String? = nil
    ) {
        self.address = address
        self.romOffset = romOffset
        self.nodeName = nodeName
        self.symbolName = symbolName
        self.logHits = logHits
        self.logLine = logLine
        self.tags = tags
        self.incomingXrefs = incomingXrefs
        self.outgoingTraps = outgoingTraps
        self.disasmLines = disasmLines
        self.heartbeatPath = heartbeatPath
        self.reachability = reachability
        self.deterministicHint = deterministicHint
    }
}

public enum AnnotationSource: String, Codable, Sendable {
    case appleFM
    case user
    case grokBuild
    case deterministic
}

public enum AnnotationStatus: String, Codable, Sendable, CaseIterable {
    case pending
    case approved
    case rejected
}

public struct MillAnnotation: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var address: ProgramAddress
    public var classification: MillClassification
    public var source: AnnotationSource
    public var status: AnnotationStatus
    public var createdAt: Date
    public var reviewedAt: Date?
    public var contextSnapshot: MillAnalysisContext
    public var suggestsEscalation: Bool
    public var tokenUsage: MillTokenUsage?

    public init(
        id: UUID = UUID(),
        address: ProgramAddress,
        classification: MillClassification,
        source: AnnotationSource,
        status: AnnotationStatus = .pending,
        createdAt: Date = Date(),
        reviewedAt: Date? = nil,
        contextSnapshot: MillAnalysisContext,
        suggestsEscalation: Bool = false,
        tokenUsage: MillTokenUsage? = nil
    ) {
        self.id = id
        self.address = address
        self.classification = classification
        self.source = source
        self.status = status
        self.createdAt = createdAt
        self.reviewedAt = reviewedAt
        self.contextSnapshot = contextSnapshot
        self.suggestsEscalation = suggestsEscalation
        self.tokenUsage = tokenUsage
    }
}

public struct MillVerificationResult: Sendable, Equatable {
    public var classification: MillClassification
    public var status: AnnotationStatus
    public var source: AnnotationSource
    public var suggestsEscalation: Bool
    public var skippedModel: Bool

    public init(
        classification: MillClassification,
        status: AnnotationStatus,
        source: AnnotationSource,
        suggestsEscalation: Bool = false,
        skippedModel: Bool = false
    ) {
        self.classification = classification
        self.status = status
        self.source = source
        self.suggestsEscalation = suggestsEscalation
        self.skippedModel = skippedModel
    }
}
