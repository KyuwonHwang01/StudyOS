import Foundation
import Observation

/// Uncommitted form data is separate from confirmed tasks, plans and backup records.
@MainActor @Observable final class DraftRepository {
    private let url: URL?
    private var values: [String: Data] = [:]
    private var pending: Task<Void, Never>?
    private var dirty = false
    private var leases: [String: UUID] = [:]
    private var recoveredKeys = Set<String>()
    private var writesAllowed = true
    var error: String?

    init(url: URL?) {
        self.url = url
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return }
        do { values = try JSONDecoder().decode([String: Data].self, from: Data(contentsOf: url)) }
        catch {
            let recovery = url.deletingLastPathComponent().appendingPathComponent("Drafts-recovery-\(UUID().uuidString).json")
            do {
                try FileManager.default.copyItem(at: url, to: recovery)
                self.error = "Your form drafts could not be opened. A recovery copy was kept; saved studies are unaffected. \(error.localizedDescription)"
            } catch {
                writesAllowed = false
                self.error = "Your form drafts could not be opened or backed up. Draft autosave is paused to protect the original file. You can still save your studies normally. \(error.localizedDescription)"
            }
        }
    }
    func value<T: Decodable>(_ type: T.Type, for key: String) -> T? {
        guard let data = values[key] else { return nil }
        do { return try JSONDecoder().decode(type, from: data) }
        catch {
            if let url, !recoveredKeys.contains(key) {
                do {
                    let recovery = url.deletingLastPathComponent().appendingPathComponent("Drafts-recovery-\(UUID().uuidString).bin")
                    try data.write(to: recovery, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    recoveredKeys.insert(key)
                } catch {
                    writesAllowed = false
                    self.error = "A draft could not be restored or backed up. Draft autosave is paused to protect its original file. You can still save your studies normally."
                    return nil
                }
            }
            self.error = "A draft could not be restored. Saved studies are unaffected; its original draft data has been retained."
            return nil
        }
    }
    func begin(_ key: String, lease: UUID) { leases[key] = lease }
    func consume(_ key: String) { leases.removeValue(forKey: key); remove(key) }
    func stage<T: Encodable>(_ value: T, for key: String, lease: UUID? = nil) {
        if let lease, leases[key] != lease { return }
        do { values[key] = try JSONEncoder().encode(value); dirty = true; schedule() }
        catch { self.error = "Your draft could not be saved: \(error.localizedDescription)" }
    }
    func remove(_ key: String) { guard values.removeValue(forKey: key) != nil else { return }; dirty = true; flush() }
    private func schedule() {
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
            self?.flush()
        }
    }
    func flush() {
        pending?.cancel(); pending = nil
        guard dirty, let url, writesAllowed else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(values).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            dirty = false
        } catch { self.error = "Draft autosave failed. Keep this form open and try saving it. \(error.localizedDescription)" }
    }
}
