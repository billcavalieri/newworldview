import Foundation
import Testing
@testable import NewWorldROM

@Suite("G3 PEF plant map")
struct G3PEFPlantMapTests {
    @Test("maps code entry PC")
    func codeEntry() throws {
        let location = try #require(G3PEFPlantMap.map(G3PEFPlantMap.codeEntryPC))
        #expect(location.section == "code")
        #expect(location.sectionOffset == 0)
    }

    @Test("maps toast data fork offset at plant base")
    func toastFileOffset() throws {
        let location = try #require(G3PEFPlantMap.map(G3PEFPlantMap.plantBase))
        #expect(location.section == "pef-file")
        #expect(location.toastFileOffset == G3PEFPlantMap.toastDataForkOffset)
    }

    @Test("maps DSI DAR in data section")
    func dataSectionFault() {
        let dar: UInt64 = G3PEFPlantMap.plantBase + G3PEFPlantMap.dataSectionOffset + 0x18
        let text = G3PEFPlantMap.describeFault(
            srr0: G3PEFPlantMap.plantBase + 0xb428,
            dar: dar
        )
        #expect(text.contains("PEF data+0x18"))
        #expect(text.contains("SRR0"))
    }
}

@Suite("G3 PEF mill stamps")
struct G3PEFMillStampTests {
    @Test("records import wait dce vol and hosted DSI")
    func stampCounts() {
        var events = G3MillClassification.EventCounts()
        events.record(line: "G3: 68k Launch A9F2 CFM Upgrader PEF enter pc=101013d0 toc=10115000")
        events.record(line: "G3: 68k Launch A9F2 CFM Upgrader PEF import idx=1 r3=10115c5e")
        events.record(line: "G3: 68k Launch A9F2 CFM Upgrader PEF vol idx=70 r3=00000000")
        events.record(line: "G3: 68k Launch A9F2 CFM Upgrader PEF dce h=10180040")
        events.record(line: "G3: 68k Launch A9F2 CFM Upgrader PEF WaitNextEvent idx=149 r3=00000001")
        events.record(line: "G3: DSI n=3 SRR0=1010b428 DAR=00015018")
        #expect(events.pefEnterCount == 1)
        #expect(events.pefImportCount == 1)
        #expect(events.pefVolCount == 1)
        #expect(events.pefDceCount == 1)
        #expect(events.pefWaitNextEventCount == 1)
        #expect(events.pefHostedDSICount == 1)
        #expect(events.pefPhase == .waitNextEvent)
        #expect(!events.hostedLocationSamples.isEmpty)
    }

    @Test("excludes host Splash 510 even dlg from splash count")
    func hostSplashExcluded() {
        var events = G3MillClassification.EventCounts()
        events.record(line: "G3: 68k GetNewDialog A97C Splash 510 even dlg=1005130c")
        events.record(line: "G3: 68k GetNewDialog A97C toast id=510 dlg=1005130c pc=1010b428")
        #expect(events.getNewDialogSplashHits == 1)
    }

    @Test("wait phase recommendation does not re-tip KEEP 16527 imports")
    func waitRecommendation() throws {
        let lines = G3MillClassification.recommendationLines(
            launchA9F2Logs: 1,
            launchA9F2Count: 1,
            pefEnterCount: 1,
            pefImportCount: 3,
            pefVolCount: 1,
            pefDceCount: 1,
            pefWaitNextEventCount: 1,
            pefHostedDSICount: 1,
            hostedLocationSamples: ["DSI SRR0 → PEF code+0x58"]
        )
        let line = try #require(lines.first)
        #expect(line.contains("WaitNextEvent"))
        #expect(line.contains("16527") || line.contains("16533"))
        #expect(!line.contains("escalate InterfaceLib host stubs"))
    }
}
