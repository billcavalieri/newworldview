import Foundation
import Testing
@testable import NewWorldROM

@Suite("Toast catalog lookup")
struct ToastCatalogLookupTests {
    private struct ListEnvelope: Decodable {
        var ok: Bool
        var command: String
        var data: [ToastCatalogLookup.CatalogEntry]?
    }

    private struct GetEnvelope: Decodable {
        var ok: Bool
        var command: String
        var data: ToastCatalogLookup.GetResult?
    }

    @Test("ResViewer JSON envelope decodes ls entries")
    func envelopeListDecode() throws {
        let json = """
        {"ok":true,"schema":1,"command":"ls","data":[{"path":"Mac OS 9.2.1/Mac OS Install","name":"Mac OS Install","isDirectory":false,"type":"APPL","creator":"????","dataSize":100,"resourceSize":200,"role":"g3Upgrader"}]}
        """
        let envelope = try JSONDecoder().decode(ListEnvelope.self, from: Data(json.utf8))
        #expect(envelope.ok)
        #expect(envelope.command == "ls")
        #expect(envelope.data?.count == 1)
        #expect(envelope.data?.first?.role == "g3Upgrader")
    }

    @Test("ResViewer JSON envelope decodes get payload")
    func envelopeGetDecode() throws {
        let json = """
        {"ok":true,"schema":1,"command":"get","data":{"path":"Mac OS 9.2.1/Mac OS Install","type":"DLOG","id":510,"name":"Splash","size":128,"dlog":{"bounds":{"top":0,"left":0,"bottom":266,"right":354},"procID":0,"visible":true,"goAway":false,"refCon":0,"itemsID":0,"title":"Welcome"}}}
        """
        let envelope = try JSONDecoder().decode(GetEnvelope.self, from: Data(json.utf8))
        #expect(envelope.ok)
        #expect(envelope.data?.type == "DLOG")
        #expect(envelope.data?.id == 510)
        #expect(envelope.data?.dlog?.bounds.width == 354)
        #expect(envelope.data?.dlog?.bounds.height == 266)
    }

    @Test("millContextLines includes ResViewer hint when CLI missing")
    func millContextWithoutCLI() {
        let lines = ToastCatalogLookup.millContextLines(
            launchA9F2: true,
            loadSeg66: true,
            client: nil
        )
        #expect(lines.contains { $0.contains("ResViewerCLI") || $0.contains("Toast catalog unavailable") })
        #expect(lines.contains { $0.contains("Launch A9F2") || $0.contains("CFM Upgrader") })
    }

    @Test("resolveConfiguration prefers explicit paths")
    func resolveExplicit() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let cliURL = directory.appendingPathComponent("ResViewerCLI")
        let toastURL = directory.appendingPathComponent("Mac OS 9.2.1.toast")
        FileManager.default.createFile(atPath: cliURL.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        FileManager.default.createFile(atPath: toastURL.path, contents: Data([0]))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cliURL.path)

        let config = ToastCatalogLookup.resolveConfiguration(cliURL: cliURL, toastImageURL: toastURL)
        #expect(config?.cliURL.path == cliURL.path)
        #expect(config?.toastImageURL.path == toastURL.path)
    }
}
