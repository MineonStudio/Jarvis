import Foundation
import IOKit

struct HomeTemperatures: Equatable, Sendable {
    var cpu: Double?
    var gpu: Double?
}

/// Read-only SMC access, confined to HomeSystemSampler's actor. Temperature
/// sensor keys vary by chip; unknown hardware reports unavailable readings.
final class HomeTemperatureReader {
    private struct Sensor {
        let key: UInt32
        let size: UInt32
        let type: UInt32
    }

    private var connection: io_connect_t = 0
    private var cpuSensors: [Sensor] = []
    private var gpuSensors: [Sensor] = []

    init() {
        let chip = HomeSystemSampler.systemString("machdep.cpu.brand_string") ?? ""
        let keys = Self.sensorKeys(for: chip)
        guard !keys.cpu.isEmpty || !keys.gpu.isEmpty else { return }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else {
            connection = 0
            return
        }
        cpuSensors = keys.cpu.compactMap(sensor)
        gpuSensors = keys.gpu.compactMap(sensor)
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
        }
    }

    func read() -> HomeTemperatures {
        // Use the hottest available sensor in each group, not a guessed
        // package temperature or a claim about individual CPU cores.
        HomeTemperatures(
            cpu: cpuSensors.compactMap(readTemperature).max(),
            gpu: gpuSensors.compactMap(readTemperature).max()
        )
    }

    private func sensor(_ key: String) -> Sensor? {
        let code = Self.fourCC(key)
        guard let info = call(key: code, command: 9) else { return nil }
        let size = Self.uint32(info, at: 28)
        let type = Self.uint32(info, at: 32)
        guard (type == Self.fourCC("flt ") && size == 4)
            || (type == Self.fourCC("sp78") && size == 2) else { return nil }
        return Sensor(key: code, size: size, type: type)
    }

    private func readTemperature(_ sensor: Sensor) -> Double? {
        guard let data = call(key: sensor.key, command: 5, size: sensor.size) else { return nil }
        return Self.decodeTemperature(type: sensor.type, bytes: Array(data[48 ..< 48 + Int(sensor.size)]))
    }

    private func call(key: UInt32, command: UInt8, size: UInt32 = 0) -> [UInt8]? {
        guard connection != 0 else { return nil }
        // AppleSMC's 80-byte user-client ABI: key at 0, key info at 28,
        // result at 40, read command at 42, and the 32-byte payload at 48.
        // Only read-key-info (9) and read-bytes (5) are used here.
        var input = [UInt8](repeating: 0, count: 80)
        var output = [UInt8](repeating: 0, count: 80)
        for index in 0 ..< 4 {
            input[index] = UInt8(truncatingIfNeeded: key >> (index * 8))
            input[28 + index] = UInt8(truncatingIfNeeded: size >> (index * 8))
        }
        input[42] = command
        var outputSize = 80
        let status = input.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                IOConnectCallStructMethod(connection, 2, source.baseAddress, 80, destination.baseAddress, &outputSize)
            }
        }
        guard status == KERN_SUCCESS, outputSize == 80, output[40] == 0 else { return nil }
        return output
    }

    static func decodeTemperature(type: UInt32, bytes: [UInt8]) -> Double? {
        let value: Double
        switch (type, bytes.count) {
        case (fourCC("flt "), 4):
            value = Double(Float(bitPattern: uint32(bytes, at: 0)))
        case (fourCC("sp78"), 2):
            value = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        default:
            return nil
        }
        guard value.isFinite, value > 0, value <= 150 else { return nil }
        return value
    }

    static func fourCC(_ value: String) -> UInt32 {
        value.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func uint32(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0 ..< 4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << ($1 * 8) }
    }

    /// Sensor groups follow the per-generation mappings in Stats:
    /// https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift
    static func sensorKeys(for chip: String) -> (cpu: [String], gpu: [String]) {
        let generation = chip.split(separator: " ").prefix(2).joined(separator: " ")
        if generation == "Apple M4" {
            let gpu = chip.contains("Pro") || chip.contains("Max") ? ["Tg1U", "Tg1k"] : ["Tg0G", "Tg0H"]
            return (
                ["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"],
                gpu + ["Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"]
            )
        }
        if generation == "Apple M3" {
            return (
                ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"],
                ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"]
            )
        }
        if generation == "Apple M2" {
            return (
                ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"],
                ["Tg0f", "Tg0j"]
            )
        }
        if generation == "Apple M1" {
            return (
                ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"],
                ["Tg05", "Tg0D", "Tg0L", "Tg0T"]
            )
        }
        if chip.contains("Intel") {
            return (["TC0D", "TC0E", "TC0F", "TC0P", "TCAD"], ["TG0D", "TGDD"])
        }
        return ([], [])
    }
}
