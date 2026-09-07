import Combine
import Foundation
import NewWorldROM

@MainActor
final class MillAnnotationStore: ObservableObject {
    @Published private(set) var annotations: [MillAnnotation] = []

    private let romKey: String

    var romKeyForExport: String { romKey }

    private var storageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("NewWorldView", isDirectory: true)
            .appendingPathComponent("mill-annotations-\(romKey).json")
    }

    init(romKey: String) {
        self.romKey = romKey
        load()
    }

    func upsert(_ annotation: MillAnnotation) {
        if let index = annotations.firstIndex(where: { $0.address.key == annotation.address.key }) {
            annotations[index] = annotation
        } else {
            annotations.insert(annotation, at: 0)
        }
        save()
    }

    func annotation(for address: ProgramAddress) -> MillAnnotation? {
        annotations.first { $0.address.key == address.key }
    }

    func approve(id: UUID, reachability: MillReachabilityReport) -> Bool {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return false }
        var annotation = annotations[index]
        guard MillSafetyVerifier.allowsApprovedSkipCandidate(annotation, reachability: reachability) else {
            return false
        }
        annotation.status = .approved
        annotation.reviewedAt = Date()
        annotations[index] = annotation
        save()
        return true
    }

    func reject(id: UUID) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else { return }
        annotations[index].status = .rejected
        annotations[index].reviewedAt = Date()
        save()
    }

    func filtered(status: AnnotationStatus?) -> [MillAnnotation] {
        guard let status else { return annotations }
        return annotations.filter { $0.status == status }
    }

    func exportApproved(to directory: URL) throws -> URL {
        try MillAnnotationExport.write(romKey: romKey, annotations: annotations, to: directory)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL)
        else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode([MillAnnotation].self, from: data) else { return }
        annotations = decoded
    }

    private func save() {
        let directory = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(annotations) else { return }
        try? data.write(to: storageURL, options: .atomic)
    }
}
