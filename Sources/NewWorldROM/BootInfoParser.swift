import Foundation

enum BootInfoParser {
    private static let constantPattern = try! NSRegularExpression(
        pattern: #"h#\s+([A-Fa-f0-9]+)\s+constant\s+([-\w]+)"#,
        options: []
    )

    static func parse(
        _ data: Data,
        name: String,
        id: String,
        containerOffset: Int?,
        resourceFork: Data?
    ) throws -> ROMNode {
        guard isBootInfo(data) else { throw ROMParseError.unrecognizedFormat }

        let constants = parseConstants(data)
        let elfOffset = constants["elf-offset"]
        let elfSize = constants["elf-size"]
        let payloadOffset = constants["parcels-offset"] ?? constants["lzss-offset"]
        let payloadSize = constants["parcels-size"] ?? constants["lzss-size"]

        let scriptEnd = elfOffset ?? payloadOffset ?? min(data.count, 0x5000)
        let bootscriptData = try BinaryCursor.slice(data, offset: 0, count: scriptEnd, context: "bootscript")
        let bootscriptText = normalizedBootscript(bootscriptData)

        var children: [ROMNode] = [
            ROMNode(
                id: id + "/Bootscript",
                name: "Bootscript",
                kind: .text,
                data: bootscriptData,
                text: bootscriptText,
                containerOffset: containerOffset,
                metadata: constants.mapValues { BinaryCursor.hex($0) }
            )
        ]

        if let elfOffset, let elfSize, elfSize > 0 {
            let elf = try BinaryCursor.slice(data, offset: elfOffset, count: elfSize, context: "MacOS.elf")
            children.append(
                ROMDispatcher.parse(
                    elf,
                    name: "MacOS.elf",
                    id: id + "/MacOS.elf",
                    containerOffset: (containerOffset ?? 0) + elfOffset,
                    resourceFork: nil
                )
            )
        }

        if let payloadOffset, let payloadSize, payloadSize > 0 {
            var payload = try BinaryCursor.slice(
                data,
                offset: payloadOffset,
                count: payloadSize,
                context: "payload"
            )
            let payloadFileOffset = (containerOffset ?? 0) + payloadOffset
            if payload.starts(withASCII: "prcl") {
                children.append(
                    try ParcelParser.parse(
                        payload,
                        name: "Parcels",
                        id: id + "/Parcels",
                        containerOffset: payloadFileOffset
                    )
                )
            } else {
                payload = LZSSDecoder.decompress(payload)
                children.append(
                    ROMDispatcher.parse(
                        payload,
                        name: "MacROM",
                        id: id + "/MacROM",
                        containerOffset: payloadFileOffset,
                        resourceFork: nil
                    )
                )
            }
        }

        var warnings: [String] = []
        if let resourceFork, !resourceFork.isEmpty {
            if let enabler = SysEnablerExtractor.extract(dataFork: data, resourceFork: resourceFork) {
                children.append(
                    ROMDispatcher.parse(
                        enabler.data,
                        name: "SysEnabler",
                        id: id + "/SysEnabler",
                        containerOffset: enabler.start,
                        resourceFork: nil
                    )
                )
                if !enabler.resources.isEmpty {
                    children.append(
                        ROMNode(
                            id: id + "/SysEnabler.rdump",
                            name: "SysEnabler resources",
                            kind: .folder,
                            data: resourceFork,
                            text: enabler.listing,
                            containerOffset: nil,
                            children: enabler.resources
                        )
                    )
                }
            } else {
                warnings.append("Resource fork is present but no SysEnabler cfrg range was found.")
            }
        }

        var metadata = constants.mapValues { BinaryCursor.hex($0) }
        if !warnings.isEmpty {
            metadata["warnings"] = warnings.joined(separator: "\n")
        }

        let summary = """
        NewWorld bootinfo
        Size: \(data.count) bytes
        \(constants.keys.sorted().map { "\($0) = \(BinaryCursor.hex(constants[$0]!))" }.joined(separator: "\n"))
        """

        return ROMNode(
            id: id,
            name: name,
            kind: .folder,
            data: data,
            text: summary,
            containerOffset: containerOffset,
            children: children,
            metadata: metadata
        )
    }

    static func isBootInfo(_ data: Data) -> Bool {
        if data.starts(withASCII: "<CHRP-BOOT>") { return true }
        if data.count >= 11, data.prefix(11).allSatisfy({ $0 == 0x20 }) { return true }
        let sample = BinaryCursor.macRoman(data.prefix(min(data.count, 0x5000)))
        return sample.contains("constant elf-offset")
            || sample.contains("constant parcels-offset")
            || sample.contains("constant lzss-offset")
    }

    static func parseConstants(_ data: Data) -> [String: Int] {
        let sampleCount = min(data.count, 0x8000)
        let sample = BinaryCursor.macRoman(data.prefix(sampleCount)).replacingOccurrences(of: "\r", with: "\n")
        let range = NSRange(sample.startIndex..., in: sample)
        var constants: [String: Int] = [:]
        constantPattern.enumerateMatches(in: sample, options: [], range: range) { match, _, _ in
            guard let match,
                  let hexRange = Range(match.range(at: 1), in: sample),
                  let nameRange = Range(match.range(at: 2), in: sample),
                  let value = Int(sample[hexRange], radix: 16)
            else { return }
            constants[String(sample[nameRange])] = value
        }
        return constants
    }

    private static func normalizedBootscript(_ data: Data) -> String {
        var bytes = data
        while bytes.last == 0 { bytes.removeLast() }
        return BinaryCursor.macRoman(bytes).replacingOccurrences(of: "\r", with: "\n")
    }
}
