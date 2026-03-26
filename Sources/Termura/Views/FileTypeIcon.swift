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

    private static let extensionMap: [String: String] = {
        var map: [String: String] = [:]
        let ns = "FileTypeIcons/"

        // Swift
        map["swift"] = ns + "filetype-swift"

        // C family
        let cfamily = ns + "filetype-c"
        let ch = ns + "filetype-c-header"
        let cpp = ns + "filetype-cpp"
        map["c"] = cfamily; map["m"] = cfamily
        map["h"] = ch; map["hpp"] = ch; map["hh"] = ch
        map["cpp"] = cpp; map["cc"] = cpp; map["cxx"] = cpp; map["mm"] = cpp

        // Python
        let py = ns + "filetype-python"
        map["py"] = py; map["pyw"] = py; map["pyi"] = py

        // JavaScript / TypeScript
        let js = ns + "filetype-javascript"
        map["js"] = js; map["mjs"] = js; map["cjs"] = js
        let ts = ns + "filetype-typescript"
        map["ts"] = ts
        let tsx = ns + "filetype-typescript-react"
        map["tsx"] = tsx; map["jsx"] = tsx

        // Rust
        map["rs"] = ns + "filetype-rust"

        // Go
        map["go"] = ns + "filetype-go"

        // Java / JVM
        let java = ns + "filetype-java"
        map["java"] = java; map["jar"] = java
        map["kt"] = ns + "filetype-kotlin"
        map["scala"] = ns + "filetype-scala"

        // Ruby
        let rb = ns + "filetype-ruby"
        map["rb"] = rb; map["rake"] = rb; map["gemspec"] = rb

        // PHP
        map["php"] = ns + "filetype-php"

        // Dart
        map["dart"] = ns + "filetype-dart"

        // Lua
        map["lua"] = ns + "filetype-lua"

        // Zig
        map["zig"] = ns + "filetype-zig"

        // Nim
        map["nim"] = ns + "filetype-nim"

        // R
        map["r"] = ns + "filetype-r"

        // Perl
        let pl = ns + "filetype-perl"
        map["pl"] = pl; map["pm"] = pl

        // Elixir
        let ex = ns + "filetype-elixir"
        map["ex"] = ex; map["exs"] = ex

        // Assembly
        let asm = ns + "filetype-assembly"
        map["asm"] = asm; map["s"] = asm

        // Web markup
        map["html"] = ns + "filetype-html"; map["htm"] = ns + "filetype-html"
        map["css"] = ns + "filetype-css"
        let sass = ns + "filetype-sass"
        map["scss"] = sass; map["sass"] = sass; map["less"] = sass

        // Frameworks
        map["vue"] = ns + "filetype-vue"
        map["svelte"] = ns + "filetype-svelte"
        map["astro"] = ns + "filetype-astro"

        // Data / config (structured)
        map["json"] = ns + "filetype-json"
        let yaml = ns + "filetype-yaml"
        map["yaml"] = yaml; map["yml"] = yaml
        map["toml"] = ns + "filetype-toml"
        map["xml"] = ns + "filetype-xml"; map["plist"] = ns + "filetype-xml"
        map["csv"] = ns + "filetype-csv"
        map["graphql"] = ns + "filetype-graphql"; map["gql"] = ns + "filetype-graphql"
        map["proto"] = ns + "filetype-proto"

        // Config
        let cfg = ns + "filetype-config"
        map["ini"] = cfg; map["cfg"] = cfg; map["conf"] = cfg
        map["editorconfig"] = cfg

        map["env"] = ns + "filetype-env"

        // Shell
        let bash = ns + "filetype-bash"
        map["sh"] = bash; map["bash"] = bash; map["zsh"] = bash; map["fish"] = bash; map["nu"] = bash
        map["ps1"] = ns + "filetype-powershell"

        // Docker
        map["dockerfile"] = ns + "filetype-docker"

        // Database
        let sql = ns + "filetype-sql"
        map["sql"] = sql; map["sqlite"] = sql; map["db"] = sql

        // Markdown / text
        let md = ns + "filetype-markdown"
        map["md"] = md; map["markdown"] = md; map["mdx"] = md
        let txt = ns + "filetype-text"
        map["txt"] = txt; map["rst"] = txt; map["adoc"] = txt; map["tex"] = txt

        // PDF / documents
        map["pdf"] = ns + "filetype-pdf"

        // Images
        let img = ns + "filetype-image"
        for ext in [
            "png", "jpg", "jpeg", "gif", "webp", "bmp", "ico",
            "tiff", "heic"
        ] {
            map[ext] = img
        }
        map["svg"] = ns + "filetype-svg"

        // Audio / Video
        let audio = ns + "filetype-audio"
        for ext in ["mp3", "wav", "aac", "flac", "ogg", "m4a"] {
            map[ext] = audio
        }
        let video = ns + "filetype-video"
        for ext in ["mp4", "mov", "avi", "mkv", "webm"] {
            map[ext] = video
        }

        // Archives
        let zip = ns + "filetype-zip"
        for ext in ["zip", "tar", "gz", "bz2", "xz", "rar", "7z"] {
            map[ext] = zip
        }

        // Lock files
        let lock = ns + "filetype-lock"
        map["lock"] = lock; map["resolved"] = lock

        // Git
        let git = ns + "filetype-git"
        map["gitignore"] = git; map["gitattributes"] = git

        // npm
        map["npmrc"] = ns + "filetype-npm"

        // Log
        map["log"] = ns + "filetype-log"

        // Diff
        map["diff"] = ns + "filetype-diff"; map["patch"] = ns + "filetype-diff"

        // Binary
        let bin = ns + "filetype-binary"
        map["bin"] = bin; map["exe"] = bin; map["dylib"] = bin; map["so"] = bin

        // Certificates
        let cert = ns + "filetype-certificate"
        map["pem"] = cert; map["crt"] = cert; map["key"] = cert; map["cer"] = cert

        return map
    }()
}
