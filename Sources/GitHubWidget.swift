import Foundation

struct RepositorySummary: Decodable {
    let full_name: String
    let html_url: String
    let stargazers_count: Int
    let forks_count: Int
    let open_issues_count: Int
    let description: String?
}
struct RepositoryIssue: Decodable, Identifiable {
    let id: Int
    let number: Int
    let title: String
    let html_url: String
    let pull_request: PullRequestMarker?
    struct PullRequestMarker: Decodable { let url: String? }
}
struct RepositoryRun: Decodable, Identifiable {
    let id: Int
    let name: String?
    let status: String
    let conclusion: String?
    let html_url: String
    var displayStatus: String { status == "completed" ? (conclusion ?? "Unknown conclusion") : status.replacingOccurrences(of: "_", with: " ") }
}
struct RepositoryRuns: Decodable { let workflow_runs: [RepositoryRun] }
struct GitHubSnapshot {
    let repository: RepositorySummary
    let issues: [RepositoryIssue]
    let run: RepositoryRun?
    let activityWarning: String?
}

enum GitHubReadError: LocalizedError {
    case invalidRepository, missingCLI, access, rateLimited, timeout, response
    var errorDescription: String? {
        switch self {
        case .invalidRepository: return "Enter a repository as owner/name, such as dylanlasensky/DockGrove."
        case .missingCLI: return "GitHub CLI was not found. Install gh and sign in with gh auth login, or choose public access."
        case .access: return "Repository unavailable. Check its name and access. For a private repo, sign in with gh auth login and enable GitHub CLI access."
        case .rateLimited: return "GitHub rate limit reached. Wait before refreshing, or use your GitHub CLI sign-in."
        case .timeout: return "GitHub took too long to respond. Try again."
        case .response: return "GitHub returned an unexpected response. Try again later."
        }
    }
}
enum GitHubClient {
    static func normalized(_ input: String) -> String? {
        var name = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("https://github.com/") { name.removeFirst("https://github.com/".count) }
        if name.hasSuffix("/") { name.removeLast() }
        if name.hasSuffix(".git") { name.removeLast(4) }
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(allowed.contains) }) else { return nil }
        return name
    }
    static func safeURL(_ value: String) -> URL? {
        guard let url = URL(string: value), url.scheme == "https", url.host == "github.com", url.user == nil, url.password == nil else { return nil }; return url
    }
    static func fetch(_ input: String, useCLI: Bool) async throws -> GitHubSnapshot {
        guard let name = normalized(input) else { throw GitHubReadError.invalidRepository }
        let repo: RepositorySummary = try await request("repos/" + name, useCLI: useCLI)
        // Repositories without Actions access still have useful metadata and issues.
        var issues: [RepositoryIssue] = [], run: RepositoryRun?, warnings: [String] = []
        do { issues = try await request("repos/\(name)/issues?state=open&per_page=20", useCLI: useCLI) }
        catch { warnings.append("Issues unavailable") }
        do { let runs: RepositoryRuns = try await request("repos/\(name)/actions/runs?per_page=1", useCLI: useCLI); run = runs.workflow_runs.first }
        catch { warnings.append("Actions unavailable") }
        return GitHubSnapshot(repository: repo, issues: issues, run: run, activityWarning: warnings.isEmpty ? nil : warnings.joined(separator: " · "))
    }
    private static func request<T: Decodable>(_ endpoint: String, useCLI: Bool) async throws -> T {
        let data: Data
        if useCLI {
            data = try await Task.detached(priority: .utility) { try cli(endpoint) }.value
        } else {
            var request = URLRequest(url: URL(string: "https://api.github.com/" + endpoint)!)
            request.timeoutInterval = 15
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("DockGrove", forHTTPHeaderField: "User-Agent")
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let (body, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GitHubReadError.response }
            guard http.statusCode == 200 else {
                if http.statusCode == 429 || (http.statusCode == 403 && http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0") { throw GitHubReadError.rateLimited }
                throw GitHubReadError.access
            }
            data = body
        }
        guard data.count <= 4_000_000 else { throw GitHubReadError.response }
        return try JSONDecoder().decode(T.self, from: data)
    }
    private static func cli(_ endpoint: String) throws -> Data {
        guard let executable = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw GitHubReadError.missingCLI }
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["api", "--hostname", "github.com", "--method", "GET", endpoint]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        defer { if process.isRunning { process.terminate() } }
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        var data = Data(); let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            var fd = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            if poll(&fd, 1, 100) > 0 {
                var bytes = [UInt8](repeating: 0, count: 8192)
                let count = Darwin.read(descriptor, &bytes, bytes.count)
                if count == 0 { process.waitUntilExit(); guard process.terminationStatus == 0 else { throw GitHubReadError.access }; return data }
                if count > 0 { data.append(contentsOf: bytes.prefix(count)) }
                guard data.count <= 4_000_000 else { throw GitHubReadError.response }
            }
        }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) { if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
        throw GitHubReadError.timeout
    }
}

@MainActor final class GitHubWidget: ObservableObject {
    @Published var repository: String { didSet { store.set(repository, forKey: "githubRepository"); if oldValue != repository { invalidate() } } }
    @Published var useCLI: Bool { didSet { store.set(useCLI, forKey: "githubUseCLI"); if oldValue != useCLI { invalidate() } } }
    @Published var autoRefresh: Bool { didSet { store.set(autoRefresh, forKey: "githubAutoRefresh") } }
    @Published var snapshot: GitHubSnapshot?
    @Published var error: String?
    @Published var refreshed: Date?
    @Published var loading = false
    private let store: UserDefaults
    private var generation = 0
    private var timer: Timer?
    init(store: UserDefaults) {
        self.store = store
        repository = store.string(forKey: "githubRepository") ?? "dylanlasensky/DockGrove"
        useCLI = store.bool(forKey: "githubUseCLI")
        autoRefresh = store.bool(forKey: "githubAutoRefresh")
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in Task { @MainActor in if self?.autoRefresh == true { self?.refresh() } } }
        if autoRefresh { refresh() }
    }
    deinit { timer?.invalidate() }
    private func invalidate() { generation += 1; snapshot = nil; refreshed = nil; error = nil; loading = false }
    func refresh() {
        guard !loading else { return }
        loading = true; let request = generation, repo = repository, cli = useCLI
        Task { @MainActor in
            do {
                let result = try await GitHubClient.fetch(repo, useCLI: cli)
                guard request == generation else { return }
                snapshot = result; refreshed = Date(); error = nil; loading = false
            } catch {
                guard request == generation else { return }
                self.error = (error as? GitHubReadError)?.localizedDescription ?? "Could not load GitHub. Check your connection and try again."
                loading = false
            }
        }
    }
}
