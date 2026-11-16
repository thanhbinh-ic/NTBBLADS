import Foundation
import SafariServices
import BackgroundTasks

/// Một bộ lọc: nhập tay (url == nil) hoặc đăng ký qua link.
struct FilterList: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var url: String?
    var enabled: Bool
    var lastUpdated: Date?
    var ruleCount: Int
    var skippedCount: Int

    var isManual: Bool { url == nil }
}

/// Quản lý các bộ lọc: lưu trong App Group, tải qua link, biên dịch ra blockerList.json.
final class FilterStore: ObservableObject {
    static let groupID = "group.ic.thanhbinh.CustomBlocker"
    static let extensionID = "ic.thanhbinh.CustomBlocker.Blocker"
    static let maxRules = 50000
    static let refreshTaskID = "ic.thanhbinh.CustomBlocker.refresh"
    static let updateInterval: TimeInterval = 24 * 3600

    @Published var lists: [FilterList] = []
    @Published var status: String = ""
    @Published var isWorking = false
    @Published var appliedRules = 0
    @Published var truncatedCount = 0

    private var groupURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupID)
    }

    private var manifestURL: URL? { groupURL?.appendingPathComponent("lists.json") }
    private var compiledURL: URL? { groupURL?.appendingPathComponent("blockerList.json") }

    private func textURL(for id: String) -> URL? {
        groupURL?.appendingPathComponent("lists").appendingPathComponent("\(id).txt")
    }

    // MARK: - Nạp / lưu

    func load() {
        guard let manifestURL = manifestURL,
              let data = try? Data(contentsOf: manifestURL),
              let saved = try? JSONDecoder().decode([FilterList].self, from: data),
              !saved.isEmpty else {
            seedDefaults()
            return
        }
        lists = saved
        // Nhập tay từ bản v1.0 (filters.txt) nếu chưa có list manual.
        if !lists.contains(where: { $0.isManual }),
           let legacy = groupURL?.appendingPathComponent("filters.txt"),
           let text = try? String(contentsOf: legacy, encoding: .utf8) {
            let manual = FilterList(id: "manual", name: "Bộ lọc của tôi", url: nil,
                                    enabled: true, lastUpdated: nil, ruleCount: 0, skippedCount: 0)
            lists.insert(manual, at: 0)
            saveText(text, for: "manual")
            saveManifest()
        }
    }

    private func saveManifest() {
        guard let manifestURL = manifestURL,
              let data = try? JSONEncoder().encode(lists) else { return }
        try? FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func saveText(_ text: String, for id: String) {
        guard let url = textURL(for: id) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func loadText(for id: String) -> String? {
        guard let url = textURL(for: id) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    func manualText() -> String {
        loadText(for: "manual") ?? ""
    }

    func saveManualText(_ text: String) {
        saveText(text, for: "manual")
        if let index = lists.firstIndex(where: { $0.id == "manual" }) {
            lists[index].lastUpdated = Date()
        }
        saveManifest()
        rebuild()
    }

    // MARK: - Mặc định từ file đính kèm

    /// Lần đầu mở app: đọc DefaultLists.txt trong bundle (file block_ads.txt của huynh).
    /// Dòng "Tên: https://..." -> list đăng ký; dòng còn lại -> luật nhập tay mặc định.
    private func seedDefaults() {
        var subscriptions: [FilterList] = []
        var manualLines: [String] = []
        if let url = Bundle.main.url(forResource: "DefaultLists", withExtension: "txt"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            for rawLine in content.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                if let sub = parseSubscriptionLine(line) {
                    subscriptions.append(sub)
                } else {
                    manualLines.append(line)
                }
            }
        }
        let manual = FilterList(id: "manual", name: "Bộ lọc của tôi", url: nil,
                                enabled: true, lastUpdated: nil, ruleCount: 0, skippedCount: 0)
        lists = [manual] + subscriptions
        // Giữ lại bộ lọc tay của bản v1.0 (filters.txt) nếu có, thay vì đè bằng mẫu mặc định.
        var manualText: String
        if let legacy = groupURL?.appendingPathComponent("filters.txt"),
           let legacyText = try? String(contentsOf: legacy, encoding: .utf8),
           !legacyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            manualText = legacyText
        } else {
            manualText = "# Bộ lọc của tôi — mỗi dòng 1 luật, dòng # là ghi chú\n"
            manualText += manualLines.joined(separator: "\n")
            if !manualLines.isEmpty { manualText += "\n" }
        }
        saveText(manualText, for: "manual")
        saveManifest()
        rebuild()
    }

    private func parseSubscriptionLine(_ line: String) -> FilterList? {
        // Dạng "Tên: https://..." — tên không chứa ký tự của luật lọc.
        guard let range = line.range(of: ": https://", options: .literal)
              ?? line.range(of: ": http://", options: .literal) else {
            return nil
        }
        let name = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
        let url = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, URL(string: url) != nil else { return nil }
        return FilterList(id: UUID().uuidString, name: name, url: url,
                          enabled: true, lastUpdated: nil, ruleCount: 0, skippedCount: 0)
    }

    // MARK: - Thêm / xóa list

    func addSubscription(name: String, urlString: String, completion: @escaping (String?) -> Void) {
        guard let url = URL(string: urlString), url.scheme == "http" || url.scheme == "https" else {
            completion("Link không hợp lệ (cần http:// hoặc https://).")
            return
        }
        let list = FilterList(id: UUID().uuidString, name: name.isEmpty ? url.host ?? urlString : name,
                              url: urlString, enabled: true, lastUpdated: nil, ruleCount: 0, skippedCount: 0)
        isWorking = true
        fetchText(from: url) { [weak self] result in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.isWorking = false
                switch result {
                case .failure(let error):
                    completion("Không tải được list: \(error.localizedDescription)")
                case .success(let text):
                    self.lists.append(list)
                    self.saveText(text, for: list.id)
                    self.saveManifest()
                    self.rebuild()
                    completion(nil)
                }
            }
        }
    }

    func removeList(id: String) {
        lists.removeAll { $0.id == id }
        if let url = textURL(for: id) { try? FileManager.default.removeItem(at: url) }
        saveManifest()
        rebuild()
    }

    func setEnabled(id: String, enabled: Bool) {
        if let index = lists.firstIndex(where: { $0.id == id }) {
            lists[index].enabled = enabled
            saveManifest()
            rebuild()
        }
    }

    // MARK: - Tải cập nhật

    private func fetchText(from url: URL, completion: @escaping (Result<String, Error>) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("CustomBlocker/1.0 (Safari Content Blocker)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error { completion(.failure(error)); return }
            guard let data = data,
                  let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                completion(.failure(NSError(domain: "CustomBlocker", code: 2,
                                            userInfo: [NSLocalizedDescriptionKey: "Máy chủ trả mã lỗi"])))
                return
            }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            completion(.success(text))
        }.resume()
    }

    /// Cập nhật các list đã quá hạn (mặc định 24h). force = true: cập nhật tất cả.
    func updateStaleLists(force: Bool = false, completion: (([String]) -> Void)? = nil) {
        let now = Date()
        let targets = lists.filter { list in
            guard let urlString = list.url, list.enabled, URL(string: urlString) != nil else { return false }
            if force { return true }
            guard let last = list.lastUpdated else { return true }
            return now.timeIntervalSince(last) >= Self.updateInterval
        }
        if targets.isEmpty {
            completion?([])
            return
        }
        isWorking = true
        var failed: [String] = []
        let failedLock = NSLock()
        let group = DispatchGroup()
        for list in targets {
            guard let url = URL(string: list.url!) else { continue }
            group.enter()
            fetchText(from: url) { [weak self] result in
                defer { group.leave() }
                guard let self = self else { return }
                switch result {
                case .success(let text):
                    self.saveText(text, for: list.id)
                    if let index = self.lists.firstIndex(where: { $0.id == list.id }) {
                        self.lists[index].lastUpdated = now
                    }
                case .failure:
                    failedLock.lock()
                    failed.append(list.name)
                    failedLock.unlock()
                }
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isWorking = false
            self.saveManifest()
            self.rebuild()
            completion?(failed)
        }
    }

    // MARK: - Biên dịch

    /// Gộp luật từ các list đang bật: khử trùng, whitelist xếp cuối, tối đa 50.000 luật.
    /// Chia đều: mỗi list được lấy trước 1 phần bằng nhau, còn thừa thì lấy tiếp theo thứ tự ưu tiên.
    static func compile(perListRules: [[[String: Any]]], maxRules: Int = maxRules) -> (rules: [[String: Any]], truncated: Int) {
        var seen = Set<String>()
        var blocksPerList: [[[String: Any]]] = []
        var whitelists: [[String: Any]] = []
        for rules in perListRules {
            var blocks: [[String: Any]] = []
            for rule in rules {
                let key = ruleKey(rule)
                if seen.contains(key) { continue }
                seen.insert(key)
                if (rule["action"] as? [String: Any])?["type"] as? String == "ignore-previous-rules" {
                    whitelists.append(rule)
                } else {
                    blocks.append(rule)
                }
            }
            blocksPerList.append(blocks)
        }
        let cap = max(0, maxRules - whitelists.count)
        // Lượt 1: mỗi list lấy tối đa quota = cap / số list (để list nào cũng có phần).
        let quota = cap / max(1, blocksPerList.count)
        var kept: [[String: Any]] = []
        var leftovers: [[String: Any]] = []
        for blocks in blocksPerList {
            kept.append(contentsOf: blocks.prefix(quota))
            leftovers.append(contentsOf: blocks.dropFirst(quota))
        }
        // Lượt 2: còn chỗ thì lấy tiếp theo thứ tự ưu tiên.
        if kept.count < cap {
            kept.append(contentsOf: leftovers.prefix(cap - kept.count))
        }
        let totalBlocks = blocksPerList.reduce(0) { $0 + $1.count }
        return (kept + whitelists, totalBlocks - kept.count)
    }

    private static func ruleKey(_ rule: [String: Any]) -> String {
        FilterEngine.jsonString(from: [rule])
    }

    /// Biên dịch lại từ text các list đang bật, ghi blockerList.json, nạp lại cho Safari.
    func rebuild() {
        guard groupURL != nil else {
            status = "Lỗi: App Groups chưa khả dụng với chứng chỉ đang ký app này."
            return
        }
        let snapshot = lists
        isWorking = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var perListRules: [[[String: Any]]] = []
            var totalSkipped = 0
            var counts: [(id: String, rules: Int, skipped: Int)] = []
            for list in snapshot where list.enabled {
                let text = self.loadText(for: list.id) ?? ""
                let result = FilterEngine.translate(text: text)
                perListRules.append(result.rules)
                totalSkipped += result.skipped
                counts.append((list.id, result.rules.count, result.skipped))
            }
            let compiled = Self.compile(perListRules: perListRules)
            let json = FilterEngine.jsonString(from: compiled.rules)
            if let url = self.compiledURL {
                try? json.write(to: url, atomically: true, encoding: .utf8)
            }
            DispatchQueue.main.async {
                for count in counts {
                    if let index = self.lists.firstIndex(where: { $0.id == count.id }) {
                        self.lists[index].ruleCount = count.rules
                        self.lists[index].skippedCount = count.skipped
                    }
                }
                self.isWorking = false
                self.appliedRules = compiled.rules.count
                self.truncatedCount = compiled.truncated
                self.saveManifest()
                SFContentBlockerManager.reloadContentBlocker(withIdentifier: Self.extensionID) { error in
                    DispatchQueue.main.async {
                        if let error = error {
                            self.status = "Đã lưu nhưng Safari báo lỗi khi nạp lại: \(error.localizedDescription)"
                        } else if compiled.truncated > 0 {
                            self.status = "Đã áp dụng \(compiled.rules.count) luật, nhưng phải bỏ \(compiled.truncated) luật vì Safari chỉ cho tối đa 50.000 luật — tắt bớt danh sách lớn để đủ chỗ."
                        } else {
                            self.status = "Đã áp dụng \(compiled.rules.count) luật (\(totalSkipped) dòng không hỗ trợ đã bỏ qua)."
                        }
                    }
                }
            }
        }
    }

    // MARK: - Cập nhật nền

    static func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskID, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            let store = FilterStore()
            store.load()
            refreshTask.expirationHandler = { refreshTask.setTaskCompleted(success: false) }
            store.updateStaleLists {
                refreshTask.setTaskCompleted(success: true)
                scheduleRefresh()
            }
        }
    }

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: updateInterval)
        try? BGTaskScheduler.shared.submit(request)
    }
}
