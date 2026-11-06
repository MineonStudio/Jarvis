import Foundation

struct HomeMacSystemInfo: Sendable {
    var modelName: String
    var modelIdentifier: String
    var chip: String
    var memory: String
    var systemVersion: String
    var storageBytes: UInt64?
    var storageMedium: String?
    var modelNumber: String?

    var modelYear: String? {
        HomeMacModelYear.label(identifier: modelIdentifier, modelNumber: modelNumber)
    }

    static var fallback: Self {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return Self(
            modelName: "Mac", modelIdentifier: HomeSystemSampler.systemString("hw.model") ?? "Mac",
            chip: HomeSystemSampler.systemString("machdep.cpu.brand_string") ?? "Mac",
            memory: ByteCountFormatter.string(fromByteCount: Int64(clamping: ProcessInfo.processInfo.physicalMemory), countStyle: .memory),
            systemVersion: "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        )
    }

    static func parse(_ data: Data) throws -> Self {
        let report = try JSONDecoder().decode(Report.self, from: data)
        var value = fallback
        if let hardware = report.SPHardwareDataType?.first {
            value.modelName = hardware.machine_name ?? value.modelName
            value.modelIdentifier = hardware.machine_model ?? value.modelIdentifier
            value.modelNumber = hardware.model_number
            value.chip = hardware.chip_type ?? hardware.cpu_type ?? value.chip
            value.memory = hardware.physical_memory ?? value.memory
        }
        value.systemVersion = report.SPSoftwareDataType?.first?.os_version ?? value.systemVersion
        let startup = report.SPStorageDataType?.first { $0.mount_point == "/" }
            ?? report.SPStorageDataType?.first { $0.mount_point == "/System/Volumes/Data" }
        value.storageBytes = startup?.size_in_bytes
        value.storageMedium = startup?.physical_drive?.medium_type
        if let name = startup?.physical_drive?.device_name {
            /// Use only the startup drive, never sum attached or external devices.
            func find(_ nodes: [Drive]) -> Drive? {
                for node in nodes {
                    if node.device_model == name || node._name == name, node.size_in_bytes != nil {
                        return node
                    }
                    if let match = find(node._items ?? []) {
                        return match
                    }
                }
                return nil
            }
            if let physical = find(report.SPNVMeDataType ?? []) {
                value.storageBytes = physical.size_in_bytes
            }
        }
        return value
    }

    private struct Report: Decodable {
        var SPHardwareDataType: [Hardware]?
        var SPSoftwareDataType: [Software]?
        var SPStorageDataType: [Storage]?
        var SPNVMeDataType: [Drive]?
    }

    private struct Hardware: Decodable {
        var machine_name: String?
        var machine_model: String?
        var model_number: String?
        var chip_type: String?
        var cpu_type: String?
        var physical_memory: String?
    }

    private struct Software: Decodable { var os_version: String? }
    private struct Storage: Decodable {
        var mount_point: String?
        var size_in_bytes: UInt64?
        var physical_drive: PhysicalDrive?
    }

    private struct PhysicalDrive: Decodable {
        var device_name: String?
        var medium_type: String?
    }

    private struct Drive: Decodable {
        var _name: String?
        var device_model: String?
        var size_in_bytes: UInt64?
        var _items: [Drive]?
    }
}

/// System Information's report, loaded off the UI actor and cached for this launch.
actor HomeMacSystemInfoReader {
    static let shared = HomeMacSystemInfoReader()
    private var cached: HomeMacSystemInfo?

    func read() -> HomeMacSystemInfo {
        if let cached {
            return cached
        }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPHardwareDataType", "SPSoftwareDataType", "SPStorageDataType", "SPNVMeDataType", "-json"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return .fallback }
            let info = try HomeMacSystemInfo.parse(data)
            cached = info
            return info
        } catch {
            return .fallback
        }
    }
}
