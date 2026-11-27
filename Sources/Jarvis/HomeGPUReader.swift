import Foundation
import IOKit

/// Reads driver-published GPU usage without launching a command or requesting
/// elevated privileges. Used only from HomeSystemSampler's background actor.
struct HomeGPUReader {
    func read() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }
        var usages: [Double] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            let property = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)
            IOObjectRelease(service)
            guard let statistics = property?.takeRetainedValue() as? [String: Any],
                  let usage = Self.fraction(from: statistics) else { continue }
            usages.append(usage)
        }
        // Do not sum independent GPU percentages on multi-GPU Macs.
        return usages.max()
    }

    static func fraction(from statistics: [String: Any]) -> Double? {
        for key in ["Device Utilization %", "GPU Activity(%)"] {
            guard let number = statistics[key] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() else { continue }
            let percent = number.doubleValue
            guard percent.isFinite, (0 ... 100).contains(percent) else { continue }
            return percent / 100
        }
        return nil
    }
}
