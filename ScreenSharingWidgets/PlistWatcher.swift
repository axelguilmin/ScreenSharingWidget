import Foundation

/// Watches Screen Sharing's preferences file. cfprefsd rewrites it atomically
/// (rename), so the file descriptor is re-opened after every event.
@MainActor
final class PlistWatcher {
    private let url: URL
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var debounce: Task<Void, Never>?
    private var retry: Task<Void, Never>?

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        self.url = url
        self.onChange = onChange
    }

    func start() {
        stop()
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File missing (Screen Sharing never launched?) — try again later.
            retry = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                self?.start()
            }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let events = source.data
                self.scheduleChange()
                if events.contains(.delete) || events.contains(.rename) {
                    self.start()
                }
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        retry?.cancel()
        source?.cancel()
        source = nil
    }

    private func scheduleChange() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.onChange()
        }
    }
}
