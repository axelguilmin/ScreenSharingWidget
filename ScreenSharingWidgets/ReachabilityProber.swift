import Foundation
import Network
import OSLog

/// Checks whether non-Bonjour connections (IP / DNS names) accept TCP on their VNC port.
///
/// Kept deliberately light: one TCP handshake per machine every 15 minutes, plus one when
/// the network changes (Wi-Fi switch, VPN, wake). Bonjour machines are never probed —
/// their presence in the `_rfb._tcp` browse already tells us they're up.
@MainActor
final class ReachabilityProber {
    static let interval: Duration = .seconds(900)
    private static let timeout: Duration = .seconds(3)

    private let logger = Logger(subsystem: "fr.axelguilmin.ScreenSharingWidgets", category: "reachability")
    private let onChange: @MainActor ([String: Bool]) -> Void
    private let pathMonitor = NWPathMonitor()
    private var addresses: [String] = []
    private var timer: Task<Void, Never>?
    /// Status + interfaces, so a VPN coming up (new utun) also triggers a probe.
    private var lastPathKey: String?

    /// Keyed by `Connection.address`.
    private(set) var results: [String: Bool] = [:]

    init(onChange: @escaping @MainActor ([String: Bool]) -> Void) {
        self.onChange = onChange
    }

    func start() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            MainActor.assumeIsolated {
                let key = "\(path.status)|" + path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
                guard let self, key != self.lastPathKey else { return }
                self.lastPathKey = key
                self.probeAll()
            }
        }
        pathMonitor.start(queue: .main)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                self?.probeAll()
            }
        }
    }

    /// Call whenever the saved connections change; probes new addresses right away.
    func setAddresses(_ newAddresses: [String]) {
        let added = Set(newAddresses).subtracting(addresses)
        addresses = newAddresses
        results = results.filter { newAddresses.contains($0.key) }
        added.forEach(probe)
    }

    private func probeAll() {
        addresses.forEach(probe)
    }

    private func probe(_ address: String) {
        let (host, port) = Self.endpoint(for: address)
        let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
        let attempt = ProbeAttempt()

        let finish: @MainActor (Bool) -> Void = { [weak self] reachable in
            guard !attempt.isDone else { return }
            attempt.isDone = true
            connection.cancel()
            guard let self, self.addresses.contains(address) else { return }
            if self.results[address] != reachable {
                self.logger.info("\(address, privacy: .public) is now \(reachable ? "online" : "offline", privacy: .public)")
                self.results[address] = reachable
                self.onChange(self.results)
            }
        }

        connection.stateUpdateHandler = { state in
            MainActor.assumeIsolated {
                switch state {
                case .ready: finish(true)
                // `.waiting` = refused / no route: TCP won't succeed without a network change.
                case .waiting, .failed: finish(false)
                default: break
                }
            }
        }
        connection.start(queue: .main)
        Task {
            try? await Task.sleep(for: Self.timeout)
            finish(false)
        }
    }

    /// `host`, `host:port` or a display number `host:1` (VNC convention: 5900 + n).
    private static func endpoint(for address: String) -> (String, NWEndpoint.Port) {
        let decoded = address.removingPercentEncoding ?? address
        if let colon = decoded.lastIndex(of: ":"), decoded.firstIndex(of: ":") == colon,
           let value = UInt16(decoded[decoded.index(after: colon)...]) {
            let port = value < 100 ? 5900 + value : value
            return (String(decoded[..<colon]), NWEndpoint.Port(rawValue: port) ?? 5900)
        }
        return (decoded, 5900)
    }
}

@MainActor
private final class ProbeAttempt {
    var isDone = false
}
