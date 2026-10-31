import Foundation

// Deterministic sign-in lifecycle fixture. Its behavior comes from the name it is copied to.
let name = URL(fileURLWithPath: CommandLine.arguments[0]).deletingPathExtension().lastPathComponent
let arguments = Array(CommandLine.arguments.dropFirst())
// Copies named gh-<mode> stand in for the GitHub CLI's read-only `gh api` command.
if name.hasPrefix("gh-") {
    guard arguments.count == 6, Array(arguments.prefix(5)) == ["api", "--hostname", "github.com", "--method", "GET"] else { exit(2) }
    let endpoint = arguments[5]
    func reply(_ text: String) -> Never { FileHandle.standardOutput.write(Data(text.utf8)); exit(0) }
    switch name {
    case "gh-fail": exit(1)
    case "gh-hang": Thread.sleep(forTimeInterval: 30); exit(0)
    case "gh-big": while true { FileHandle.standardOutput.write(Data(repeating: 32, count: 65_536)) }
    default:
        if endpoint.contains("/issues") {
            if name == "gh-partial" { exit(1) }
            reply(#"[{"id":1,"number":7,"title":"Fixture issue","html_url":"https://github.com/o/r/issues/7","pull_request":null}]"#)
        }
        if endpoint.contains("/actions/runs") {
            if name == "gh-partial" { reply("not json") }
            reply(#"{"workflow_runs":[{"id":2,"name":"CI","status":"completed","conclusion":"success","html_url":"https://github.com/o/r/actions/runs/2"}]}"#)
        }
        reply(#"{"full_name":"o/r","html_url":"https://github.com/o/r","stargazers_count":1,"forks_count":2,"open_issues_count":3,"description":null}"#)
    }
}
guard [["login"], ["login", "status"], ["auth", "login", "--claudeai"], ["auth", "status"]].contains(arguments) else {
    FileHandle.standardError.write(Data("Unexpected arguments: \(arguments)\n".utf8)); exit(1)
}
if name == "denied" { exit(1) }
if name == "waiting" { Thread.sleep(forTimeInterval: 30) }
exit(0)
