import ArgumentParser

@main
struct TermuraNotesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tn",
        abstract: "Knowledge management CLI for Termura projects.",
        version: "0.1.0",
        subcommands: [
            ListCommand.self,
            AppendCommand.self,
            SearchCommand.self,
            LinkCommand.self,
            ImportCommand.self,
            MCPCommand.self,
            InitConventionCommand.self
        ]
    )
}
