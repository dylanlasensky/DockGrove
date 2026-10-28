import SwiftUI

struct GitHubView: View {
    @ObservedObject var github: GitHubWidget
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("owner/repository", text: $github.repository).textFieldStyle(.roundedBorder).onSubmit { github.refresh() }
            Toggle("Use existing GitHub CLI sign-in", isOn: $github.useCLI)
            Toggle("Refresh every five minutes", isOn: $github.autoRefresh)
            Text("Public mode reads api.github.com. CLI mode uses gh’s existing sign-in. WaveDock does not read or store your token.").font(.caption).foregroundStyle(.secondary)
            if let snapshot = github.snapshot {
                if let url = GitHubClient.safeURL(snapshot.repository.html_url) { Link(snapshot.repository.full_name, destination: url).font(.headline) }
                Text("\(snapshot.repository.stargazers_count) stars · \(snapshot.repository.forks_count) forks · \(snapshot.repository.open_issues_count) open issues & PRs").font(.caption)
                if let run = snapshot.run, let url = GitHubClient.safeURL(run.html_url) {
                    Link("\(run.name ?? "Workflow"): \(run.displayStatus)", destination: url)
                } else { Text("No workflow run available").font(.caption).foregroundStyle(.secondary) }
                ScrollView { VStack(alignment: .leading, spacing: 10) { ForEach(snapshot.issues) { item in
                    if let url = GitHubClient.safeURL(item.html_url) { Link("\(item.pull_request == nil ? "Issue" : "PR") #\(item.number) · \(item.title)", destination: url).lineLimit(2) }
                } }}.frame(maxHeight: 190)
                if let warning = snapshot.activityWarning { Text(warning).font(.caption).foregroundStyle(.orange) }
            }
            if let error = github.error { Text(error).font(.caption).foregroundStyle(.orange) }
            if let refreshed = github.refreshed { Text("Updated \(refreshed.formatted(date: .omitted, time: .shortened))\(github.error == nil ? "" : " · Previous reading")").font(.caption).foregroundStyle(.secondary) }
            Button(github.loading ? "Refreshing…" : "Refresh GitHub", action: github.refresh).disabled(github.loading)
        }
    }
}
