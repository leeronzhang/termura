import SwiftUI

// MARK: - File Type Icon

/// Maps file extensions to Catppuccin icon assets (Frappe variant).
/// Icons are bundled as template images and render in `.secondary` monochrome.
/// Source: https://github.com/catppuccin/vscode-icons (MIT License)
enum FileTypeIcon {
    /// Returns a SwiftUI `Image` for the given filename, sized for the file tree.
    static func image(for filename: String) -> Image {
        let asset = assetName(for: filename)
        return Image(asset, bundle: nil)
    }

    /// Returns the asset catalog name for a given filename.
    static func assetName(for filename: String) -> String {
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        if ext.isEmpty {
            return specialFilenameMap[filename.lowercased()] ?? defaultIcon
        }
        return extensionMap[ext] ?? defaultIcon
    }

    // MARK: - Private

    private static let defaultIcon = "FileTypeIcons/filetype-file"

    // MARK: Special Filenames (no extension)

    private static let specialFilenameMap: [String: String] = icons([
        "makefile": "filetype-bash", "justfile": "filetype-bash",
        "rakefile": "filetype-bash", "gemfile": "filetype-bash", "podfile": "filetype-bash",
        "dockerfile": "filetype-docker",
        "dockerfile.dev": "filetype-docker", "dockerfile.prod": "filetype-docker",
        "docker-compose.yml": "filetype-docker-compose",
        "docker-compose.yaml": "filetype-docker-compose",
        "compose.yml": "filetype-docker-compose", "compose.yaml": "filetype-docker-compose",
        "license": "filetype-license", "licence": "filetype-license",
        "license.md": "filetype-license", "licence.md": "filetype-license",
        "readme": "filetype-readme", "readme.md": "filetype-readme",
        ".gitignore": "filetype-git", ".gitattributes": "filetype-git",
        ".gitmodules": "filetype-git", ".gitkeep": "filetype-git",
        ".env": "filetype-env", ".envrc": "filetype-env",
        ".env.local": "filetype-env", ".env.development": "filetype-env",
        ".env.production": "filetype-env",
        ".editorconfig": "filetype-config", ".prettierrc": "filetype-config",
        ".eslintrc": "filetype-config",
        ".npmrc": "filetype-npm", ".npmignore": "filetype-npm"
    ])

    // MARK: Extension Maps (grouped by category)

    private static let languageExtensions: [String: String] = icons([
        "swift": "filetype-swift",
        "c": "filetype-c", "m": "filetype-c",
        "h": "filetype-c-header", "hpp": "filetype-c-header", "hh": "filetype-c-header",
        "cpp": "filetype-cpp", "cc": "filetype-cpp", "cxx": "filetype-cpp", "mm": "filetype-cpp",
        "py": "filetype-python", "pyw": "filetype-python", "pyi": "filetype-python",
        "js": "filetype-javascript", "mjs": "filetype-javascript", "cjs": "filetype-javascript",
        "ts": "filetype-typescript",
        "tsx": "filetype-typescript-react", "jsx": "filetype-typescript-react",
        "rs": "filetype-rust",
        "go": "filetype-go",
        "java": "filetype-java", "jar": "filetype-java",
        "kt": "filetype-kotlin",
        "scala": "filetype-scala",
        "rb": "filetype-ruby", "rake": "filetype-ruby", "gemspec": "filetype-ruby",
        "php": "filetype-php",
        "dart": "filetype-dart",
        "lua": "filetype-lua",
        "zig": "filetype-zig",
        "nim": "filetype-nim",
        "r": "filetype-r",
        "pl": "filetype-perl", "pm": "filetype-perl",
        "ex": "filetype-elixir", "exs": "filetype-elixir",
        "asm": "filetype-assembly", "s": "filetype-assembly"
    ])

    private static let webExtensions: [String: String] = icons([
        "html": "filetype-html", "htm": "filetype-html",
        "css": "filetype-css",
        "scss": "filetype-sass", "sass": "filetype-sass", "less": "filetype-sass",
        "vue": "filetype-vue",
        "svelte": "filetype-svelte",
        "astro": "filetype-astro"
    ])

    private static let dataExtensions: [String: String] = icons([
        "json": "filetype-json",
        "yaml": "filetype-yaml", "yml": "filetype-yaml",
        "toml": "filetype-toml",
        "xml": "filetype-xml", "plist": "filetype-xml",
        "csv": "filetype-csv",
        "graphql": "filetype-graphql", "gql": "filetype-graphql",
        "proto": "filetype-proto",
        "ini": "filetype-config", "cfg": "filetype-config",
        "conf": "filetype-config", "editorconfig": "filetype-config",
        "env": "filetype-env",
        "sh": "filetype-bash", "bash": "filetype-bash",
        "zsh": "filetype-bash", "fish": "filetype-bash", "nu": "filetype-bash",
        "ps1": "filetype-powershell",
        "dockerfile": "filetype-docker",
        "sql": "filetype-sql", "sqlite": "filetype-sql", "db": "filetype-sql",
        "md": "filetype-markdown", "markdown": "filetype-markdown", "mdx": "filetype-markdown",
        "txt": "filetype-text", "rst": "filetype-text",
        "adoc": "filetype-text", "tex": "filetype-text",
        "pdf": "filetype-pdf"
    ])

    private static let mediaAndSystemExtensions: [String: String] = icons([
        "png": "filetype-image", "jpg": "filetype-image", "jpeg": "filetype-image",
        "gif": "filetype-image", "webp": "filetype-image", "bmp": "filetype-image",
        "ico": "filetype-image", "tiff": "filetype-image", "heic": "filetype-image",
        "svg": "filetype-svg",
        "mp3": "filetype-audio", "wav": "filetype-audio", "aac": "filetype-audio",
        "flac": "filetype-audio", "ogg": "filetype-audio", "m4a": "filetype-audio",
        "mp4": "filetype-video", "mov": "filetype-video", "avi": "filetype-video",
        "mkv": "filetype-video", "webm": "filetype-video",
        "zip": "filetype-zip", "tar": "filetype-zip", "gz": "filetype-zip",
        "bz2": "filetype-zip", "xz": "filetype-zip", "rar": "filetype-zip", "7z": "filetype-zip",
        "lock": "filetype-lock", "resolved": "filetype-lock",
        "gitignore": "filetype-git", "gitattributes": "filetype-git",
        "npmrc": "filetype-npm",
        "log": "filetype-log",
        "diff": "filetype-diff", "patch": "filetype-diff",
        "bin": "filetype-binary", "exe": "filetype-binary",
        "dylib": "filetype-binary", "so": "filetype-binary",
        "pem": "filetype-certificate", "crt": "filetype-certificate",
        "key": "filetype-certificate", "cer": "filetype-certificate"
    ])

    private static let extensionMap: [String: String] = {
        var result = languageExtensions
        result.merge(webExtensions) { a, _ in a }
        result.merge(dataExtensions) { a, _ in a }
        result.merge(mediaAndSystemExtensions) { a, _ in a }
        return result
    }()

    /// Prefixes all icon suffix values with the "FileTypeIcons/" asset namespace.
    private static func icons(_ pairs: [String: String]) -> [String: String] {
        pairs.mapValues { "FileTypeIcons/" + $0 }
    }
}
