import Foundation

struct SharedFileImportSummary {
    var importedNames: [String] = []
    var failedNames: [String] = []
}

actor SharedFileImporter {
    func importFiles(_ urls: [URL], into directory: URL, maxBytes: Int64) -> SharedFileImportSummary {
        let fileManager = FileManager.default
        var summary = SharedFileImportSummary()
        for url in urls {
            let name = url.lastPathComponent
            let hasScopedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if hasScopedAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                guard !name.isEmpty, name != ".", name != "..", !name.hasPrefix("."),
                      !name.contains("\\"),
                      name.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value != 127 })
                else { throw ImportError.invalidFile }
                let values = try url.resourceValues(forKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
                ])
                guard values.isRegularFile == true, values.isSymbolicLink != true,
                      let size = values.fileSize
                else { throw ImportError.invalidFile }
                guard Int64(size) <= maxBytes else { throw ImportError.tooLarge }

                let destination = uniqueDestination(for: name, in: directory, fileManager: fileManager)
                let temporary = directory.appendingPathComponent(".lan-import-\(UUID().uuidString).part")
                do {
                    try fileManager.copyItem(at: url, to: temporary)
                    let copiedSize = try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize
                    guard let copiedSize, Int64(copiedSize) <= maxBytes else {
                        throw ImportError.tooLarge
                    }
                    try fileManager.moveItem(at: temporary, to: destination)
                } catch {
                    try? fileManager.removeItem(at: temporary)
                    throw error
                }
                summary.importedNames.append(destination.lastPathComponent)
            } catch {
                summary.failedNames.append("\(name)：\(error.localizedDescription)")
            }
        }
        return summary
    }

    private func uniqueDestination(for name: String, in directory: URL, fileManager: FileManager) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var destination = directory.appendingPathComponent(name)
        var index = 1
        while fileManager.fileExists(atPath: destination.path) {
            let suffix = "\(base)(\(index))" + (ext.isEmpty ? "" : ".\(ext)")
            destination = directory.appendingPathComponent(suffix)
            index += 1
        }
        return destination
    }

    private enum ImportError: LocalizedError {
        case invalidFile
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .invalidFile: "只支持普通文件，且文件名不能以点开头。"
            case .tooLarge: "单文件不能超过 2 GB。"
            }
        }
    }
}
