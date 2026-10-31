import AppKit
import CoreServices
import CryptoKit
import Foundation
import Security

enum JarvisAppVersion {
    private static let fallbackShortVersion = "1.9.0"
    private static let fallbackBuild = "383"

    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? fallbackShortVersion
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? fallbackBuild
    }

    static var displayName: String {
        "v\(shortVersion) (构建 \(build))"
    }
}

struct JarvisReleaseInfo: Equatable {
    let version: String
    let build: String?
    let releaseURL: URL
    let downloadURL: URL
    let manifestURL: URL
    let signatureURL: URL
    /// 应用内更新只安装这个名字对应的资产。必须等于验签后清单里的 `archiveName`。
    let archiveName: String
}

enum JarvisUpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(JarvisReleaseInfo)
    case downloading(version: String)
    case readyToInstall(version: String)
    case installing(version: String)
    case failed(message: String)
}

enum JarvisUpdateError: LocalizedError {
    case downloadUnavailable
    case invalidArchive
    case invalidApplication
    case incompatibleCodeIdentity
    case invalidManifest
    case invalidManifestSignature
    case missingSignedManifest
    case mismatchedVersion
    case unsupportedInstallLocation
    case ambiguousInstallLocation
    case unsupportedUpdateChannel
    case toolFailed(String)
    case checksumMismatch
    case notNewerRelease

    var errorDescription: String? {
        switch self {
        case .downloadUnavailable:
            "该版本没有可用的应用安装包"
        case .invalidArchive:
            "更新包格式无效"
        case .invalidApplication:
            "更新包中的工作搭子 Jarvis 应用无效"
        case .incompatibleCodeIdentity:
            "更新包的代码签名身份与当前应用不一致，已保留当前版本。请安装使用固定发布证书签名的正式包"
        case .invalidManifest:
            "更新清单无效或与发布版本不匹配"
        case .invalidManifestSignature:
            "更新清单签名校验失败，已阻止安装"
        case .missingSignedManifest:
            "该版本缺少可信更新签名，已阻止安装"
        case .mismatchedVersion:
            "更新包内的版本与发布信息不一致，已阻止安装"
        case .unsupportedInstallLocation:
            "当前应用位于只读磁盘映像或临时转移路径，无法自动更新。请先将工作搭子 Jarvis 复制到“应用程序”文件夹后重试"
        case .ambiguousInstallLocation:
            "检测到多个工作搭子 Jarvis 安装副本，无法确定要更新哪一个。请保留一个安装副本后重试"
        case .unsupportedUpdateChannel:
            "开发版不能安装正式更新。请打开已安装的工作搭子 Jarvis 后再更新"
        case let .toolFailed(message):
            "解压更新包失败：\(message)"
        case .checksumMismatch:
            "更新包校验失败，未进行安装"
        case .notNewerRelease:
            "这个版本不比当前安装更新，已阻止安装"
        }
    }
}

struct JarvisUpdateService {
    private static let manifestAssetName = "Jarvis-update-manifest.json"
    private static let signatureAssetName = "Jarvis-update-manifest.sig"
    private static let releasesURL = URL(string: "https://github.com/MineonStudio/Jarvis/releases")!
    static let updateLogURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/Jarvis/update.log")

    func checkForLatestRelease() async throws -> JarvisReleaseInfo {
        let operationID = JarvisLog.operationID()
        JarvisLog.info(
            category: .update,
            event: "release.check.begin",
            operationID: operationID
        )
        // GitHub 的 latest 下载链接不调用 REST API；签名清单负责提供可信版本与归档哈希。
        let manifest = try await latestSignedManifest(operationID: operationID)
        guard let version = JarvisUpdateSecurity.normalizedVersion(manifest.version),
              let downloadURL = Self.releaseAssetURL(version: version, name: manifest.archiveName),
              let manifestURL = Self.releaseAssetURL(version: version, name: Self.manifestAssetName),
              let signatureURL = Self.releaseAssetURL(version: version, name: Self.signatureAssetName)
        else {
            throw JarvisUpdateError.invalidManifest
        }
        let releaseInfo = JarvisReleaseInfo(
            version: version,
            build: manifest.build,
            releaseURL: Self.releasesURL.appending(path: "tag/v\(version)"),
            downloadURL: downloadURL,
            manifestURL: manifestURL,
            signatureURL: signatureURL,
            archiveName: manifest.archiveName
        )
        JarvisLog.info(
            category: .update,
            event: "release.check.complete",
            operationID: operationID,
            result: "success",
            fields: [
                "version": releaseInfo.version,
                "hasDownload": "true",
                "signedManifest": "true"
            ]
        )
        return releaseInfo
    }

    func isNewer(_ remote: String, than local: String) -> Bool {
        JarvisUpdateSecurity.isNewer(
            remoteVersion: remote,
            remoteBuild: nil,
            than: local,
            localBuild: nil
        )
    }

    func isNewer(_ release: JarvisReleaseInfo, than localVersion: String, build localBuild: String) -> Bool {
        JarvisUpdateSecurity.isNewer(
            remoteVersion: release.version,
            remoteBuild: release.build,
            than: localVersion,
            localBuild: localBuild
        )
    }

    /// Downloads, validates, and hands the update to a detached installer.
    func downloadAndInstall(_ release: JarvisReleaseInfo) async throws {
        guard !JarvisAppIdentity.isDevelopment else { throw JarvisUpdateError.unsupportedUpdateChannel }
        let operationID = JarvisLog.operationID()
        var handedOffToInstaller = false
        JarvisLog.notice(
            category: .update,
            event: "install.begin",
            operationID: operationID,
            fields: ["version": release.version]
        )
        defer {
            JarvisLog.notice(
                category: .update,
                event: "install.complete",
                operationID: operationID,
                result: handedOffToInstaller ? "handedOffToInstaller" : "failed",
                fields: ["version": release.version]
            )
        }
        // Authenticate the manifest and archive before inspecting the app.
        // Updates preserve the publisher signature and never reset privacy grants.
        let manifest = try await verifyUpdateManifest(for: release, operationID: operationID)
        guard JarvisUpdateSecurity.isNewer(
            remoteVersion: manifest.version,
            remoteBuild: manifest.build,
            than: JarvisAppVersion.shortVersion,
            localBuild: JarvisAppVersion.build
        ) else {
            throw JarvisUpdateError.notNewerRelease
        }
        guard release.archiveName == manifest.archiveName,
              release.build == manifest.build,
              release.downloadURL == Self.releaseAssetURL(version: release.version, name: manifest.archiveName)
        else {
            throw JarvisUpdateError.downloadUnavailable
        }

        let launchedAppURL = Bundle.main.bundleURL.standardizedFileURL
        guard launchedAppURL.pathExtension.lowercased() == "app",
              launchedAppURL.lastPathComponent == "Jarvis.app"
        else {
            throw JarvisUpdateError.unsupportedInstallLocation
        }
        let currentAppURL = try resolveInstallLocation(for: launchedAppURL)
        try validateInstallLocation(currentAppURL)
        cleanupStaleLaunchServices(preserving: [launchedAppURL, currentAppURL])

        let fileManager = FileManager.default
        let temporaryDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("JarvisUpdate-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporaryDirectory.path)
        defer {
            if !handedOffToInstaller {
                try? fileManager.removeItem(at: temporaryDirectory)
            }
        }

        var request = URLRequest(url: release.downloadURL)
        request.setValue("Jarvis macOS; +https://github.com/MineonStudio/Jarvis", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (downloadedURL, response) = try await updateSession.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }

        let archiveURL = temporaryDirectory.appendingPathComponent(manifest.archiveName)
        try fileManager.moveItem(at: downloadedURL, to: archiveURL)
        try validateSignedArchive(at: archiveURL, manifest: manifest)

        let extractionDirectory = temporaryDirectory.appendingPathComponent("extracted", isDirectory: true)
        try fileManager.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        try runTool(
            "/usr/bin/ditto",
            arguments: ["-x", "-k", archiveURL.path, extractionDirectory.path]
        )

        guard let newAppURL = findApplication(in: extractionDirectory),
              isValidApplicationBundle(newAppURL)
        else {
            throw JarvisUpdateError.invalidApplication
        }

        try JarvisCodeIdentity.validateUpdate(at: newAppURL, replacing: currentAppURL)
        guard Self.bundleValue("CFBundleShortVersionString", in: newAppURL) == manifest.version,
              Self.bundleValue("CFBundleVersion", in: newAppURL) == manifest.build
        else { throw JarvisUpdateError.mismatchedVersion }

        let scriptURL = temporaryDirectory.appendingPathComponent("install-update.zsh")
        try makeInstallerScript(
            at: scriptURL,
            currentAppURL: currentAppURL,
            newAppURL: newAppURL,
            temporaryDirectory: temporaryDirectory,
            parentProcessID: ProcessInfo.processInfo.processIdentifier
        )

        let installer = Process()
        installer.executableURL = URL(fileURLWithPath: "/usr/bin/nohup")
        installer.arguments = ["/bin/zsh", scriptURL.path]
        installer.standardOutput = FileHandle.nullDevice
        installer.standardError = FileHandle.nullDevice
        try installer.run()
        handedOffToInstaller = true
    }

    private func downloadSmallAsset(at url: URL, maximumBytes: Int) async throws -> Data {
        guard isAllowedGitHubAssetURL(url) else {
            throw JarvisUpdateError.invalidManifest
        }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Jarvis macOS; +https://github.com/MineonStudio/Jarvis", forHTTPHeaderField: "User-Agent")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        let (fileURL, response) = try await updateSession.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200 ..< 300).contains(httpResponse.statusCode)
        else {
            throw URLError(.badServerResponse)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? maximumBytes + 1
        guard size > 0, size <= maximumBytes else {
            throw JarvisUpdateError.invalidManifest
        }
        return try Data(contentsOf: fileURL, options: .mappedIfSafe)
    }

    private func latestSignedManifest(operationID: String) async throws -> JarvisUpdateManifest {
        let manifestURL = Self.releasesURL.appending(path: "latest/download/\(Self.manifestAssetName)")
        let signatureURL = Self.releasesURL.appending(path: "latest/download/\(Self.signatureAssetName)")
        do {
            return try await verifySignedManifest(
                manifestURL: manifestURL,
                signatureURL: signatureURL,
                operationID: operationID
            )
        } catch JarvisUpdateError.invalidManifestSignature {
            // A new release can become latest between the two asset requests.
            return try await verifySignedManifest(
                manifestURL: manifestURL,
                signatureURL: signatureURL,
                operationID: operationID
            )
        }
    }

    static func releaseAssetURL(version: String, name: String) -> URL? {
        guard let normalizedVersion = JarvisUpdateSecurity.normalizedVersion(version),
              JarvisUpdateSecurity.isValidVersion(normalizedVersion),
              [JarvisUpdateSecurity.updateArchiveName, manifestAssetName, signatureAssetName].contains(name)
        else {
            return nil
        }
        return releasesURL.appending(path: "download/v\(normalizedVersion)/\(name)")
    }

    /// Download and verify the signed manifest before trusting its version or archive hash.
    private func verifyUpdateManifest(
        for release: JarvisReleaseInfo,
        operationID: String
    ) async throws -> JarvisUpdateManifest {
        try await verifySignedManifest(
            manifestURL: release.manifestURL,
            signatureURL: release.signatureURL,
            expectedVersion: release.version,
            expectedBuild: release.build,
            operationID: operationID
        )
    }

    private func verifySignedManifest(
        manifestURL: URL,
        signatureURL: URL,
        expectedVersion: String? = nil,
        expectedBuild: String? = nil,
        operationID: String
    ) async throws -> JarvisUpdateManifest {
        do {
            let manifestData = try await downloadSmallAsset(
                at: manifestURL,
                maximumBytes: JarvisUpdateSecurity.maximumManifestBytes
            )
            let signatureData = try await downloadSmallAsset(
                at: signatureURL,
                maximumBytes: JarvisUpdateSecurity.maximumSignatureBytes
            )
            let publicKey = try embeddedUpdatePublicKey()
            let manifest = try JarvisUpdateSecurity.verifyManifest(
                data: manifestData,
                signatureData: signatureData,
                publicKeyBase64: publicKey
            )
            if let expectedVersion,
               !JarvisUpdateSecurity.releaseVersionsMatch(manifest.version, expectedVersion)
            {
                throw JarvisUpdateError.mismatchedVersion
            }
            if let expectedBuild, manifest.build != expectedBuild {
                throw JarvisUpdateError.mismatchedVersion
            }
            JarvisLog.info(
                category: .update,
                event: "manifest.verify.success",
                operationID: operationID,
                fields: ["version": manifest.version]
            )
            return manifest
        } catch {
            JarvisLog.error(
                category: .update,
                event: "manifest.verify.failed",
                error: error,
                operationID: operationID
            )
            throw error
        }
    }

    private func embeddedUpdatePublicKey() throws -> String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "JarvisUpdatePublicKey") as? String,
              !key.isEmpty
        else {
            throw JarvisUpdateError.missingSignedManifest
        }
        return key
    }

    private func isAllowedGitHubAssetURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "github.com"
    }

    private static func bundleValue(_ key: String, in appURL: URL) -> String? {
        let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return nil
        }
        return plist[key] as? String
    }

    private func validateInstallLocation(_ appURL: URL) throws {
        let path = appURL.path
        if path.range(of: "/AppTranslocation/", options: .caseInsensitive) != nil {
            throw JarvisUpdateError.unsupportedInstallLocation
        }

        let resourceValues = try? appURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        if resourceValues?.volumeIsReadOnly == true {
            throw JarvisUpdateError.unsupportedInstallLocation
        }
    }

    private func resolveInstallLocation(for launchedURL: URL) throws -> URL {
        guard launchedURL.path.range(of: "/AppTranslocation/", options: .caseInsensitive) != nil else {
            return launchedURL
        }

        let launchedExecutable = launchedURL.appendingPathComponent("Contents/MacOS/Jarvis")
        guard let launchedExecutableDigest = try? sha256(of: launchedExecutable),
              let bundleIdentifier = Bundle.main.bundleIdentifier,
              let unmanagedURLs = LSCopyApplicationURLsForBundleIdentifier(
                  bundleIdentifier as CFString,
                  nil
              )
        else {
            throw JarvisUpdateError.unsupportedInstallLocation
        }

        let registeredURLs = unmanagedURLs.takeRetainedValue() as NSArray
        let candidates = registeredURLs.compactMap { $0 as? URL }
            .map(\.standardizedFileURL)
            .filter { candidate in
                candidate.pathExtension.lowercased() == "app"
                    && candidate.lastPathComponent == "Jarvis.app"
                    && candidate.path.range(of: "/AppTranslocation/", options: .caseInsensitive) == nil
                    && isValidApplicationBundle(candidate)
                    && (try? sha256(of: candidate.appendingPathComponent("Contents/MacOS/Jarvis"))) == launchedExecutableDigest
            }

        guard !candidates.isEmpty else {
            throw JarvisUpdateError.unsupportedInstallLocation
        }
        guard candidates.count == 1 else {
            throw JarvisUpdateError.ambiguousInstallLocation
        }
        return candidates[0]
    }

    /// The signed manifest is the trust root; the downloaded archive must match its SHA-256.
    func validateSignedArchive(
        at fileURL: URL,
        manifest: JarvisUpdateManifest
    ) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let archiveSize = (attributes[.size] as? NSNumber)?.int64Value,
              archiveSize > 0,
              archiveSize <= JarvisUpdateSecurity.maximumArchiveBytes
        else { throw JarvisUpdateError.invalidArchive }
        let actual = try sha256(of: fileURL)
        guard actual.caseInsensitiveCompare(manifest.sha256) == .orderedSame else {
            throw JarvisUpdateError.checksumMismatch
        }
    }

    private func sha256(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private var updateSession: URLSession {
        Self.updateSession
    }

    private static let updateSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 10 * 60
        return URLSession(configuration: configuration)
    }()

    private func findApplication(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator {
            if url.pathExtension.lowercased() == "app", url.lastPathComponent == "Jarvis.app" {
                return url
            }
        }
        return nil
    }

    private func isValidApplicationBundle(_ url: URL) -> Bool {
        let executableURL = url.appendingPathComponent("Contents/MacOS/Jarvis")
        let infoURL = url.appendingPathComponent("Contents/Info.plist")
        guard FileManager.default.isReadableFile(atPath: executableURL.path),
              FileManager.default.isReadableFile(atPath: infoURL.path),
              let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleIdentifier = plist["CFBundleIdentifier"] as? String
        else {
            return false
        }
        guard bundleIdentifier == Bundle.main.bundleIdentifier else {
            return false
        }
        return true
    }

    private func runTool(_ path: String, arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "未知错误"
            throw JarvisUpdateError.toolFailed(message)
        }
    }
}

extension JarvisUpdateService {
    // Keep the replacement/rollback script as one transaction so that every
    // path shares the same quoting, logging, and recovery behavior.
    // swiftlint:disable:next function_body_length
    func makeInstallerScript(
        at scriptURL: URL,
        currentAppURL: URL,
        newAppURL: URL,
        temporaryDirectory: URL,
        parentProcessID: Int32
    ) throws {
        let backupURL = currentAppURL.deletingLastPathComponent()
            .appendingPathComponent("Jarvis.app.update-backup-\(UUID().uuidString)")
        let script = """
        #!/bin/zsh
        set -u
        log_file=\(shellQuote(Self.updateLogURL.path))
        /bin/mkdir -p "$(/usr/bin/dirname "$log_file")" 2>/dev/null || true
        exec >> "$log_file" 2>&1
        log() {
            echo "[$(/bin/date '+%Y-%m-%d %H:%M:%S')] $*"
        }

        old_app=\(shellQuote(currentAppURL.path))
        new_app=\(shellQuote(newAppURL.path))
        backup_app=\(shellQuote(backupURL.path))
        temp_dir=\(shellQuote(temporaryDirectory.path))
        parent_pid=\(parentProcessID)

        log "开始安装更新：$new_app -> $old_app"
        log "当前进程 PID：$parent_pid"

        is_app_running() {
            local target="$1"
            /bin/ps -axo pid=,command= \\
                | /usr/bin/grep -F "$target/Contents/MacOS/Jarvis" \\
                | /usr/bin/grep -v -F "/usr/bin/grep" >/dev/null 2>&1
        }

        launch_and_verify() {
            local target="$1"
            local attempt
            local tick
            for attempt in 1 2 3; do
                log "启动应用（第 $attempt 次）：$target"
                if ! /usr/bin/open -na "$target"; then
                    log "open 启动命令失败"
                fi
                for tick in {1..40}; do
                    if is_app_running "$target"; then
                        log "检测到新进程已启动"
                        return 0
                    fi
                    /bin/sleep 0.25
                done
                log "等待应用进程超时"
            done
            return 1
        }

        refresh_launch_services() {
            local target="$1"
            local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
            if [[ -x "$lsregister" ]]; then
                "$lsregister" -u "$target" >/dev/null 2>&1 || true
                "$lsregister" -f "$target" >/dev/null 2>&1 || log "刷新 LaunchServices 图标注册失败"
            fi
        }

        cleanup_user_owned() {
            /bin/rm -rf "$backup_app" "$temp_dir"
        }

        restore_user_owned() {
            log "回滚到旧版本"
            /bin/rm -rf "$old_app"
            /bin/mv "$backup_app" "$old_app"
        }

        cleanup_with_authorization() {
            /usr/bin/osascript - "$backup_app" "$temp_dir" <<'APPLESCRIPT'
        on run argv
            set backupApp to item 1 of argv
            set tempDir to item 2 of argv
            set command to "/bin/rm -rf " & quoted form of backupApp & " " & quoted form of tempDir
            do shell script command with administrator privileges
        end run
        APPLESCRIPT
        }

        restore_with_authorization() {
            /usr/bin/osascript - "$old_app" "$backup_app" <<'APPLESCRIPT'
        on run argv
            set oldApp to item 1 of argv
            set backupApp to item 2 of argv
            set command to "/bin/rm -rf " & quoted form of oldApp & " && /bin/mv " & quoted form of backupApp & " " & quoted form of oldApp
            do shell script command with administrator privileges
        end run
        APPLESCRIPT
        }

        replace_without_authorization() {
            if ! /bin/mv "$old_app" "$backup_app"; then
                log "普通权限移动旧应用失败"
                return 1
            fi
            log "旧应用已暂存为备份"

            if ! /usr/bin/ditto "$new_app" "$old_app"; then
                log "普通权限复制新应用失败"
                restore_user_owned
                return 1
            fi
            log "新应用已替换到原路径"
            refresh_launch_services "$old_app"

            if launch_and_verify "$old_app"; then
                cleanup_user_owned
                log "更新成功"
                exit 0
            fi

            log "新应用启动失败，执行回滚"
            restore_user_owned
            launch_and_verify "$old_app" || log "旧版本恢复后启动也失败"
            /bin/rm -rf "$temp_dir"
            exit 1
        }

        replace_with_authorization() {
            log "请求系统管理员授权替换应用"
            if ! /usr/bin/osascript - "$old_app" "$new_app" "$backup_app" <<'APPLESCRIPT'
        on run argv
            set oldApp to item 1 of argv
            set newApp to item 2 of argv
            set backupApp to item 3 of argv
            set command to "/bin/mv " & quoted form of oldApp & " " & quoted form of backupApp & " && if /usr/bin/ditto " & quoted form of newApp & " " & quoted form of oldApp & "; then exit 0; else /bin/rm -rf " & quoted form of oldApp & " && /bin/mv " & quoted form of backupApp & " " & quoted form of oldApp & "; exit 1; end if"
            do shell script command with administrator privileges
        end run
        APPLESCRIPT
            then
                log "管理员授权失败或用户取消"
                launch_and_verify "$old_app" || log "授权取消后旧版本启动失败"
                /bin/rm -rf "$temp_dir"
                exit 1
            fi
            log "管理员权限替换完成"
            refresh_launch_services "$old_app"

            if launch_and_verify "$old_app"; then
                cleanup_with_authorization || log "清理备份文件失败：$backup_app"
                log "更新成功"
                exit 0
            fi

            log "新应用启动失败，执行管理员回滚"
            if restore_with_authorization; then
                launch_and_verify "$old_app" || log "旧版本恢复后启动也失败"
            else
                log "管理员回滚失败：$backup_app"
            fi
            /bin/rm -rf "$temp_dir"
            exit 1
        }

        log "等待用户已批准退出的应用结束"
        while /bin/ps -p "$parent_pid" -o command= 2>/dev/null \\
            | /usr/bin/grep -F "$old_app/Contents/MacOS/Jarvis" >/dev/null 2>&1; do
            /bin/sleep 0.1
        done
        log "应用进程已结束，开始替换"

        abort_install() {
            log "$1，保留旧版本并重新启动"
            /usr/bin/open -na "$old_app" || log "旧版本重新启动失败"
            /bin/rm -rf "$temp_dir"
            exit 1
        }
        requirement=$(/usr/bin/codesign -d -r- "$old_app" 2>&1) || abort_install "无法读取当前代码身份"
        requirement=$(print -r -- "$requirement" | /usr/bin/sed -n 's/^designated => //p')
        if [[ -n "$requirement" ]] && /usr/bin/codesign --verify --deep --strict -R "=$requirement" "$new_app" >/dev/null 2>&1; then
            log "新应用签名校验通过"
        else
            log "新应用签名校验失败，保留旧版本并重新启动"
            /usr/bin/open -na "$old_app" || log "旧版本重新启动失败"
            /bin/rm -rf "$temp_dir"
            exit 1
        fi

        # 发布包没有开发者 ID 签名，留着 quarantine 会被 Gatekeeper 挡住启动，
        # 所以只在签名校验通过之后才摘。
        if /usr/bin/xattr -p com.apple.quarantine "$new_app" >/dev/null 2>&1; then
            /usr/bin/xattr -dr com.apple.quarantine "$new_app" || abort_install "无法移除更新包隔离标记"
        fi

        if replace_without_authorization; then
            exit 0
        fi
        replace_with_authorization
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: scriptURL.path
        )
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
