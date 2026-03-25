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
            return specialFilename(filename) ?? defaultIcon
        }

        return extensionMap[ext] ?? defaultIcon
    }

    // MARK: - Private

    private static let defaultIcon = "FileTypeIcons/filetype-file"

    private static func specialFilename(_ name: String) -> String? {
        let lower = name.lowercased()
        switch lower {
        case "makefile", "justfile", "rakefile", "gemfile", "podfile":
            return "FileTypeIcons/filetype-bash"
        case "dockerfile", "dockerfile.dev", "dockerfile.prod":
            return "FileTypeIcons/filetype-docker"
        case "docker-compose.yml", "docker-compose.yaml",
             "compose.yml", "compose.yaml":
            return "FileTypeIcons/filetype-docker-compose"
        case "license", "licence", "license.md", "licence.md":
            return "FileTypeIcons/filetype-license"
        case "readme", "readme.md":
            return "FileTypeIcons/filetype-readme"
        case ".gitignore", ".gitattributes", ".gitmodules", ".gitkeep":
            return "FileTypeIcons/filetype-git"
        case ".env", ".envrc", ".env.local", ".env.development",
             ".env.production":
            return "FileTypeIcons/filetype-env"
        case ".editorconfig", ".prettierrc", ".eslintrc":
            return "FileTypeIcons/filetype-config"
        case ".npmrc", ".npmignore":
            return "FileTypeIcons/filetype-npm"
        default:
            return nil
        }
    }

    // swiftlint:disable function_body_length
    private static let extensionMap: [String: String] = {
        var m: [String: String] = [:]
        let ns = "FileTypeIcons/"

        // Swift
        m["swift"] = ns + "filetype-swift"

        // C family
        let c = ns + "filetype-c"
        let ch = ns + "filetype-c-header"
        let cpp = ns + "filetype-cpp"
        m["c"] = c; m["m"] = c
        m["h"] = ch; m["hpp"] = ch; m["hh"] = ch
        m["cpp"] = cpp; m["cc"] = cpp; m["cxx"] = cpp; m["mm"] = cpp

        // Python
        let py = ns + "filetype-python"
        m["py"] = py; m["pyw"] = py; m["pyi"] = py

        // JavaScript / TypeScript
        let js = ns + "filetype-javascript"
        m["js"] = js; m["mjs"] = js; m["cjs"] = js
        let ts = ns + "filetype-typescript"
        m["ts"] = ts
        let tsx = ns + "filetype-typescript-react"
        m["tsx"] = tsx; m["jsx"] = tsx

        // Rust
        m["rs"] = ns + "filetype-rust"

        // Go
        m["go"] = ns + "filetype-go"

        // Java / JVM
        let java = ns + "filetype-java"
        m["java"] = java; m["jar"] = java
        m["kt"] = ns + "filetype-kotlin"
        m["scala"] = ns + "filetype-scala"

        // Ruby
        let rb = ns + "filetype-ruby"
        m["rb"] = rb; m["rake"] = rb; m["gemspec"] = rb

        // PHP
        m["php"] = ns + "filetype-php"

        // Dart
        m["dart"] = ns + "filetype-dart"

        // Lua
        m["lua"] = ns + "filetype-lua"

        // Zig
        m["zig"] = ns + "filetype-zig"

        // Nim
        m["nim"] = ns + "filetype-nim"

        // R
        m["r"] = ns + "filetype-r"

        // Perl
        let pl = ns + "filetype-perl"
        m["pl"] = pl; m["pm"] = pl

        // Elixir
        let ex = ns + "filetype-elixir"
        m["ex"] = ex; m["exs"] = ex

        // Assembly
        let asm = ns + "filetype-assembly"
        m["asm"] = asm; m["s"] = asm

        // Web markup
        m["html"] = ns + "filetype-html"; m["htm"] = ns + "filetype-html"
        m["css"] = ns + "filetype-css"
        let sass = ns + "filetype-sass"
        m["scss"] = sass; m["sass"] = sass; m["less"] = sass

        // Frameworks
        m["vue"] = ns + "filetype-vue"
        m["svelte"] = ns + "filetype-svelte"
        m["astro"] = ns + "filetype-astro"

        // Data / config (structured)
        m["json"] = ns + "filetype-json"
        let yaml = ns + "filetype-yaml"
        m["yaml"] = yaml; m["yml"] = yaml
        m["toml"] = ns + "filetype-toml"
        m["xml"] = ns + "filetype-xml"; m["plist"] = ns + "filetype-xml"
        m["csv"] = ns + "filetype-csv"
        m["graphql"] = ns + "filetype-graphql"; m["gql"] = ns + "filetype-graphql"
        m["proto"] = ns + "filetype-proto"

        // Config
        let cfg = ns + "filetype-config"
        m["ini"] = cfg; m["cfg"] = cfg; m["conf"] = cfg
        m["editorconfig"] = cfg

        m["env"] = ns + "filetype-env"

        // Shell
        let bash = ns + "filetype-bash"
        m["sh"] = bash; m["bash"] = bash; m["zsh"] = bash; m["fish"] = bash; m["nu"] = bash
        m["ps1"] = ns + "filetype-powershell"

        // Docker
        m["dockerfile"] = ns + "filetype-docker"

        // Database
        let sql = ns + "filetype-sql"
        m["sql"] = sql; m["sqlite"] = sql; m["db"] = sql

        // Markdown / text
        let md = ns + "filetype-markdown"
        m["md"] = md; m["markdown"] = md; m["mdx"] = md
        let txt = ns + "filetype-text"
        m["txt"] = txt; m["rst"] = txt; m["adoc"] = txt; m["tex"] = txt

        // PDF / documents
        m["pdf"] = ns + "filetype-pdf"

        // Images
        let img = ns + "filetype-image"
        for ext in ["png", "jpg", "jpeg", "gif", "webp", "bmp", "ico",
                     "tiff", "heic"] {
            m[ext] = img
        }
        m["svg"] = ns + "filetype-svg"

        // Audio / Video
        let audio = ns + "filetype-audio"
        for ext in ["mp3", "wav", "aac", "flac", "ogg", "m4a"] {
            m[ext] = audio
        }
        let video = ns + "filetype-video"
        for ext in ["mp4", "mov", "avi", "mkv", "webm"] {
            m[ext] = video
        }

        // Archives
        let zip = ns + "filetype-zip"
        for ext in ["zip", "tar", "gz", "bz2", "xz", "rar", "7z"] {
            m[ext] = zip
        }

        // Lock files
        let lock = ns + "filetype-lock"
        m["lock"] = lock; m["resolved"] = lock

        // Git
        let git = ns + "filetype-git"
        m["gitignore"] = git; m["gitattributes"] = git

        // npm
        m["npmrc"] = ns + "filetype-npm"

        // Log
        m["log"] = ns + "filetype-log"

        // Diff
        m["diff"] = ns + "filetype-diff"; m["patch"] = ns + "filetype-diff"

        // Binary
        let bin = ns + "filetype-binary"
        m["bin"] = bin; m["exe"] = bin; m["dylib"] = bin; m["so"] = bin

        // Certificates
        let cert = ns + "filetype-certificate"
        m["pem"] = cert; m["crt"] = cert; m["key"] = cert; m["cer"] = cert

        return m
    }()
    // swiftlint:enable function_body_length
}
