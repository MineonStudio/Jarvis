import Darwin
import Foundation
import Observation

struct HomeSystemSnapshot: Sendable {
    var cpu: Double?
    var memoryUsed: UInt64?
    var memoryTotal: UInt64 = ProcessInfo.processInfo.physicalMemory
    var upload: Double?
    var download: Double?
    var diskAvailable: UInt64?
    var diskTotal: UInt64?
    var uptime: TimeInterval = ProcessInfo.processInfo.systemUptime

    var memoryFraction: Double? {
        guard let memoryUsed, memoryTotal > 0 else { return nil }
        return min(1, Double(memoryUsed) / Double(memoryTotal))
    }

    var diskFraction: Double? {
        guard let diskAvailable, let diskTotal, diskTotal > 0 else { return nil }
        return min(1, max(0, 1 - Double(diskAvailable) / Double(diskTotal)))
    }
}

@Observable @MainActor
final class HomeSystemMonitor {
    var snapshot = HomeSystemSnapshot()
    var identity = HomeNetworkDisplay.empty
    var cpuHistory: [Double] = []
    var memoryHistory: [Double] = []
    var networkHistory: [Double] = []
    var diskHistory: [Double] = []
    let deviceName = Host.current().localizedName ?? "我的 Mac"
    var macInfo = HomeMacSystemInfo.fallback
    private let egress = HomeNetworkEgressEngine()

    /// The view owns this task; leaving Home or deactivating the scene cancels it.
    func run() async {
        let info = await HomeMacSystemInfoReader.shared.read()
        guard !Task.isCancelled else { return }
        macInfo = info
        egress.onUpdate = { [weak self] next in
            self?.identity = next
        }
        async let sampling: Void = sampleLoop()
        async let egressing: Void = egress.run()
        _ = await (sampling, egressing)
    }

    private func sampleLoop() async {
        let sampler = HomeSystemSampler()
        while !Task.isCancelled {
            let next = await sampler.sample()
            guard !Task.isCancelled else { return }
            snapshot = next
            append(next.cpu, to: &cpuHistory)
            append(next.memoryFraction, to: &memoryHistory)
            append(next.diskFraction, to: &diskHistory)
            append(next.download.map { $0 + (next.upload ?? 0) }, to: &networkHistory)
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
        }
    }

    private func append(_ value: Double?, to values: inout [Double]) {
        guard let value else { return }
        values.append(value)
        if values.count > 30 {
            values.removeFirst(values.count - 30)
        }
    }
}

actor HomeSystemSampler {
    private var previousCPU: [UInt32]?
    private var previousNetwork: (received: UInt64, sent: UInt64, time: TimeInterval)?
    private var lastDiskRead = Date.distantPast
    private var disk: (available: UInt64?, total: UInt64?) = (nil, nil)

    func sample() -> HomeSystemSnapshot {
        var result = HomeSystemSnapshot()
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var cpu = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let status = withUnsafeMutablePointer(to: &cpu) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(host, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if status == KERN_SUCCESS {
            let ticks = [cpu.cpu_ticks.0, cpu.cpu_ticks.1, cpu.cpu_ticks.2, cpu.cpu_ticks.3]
            if let previousCPU {
                result.cpu = Self.cpuFraction(previous: previousCPU, current: ticks)
            }
            previousCPU = ticks
        }
        var memory = vm_statistics64()
        var memoryCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let memoryStatus = withUnsafeMutablePointer(to: &memory) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(memoryCount)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &memoryCount)
            }
        }
        var pageSize: vm_size_t = 0
        if memoryStatus == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS {
            // Active, wired and compressed pages; inactive pages can be reclaimed.
            let pages = UInt64(memory.active_count) + UInt64(memory.wire_count) + UInt64(memory.compressor_page_count)
            result.memoryUsed = min(result.memoryTotal, pages * UInt64(pageSize))
        }
        if let counters = Self.networkCounters() {
            let time = ProcessInfo.processInfo.systemUptime
            if let old = previousNetwork {
                result.download = Self.rate(
                    previous: old.received, current: counters.received, elapsed: time - old.time
                )
                result.upload = Self.rate(previous: old.sent, current: counters.sent, elapsed: time - old.time)
            }
            previousNetwork = (counters.received, counters.sent, time)
        } else {
            previousNetwork = nil
        }
        if Date().timeIntervalSince(lastDiskRead) >= 30 {
            let values = try? URL(fileURLWithPath: NSHomeDirectory()).resourceValues(
                forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
            )
            disk = (
                values?.volumeAvailableCapacityForImportantUsage.map { UInt64(max(0, $0)) },
                values?.volumeTotalCapacity.map { UInt64(max(0, $0)) }
            )
            lastDiskRead = Date()
        }
        result.diskAvailable = disk.available
        result.diskTotal = disk.total
        return result
    }

    nonisolated static func cpuFraction(previous: [UInt32], current: [UInt32]) -> Double? {
        guard previous.count == 4, current.count == 4 else { return nil }
        let delta = zip(previous, current).map { UInt64($1 &- $0) }
        let total = delta.reduce(0, +)
        guard total > 0 else { return nil }
        return min(1, max(0, 1 - Double(delta[Int(CPU_STATE_IDLE)]) / Double(total)))
    }

    nonisolated static func rate(previous: UInt64, current: UInt64, elapsed: TimeInterval) -> Double? {
        guard elapsed > 0, current >= previous else { return nil }
        return Double(current - previous) / elapsed
    }

    private static func networkCounters() -> (received: UInt64, sent: UInt64)? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var found = false
        while let current = pointer {
            let item = current.pointee
            defer { pointer = item.ifa_next }
            guard let address = item.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK,
                  item.ifa_flags & UInt32(IFF_UP) != 0,
                  String(cString: item.ifa_name).hasPrefix("en"), let data = item.ifa_data
            else { continue }
            let counters = data.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(counters.ifi_ibytes)
            sent += UInt64(counters.ifi_obytes)
            found = true
        }
        return found ? (received, sent) : nil
    }

    nonisolated static func systemString(_ key: String) -> String? {
        var size = 0
        guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 1 else { return nil }
        var bytes = [CChar](repeating: 0, count: size)
        guard sysctlbyname(key, &bytes, &size, nil, 0) == 0 else { return nil }
        return String(bytes: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }
}
