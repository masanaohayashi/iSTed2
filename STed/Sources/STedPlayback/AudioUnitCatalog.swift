import AudioToolbox
import AVFoundation
import Foundation

public enum AudioUnitCatalog {
    public static let displayName = "SC-55 (Rin2)"

    public struct ListedComponent: Equatable, Sendable {
        public var name: String
        public var type: OSType
        public var subtype: OSType
        public var manufacturer: OSType

        public init(
            name: String,
            type: OSType,
            subtype: OSType,
            manufacturer: OSType,
            flags: UInt32 = 0
        ) {
            self.name = name
            self.type = type
            self.subtype = subtype
            self.manufacturer = manufacturer
            self.flags = flags
        }

        public var flags: UInt32 = 0

        public var audioComponentDescription: AudioComponentDescription {
            AudioComponentDescription(
                componentType: type,
                componentSubType: subtype,
                componentManufacturer: manufacturer,
                componentFlags: flags,
                componentFlagsMask: 0
            )
        }
    }

    public static var sc55Description: AudioComponentDescription {
        description(subtype: "Sc55")
    }

    public static var candidateDescriptions: [AudioComponentDescription] {
        [description(subtype: "Sc55"), description(subtype: "SC55")]
    }

    public static func description(subtype: String) -> AudioComponentDescription {
        AudioComponentDescription(
            componentType: fourCC("aumu"),
            componentSubType: fourCC(subtype),
            componentManufacturer: fourCC("Rin2"),
            componentFlags: 0,
            componentFlagsMask: 0
        )
    }

    public static func fourCC(_ code: String) -> OSType {
        var result: OSType = 0
        for byte in code.utf8.prefix(4) {
            result = (result << 8) | OSType(byte)
        }
        return result
    }

    public static func fourCCString(_ value: OSType) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8(value & 0xff)
        ]
        if let text = String(bytes: bytes, encoding: .ascii),
           text.unicodeScalars.allSatisfy({ $0.isASCII && $0.value >= 32 && $0.value < 127 })
        {
            return text
        }
        return String(format: "%08X", value)
    }

    public static func listedAUMU() -> [ListedComponent] {
        let aumu = fourCC("aumu")
        var found: [ListedComponent] = []
        var seen = Set<String>()

        func add(_ item: ListedComponent) {
            let key = "\(item.subtype)-\(item.manufacturer)-\(item.name)"
            if seen.insert(key).inserted {
                found.append(item)
            }
        }

        let fromManager = AVAudioUnitComponentManager.shared().components(passingTest: { component, _ in
            component.audioComponentDescription.componentType == aumu
        })
        for component in fromManager {
            add(listed(from: component))
        }

        var query = AudioComponentDescription(
            componentType: aumu,
            componentSubType: 0,
            componentManufacturer: 0,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        var component = AudioComponentFindNext(nil, &query)
        while let current = component {
            var description = AudioComponentDescription()
            AudioComponentGetDescription(current, &description)
            var name: Unmanaged<CFString>?
            AudioComponentCopyName(current, &name)
            add(
                ListedComponent(
                    name: name?.takeRetainedValue() as String? ?? "",
                    type: description.componentType,
                    subtype: description.componentSubType,
                    manufacturer: description.componentManufacturer,
                    flags: description.componentFlags
                )
            )
            component = AudioComponentFindNext(current, &query)
        }

        return found.sorted { lhs, rhs in
            if lhs.manufacturer != rhs.manufacturer {
                return fourCCString(lhs.manufacturer) < fourCCString(rhs.manufacturer)
            }
            return fourCCString(lhs.subtype) < fourCCString(rhs.subtype)
        }
    }

    public static func logAvailableAUMU() {
        let items = listedAUMU()
        NSLog("[STed] available aumu count=%d", items.count)
        let onlyApple = items.allSatisfy { $0.manufacturer == fourCC("appl") }
        if onlyApple {
            NSLog("[STed] only Apple aumu visible; iOS needs Inter-App Audio entitlement to see third-party AUv3")
        }
        if items.isEmpty {
            NSLog("[STed] aumu (none)")
            return
        }
        for item in items {
            NSLog(
                "[STed] aumu %@ %@  -  %@",
                fourCCString(item.subtype),
                fourCCString(item.manufacturer),
                item.name
            )
        }
    }

    public static func matchSC55(among components: [ListedComponent]) -> ListedComponent? {
        let aumu = fourCC("aumu")
        let rin2 = fourCC("Rin2")
        let subtypes: Set<OSType> = [fourCC("Sc55"), fourCC("SC55")]
        if let exact = components.first(where: {
            $0.type == aumu && $0.manufacturer == rin2 && subtypes.contains($0.subtype)
        }) {
            return exact
        }
        return components.first { component in
            guard component.manufacturer == rin2 || component.type == aumu else { return false }
            let name = component.name.lowercased()
            return name.contains("sc-55") || name.contains("sc55")
        }
    }

    public static func listedInstruments() -> [ListedComponent] {
        let manager = AVAudioUnitComponentManager.shared()
        let fromScan = manager.components(passingTest: { component, _ in
            let description = component.audioComponentDescription
            if description.componentManufacturer == fourCC("Rin2") {
                return true
            }
            let name = component.name.lowercased()
            return name.contains("sc-55") || name.contains("sc55")
        }).map(listed(from:))
        if matchSC55(among: fromScan) != nil {
            return fromScan
        }

        for var query in candidateDescriptions {
            if let current = AudioComponentFindNext(nil, &query) {
                var description = AudioComponentDescription()
                AudioComponentGetDescription(current, &description)
                var name: Unmanaged<CFString>?
                AudioComponentCopyName(current, &name)
                return [
                    ListedComponent(
                        name: name?.takeRetainedValue() as String? ?? displayName,
                        type: description.componentType,
                        subtype: description.componentSubType,
                        manufacturer: description.componentManufacturer,
                        flags: description.componentFlags
                    )
                ]
            }
        }
        return fromScan
    }

    private static func listed(from component: AVAudioUnitComponent) -> ListedComponent {
        let description = component.audioComponentDescription
        return ListedComponent(
            name: component.name,
            type: description.componentType,
            subtype: description.componentSubType,
            manufacturer: description.componentManufacturer,
            flags: description.componentFlags
        )
    }

    public static func resolveSC55() -> ListedComponent? {
        matchSC55(among: listedInstruments())
    }

    public static func isInstalled(_ description: AudioComponentDescription = sc55Description) -> Bool {
        resolveSC55() != nil || {
            var description = description
            return AudioComponentFindNext(nil, &description) != nil
        }()
    }
}

public enum AudioUnitAdapterError: Error, LocalizedError, Equatable {
    case componentNotFound(type: String, subtype: String, manufacturer: String)
    case instantiationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .componentNotFound(let type, let subtype, let manufacturer):
            return "AudioUnit \(type) \(subtype) \(manufacturer) が見つからない"
        case .instantiationFailed(let message):
            return "AudioUnit を開けない: \(message)"
        }
    }
}
