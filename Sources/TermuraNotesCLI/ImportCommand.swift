import ArgumentParser
import Foundation
import TermuraNotesKit

struct ImportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import a file into the sources/ directory.",
        subcommands: [ImportFileCommand.self, ImportURLCommand.self]
    )
}

// MARK: - import file

struct ImportFileCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file",
        abstract: "Copy a local file into sources/ (auto-categorized by extension)."
    )

    @Argument(help: "Path to the file to import.")
    var path: String

    func run() throws {
        let project = try ProjectDiscovery()
        try project.ensureDirectories()

        let sourceURL = URL(fileURLWithPath: path).standardizedFileURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourceURL.path) else {
            throw ValidationError("File not found: \(path)")
        }

        let ext = sourceURL.pathExtension.lowercased()
        let subdir = Self.subdirectory(for: ext)
        let destDir = project.sourcesDirectory.appendingPathComponent(subdir)

        if !fm.fileExists(atPath: destDir.path) {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true, attributes: nil)
        }

        let destURL = destDir.appendingPathComponent(sourceURL.lastPathComponent)
        if fm.fileExists(atPath: destURL.path) {
            throw ValidationError("File already exists at \(destURL.path)")
        }

        try fm.copyItem(at: sourceURL, to: destURL)
        print("Imported \(sourceURL.lastPathComponent) → sources/\(subdir)/")
    }

    private static func subdirectory(for ext: String) -> String {
        switch ext {
        case "pdf": "papers"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "heic": "images"
        case "swift", "py", "js", "ts", "go", "rs", "rb", "sh": "code"
        case "csv", "json", "xml", "yaml", "yml": "data"
        default: "data"
        }
    }
}

// MARK: - import url

struct ImportURLCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "url",
        abstract: "Fetch a URL and save as a markdown source."
    )

    @Argument(help: "URL to fetch.")
    var url: String

    func run() throws {
        let project = try ProjectDiscovery()
        try project.ensureDirectories()

        guard let requestURL = URL(string: url) else {
            throw ValidationError("Invalid URL: \(url)")
        }

        let sem = DispatchSemaphore(value: 0)
        var fetchedData: Data?
        var fetchError: Error?

        let task = URLSession.shared.dataTask(with: requestURL) { data, _, error in
            fetchedData = data
            fetchError = error
            sem.signal()
        }
        task.resume()
        sem.wait()

        if let error = fetchError {
            throw ValidationError("Failed to fetch URL: \(error.localizedDescription)")
        }
        guard let data = fetchedData, let body = String(data: data, encoding: .utf8) else {
            throw ValidationError("No readable content at \(url)")
        }

        let slug = NoteFileLister.slugify(requestURL.host ?? "page")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let filename = "\(slug)-\(String(timestamp.prefix(10))).md"

        let header = """
        ---
        source_url: \(url)
        fetched_at: \(timestamp)
        ---

        """

        let destDir = project.sourcesDirectory.appendingPathComponent("articles")
        let destURL = destDir.appendingPathComponent(filename)
        try (header + body).write(to: destURL, atomically: true, encoding: .utf8)
        print("Imported \(url) → sources/articles/\(filename)")
    }
}
