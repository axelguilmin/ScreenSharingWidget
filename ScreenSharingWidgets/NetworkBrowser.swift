import Foundation
import Network
import OSLog

/// Live list of machines advertising Screen Sharing (`_rfb._tcp`) on the local network,
/// i.e. the "Network" section of Screen Sharing's sidebar.
@MainActor
final class NetworkBrowser {
    private let logger = Logger(subsystem: "fr.axelguilmin.ScreenSharingWidgets", category: "bonjour")
    private let onChange: @MainActor ([String]) -> Void
    private var browser: NWBrowser?
    private var debounce: Task<Void, Never>?

    /// Bonjour instance names, sorted, excluding this Mac.
    private(set) var serviceNames: [String] = []

    init(onChange: @escaping @MainActor ([String]) -> Void) {
        self.onChange = onChange
    }

    func start() {
        let browser = NWBrowser(for: .bonjour(type: "_rfb._tcp", domain: "local."), using: .tcp)
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .failed(let error):
                    self.logger.error("Browser failed: \(error.localizedDescription, privacy: .public)")
                    self.restart()
                case .waiting(let error):
                    self.logger.notice("Browser waiting: \(error.localizedDescription, privacy: .public)")
                default:
                    break
                }
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let names = results.compactMap { result -> String? in
                if case let .service(name, _, _, _) = result.endpoint { return name }
                return nil
            }
            MainActor.assumeIsolated { self?.update(names) }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    private func restart() {
        browser?.cancel()
        browser = nil
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.start()
        }
    }

    private func update(_ names: [String]) {
        let localName = Host.current().localizedName
        let sorted = Set(names)
            .filter { $0 != localName }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard sorted != serviceNames else { return }
        serviceNames = sorted
        // Bonjour flaps when machines sleep/wake; coalesce bursts.
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.onChange(self.serviceNames)
        }
    }
}
