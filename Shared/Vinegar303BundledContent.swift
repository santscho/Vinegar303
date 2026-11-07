import Darwin
import Foundation

/// Copies goodie presets and MIDI profiles that ship inside the app bundle into
/// the normal user library. The copies are ordinary user files: they are never
/// protected, locked or treated as factory content.
///
/// A marker file in the support root records which bundled relative paths have
/// already been offered. That lets the user delete a bundled goodie without the
/// app restoring it on the next launch, while still allowing later app versions
/// to add new goodies under new relative paths.
public enum Vinegar303BundledContent {
    public static let contentFolderName = "Content"
    public static let markerFileName = ".bundled-content-seeded"

    @discardableResult
    public static func installFromAppBundle(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) -> Set<String> {
        guard let resources = bundle.resourceURL else { return [] }
        return install(
            from: resources.appendingPathComponent(contentFolderName, isDirectory: true),
            to: applicationSupportURL(),
            fileManager: fileManager
        )
    }

    @discardableResult
    public static func install(
        from contentURL: URL,
        to supportURL: URL,
        fileManager: FileManager = .default
    ) -> Set<String> {
        let markerURL = supportURL.appendingPathComponent(markerFileName, isDirectory: false)
        var seeded = readSeeded(markerURL, fileManager: fileManager)

        copyTree(
            from: contentURL.appendingPathComponent("Presets", isDirectory: true),
            to: supportURL.appendingPathComponent("Presets", isDirectory: true),
            idPrefix: "Presets",
            fileExtension: Vinegar303Preset.fileExtension,
            seeded: &seeded,
            fileManager: fileManager
        )
        copyTree(
            from: contentURL.appendingPathComponent("MIDI/Profiles", isDirectory: true),
            to: supportURL.appendingPathComponent("MIDI/Profiles", isDirectory: true),
            idPrefix: "MIDI/Profiles",
            fileExtension: "json",
            seeded: &seeded,
            fileManager: fileManager
        )

        writeSeeded(seeded, to: markerURL, fileManager: fileManager)
        return seeded
    }

    public static func applicationSupportURL() -> URL {
        realHomeDirectory
            .appendingPathComponent("Library/Application Support/Vinegar303", isDirectory: true)
    }

    private static func copyTree(
        from sourceRoot: URL,
        to destinationRoot: URL,
        idPrefix: String,
        fileExtension: String,
        seeded: inout Set<String>,
        fileManager: FileManager
    ) {
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        let sourceComponents = sourceRoot.standardizedFileURL.pathComponents
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == fileExtension else { continue }
            guard let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            ),
            values.isRegularFile == true,
            values.isSymbolicLink != true else {
                continue
            }

            let components = fileURL.standardizedFileURL.pathComponents
            guard components.count > sourceComponents.count,
                  Array(components.prefix(sourceComponents.count)) == sourceComponents else {
                continue
            }
            let relativePath = components
                .dropFirst(sourceComponents.count)
                .joined(separator: "/")
            guard !relativePath.isEmpty else { continue }

            let id = "\(idPrefix)/\(relativePath)"
            guard !seeded.contains(id) else { continue }

            let destination = destinationRoot.appendingPathComponent(relativePath)
            let destinationPath = destination.standardizedFileURL.path
            guard destinationPath.hasPrefix(
                destinationRoot.standardizedFileURL.path + "/"
            ) else {
                continue
            }

            if fileManager.fileExists(atPath: destinationPath) {
                // A user may already have installed or edited the same goodie.
                // Mark it as offered so deleting it later does not resurrect it.
                seeded.insert(id)
                continue
            }

            do {
                try fileManager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try fileManager.copyItem(at: fileURL, to: destination)
                seeded.insert(id)
            } catch {
                // Leave the file unmarked so a later launch can retry.
            }
        }
    }

    private static func readSeeded(_ url: URL, fileManager: FileManager) -> Set<String> {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return Set(text.split(whereSeparator: \.isNewline).map(String.init))
    }

    private static func writeSeeded(
        _ seeded: Set<String>,
        to url: URL,
        fileManager: FileManager
    ) {
        let text = seeded.sorted().joined(separator: "\n")
            + (seeded.isEmpty ? "" : "\n")
        guard let data = text.data(using: .utf8) else { return }
        try? fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    private static var realHomeDirectory: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }
}
