import Foundation

/// Bộ dịch ABP/uBlock -> JSON content-blocker của Safari.
/// Mirror của /tmp/abp.js — cùng thuật toán, để kiểm chứng trên Linux bằng Node.
///
/// Hỗ trợ: ||domain, pattern chuỗi, regex /.../, ## ẩn phần tử, @@ whitelist,
/// hosts-format, bare domain, $third-party/$script/$image/.../$domain=...
/// Bỏ qua: redirect/csp/replace/scriptlet/#@#/#?#/$badfilter/$popup/... (không diễn đạt được).
enum FilterEngine {

    // MARK: - Kết quả

    struct BuildResult {
        let json: String
        let ruleCount: Int
        let errors: [String]
    }

    struct LenientResult {
        let rules: [[String: Any]]
        let skipped: Int
        let skippedReasons: [String: Int]
    }

    enum Translation {
        case rule([String: Any])
        case skip(String)
        case none
    }

    // MARK: - API dùng chung

    /// Chế độ chặt (nhập tay): dòng nào không dịch được là lỗi, không áp dụng.
    static func build(from text: String) -> BuildResult {
        var rules: [[String: Any]] = []
        var errors: [String] = []
        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            switch translateLine(rawLine) {
            case .none:
                continue
            case .rule(let rule):
                rules.append(rule)
            case .skip(let reason):
                errors.append("Dòng \(index + 1): \(reason)")
            }
        }
        if rules.count > 50000 {
            errors.append("Quá 50.000 luật — Safari không biên dịch được, hãy bớt lại.")
            return BuildResult(json: "[]", ruleCount: 0, errors: errors)
        }
        return BuildResult(json: jsonString(from: rules), ruleCount: rules.count, errors: errors)
    }

    /// Chế độ mềm (list đăng ký): dòng không hỗ trợ thì bỏ qua, đếm lại.
    static func translate(text: String) -> LenientResult {
        var rules: [[String: Any]] = []
        var skipped = 0
        var reasons: [String: Int] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            switch translateLine(rawLine) {
            case .none:
                continue
            case .rule(let rule):
                rules.append(rule)
            case .skip(let reason):
                skipped += 1
                reasons[reason, default: 0] += 1
            }
        }
        return LenientResult(rules: rules, skipped: skipped, skippedReasons: reasons)
    }

    static func jsonString(from rules: [[String: Any]]) -> String {
        // JSON gọn (không pretty-print) để file 50.000 luật không quá nặng.
        let data = try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    // MARK: - Dịch 1 dòng

    static func translateLine(_ rawLine: String) -> Translation {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return .none }
        if line.hasPrefix("!") || line.hasPrefix("[") { return .none }
        // '#' đơn là ghi chú (vd. file hosts), nhưng '##' là luật ẩn phần tử.
        if line.hasPrefix("#") && !line.hasPrefix("##") { return .none }

        // --- Ẩn phần tử: ## / #@# / #?# / #+js ---
        if let hashIndex = line.firstIndex(of: "#") {
            let after = String(line[hashIndex...])
            if after.hasPrefix("#@#") || after.hasPrefix("#?#") || after.hasPrefix("#+js") {
                return .skip("không hỗ trợ \(String(after.prefix(4)))")
            }
            if after.hasPrefix("##") {
                let left = String(line[..<hashIndex]).trimmingCharacters(in: .whitespaces)
                let selector = String(after.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if selector.isEmpty { return .skip("thiếu selector sau ##") }
                if selector.contains(":has(") || selector.contains(":has-text(")
                    || selector.contains(":style(") || selector.contains(":xpath(")
                    || selector.contains(":matches-css(") || selector.contains(":contains(") {
                    return .skip("selector procedural không hỗ trợ")
                }
                var trigger: [String: Any] = ["url-filter": ".*"]
                if !left.isEmpty {
                    let domains = left.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty && !$0.contains("*") && isValidDomain($0) }
                    if !domains.isEmpty { trigger["if-domain"] = domains }
                }
                return .rule(["trigger": trigger, "action": ["type": "css-display-none", "selector": selector]])
            }
            // '#' lẻ trong pattern khác: rơi xuống xử lý pattern thường.
        }

        // --- Whitelist @@ ---
        var isWhitelist = false
        var rest = line
        if rest.hasPrefix("@@") {
            isWhitelist = true
            rest = String(rest.dropFirst(2))
        }

        // --- Regex thuần /.../ ---
        // Lưu ý: '$' neo cuối regex đứng TRƯỚC '/' đóng, nên phải tách options sau '/' đóng,
        // không được tách ở '$' đầu tiên.
        if rest.hasPrefix("/") {
            if let ro = splitRegexOptions(rest) {
                let inner = String(ro.pattern.dropFirst().dropLast())
                if looksLikeRegex(inner) {
                    guard isValidRegex(inner), inner.count <= 1000 else {
                        return .skip(isValidRegex(inner) ? "regex quá dài" : "regex lỗi")
                    }
                    let opt: ParsedOptions
                    if let tokens = ro.options {
                        switch parseOptions(tokens) {
                        case .skip(let reason): return .skip(reason)
                        case .ok(let parsed): opt = parsed
                        }
                    } else {
                        opt = ParsedOptions()
                    }
                    var trigger: [String: Any] = ["url-filter": inner]
                    applyOptions(&trigger, opt)
                    return .rule(["trigger": trigger, "action": ["type": isWhitelist ? "ignore-previous-rules" : "block"]])
                }
            }
            // Không phải regex thuần -> pattern chuỗi thường (giữ nguyên cả dòng, kể cả '/').
            let split = splitOptions(rest)
            return patternRule(pattern: split.pattern, options: split.options, isWhitelist: isWhitelist)
        }

        // --- Hosts-format: 0.0.0.0 domain ---
        if let host = parseHostsLine(rest) {
            if !isValidDomain(host) || host == "localhost" { return .skip("hosts line không hợp lệ") }
            let trigger: [String: Any] = [
                "url-filter": "^https?://([^/]*\\.)?" + escapeDots(host),
                "load-type": ["third-party"]
            ]
            return .rule(["trigger": trigger, "action": ["type": "block"]])
        }

        // --- Tách options rồi xử lý pattern ---
        let split = splitOptions(rest)
        let opt: ParsedOptions
        if let tokens = split.options {
            switch parseOptions(tokens) {
            case .skip(let reason): return .skip(reason)
            case .ok(let parsed): opt = parsed
            }
        } else {
            opt = ParsedOptions()
        }
        let pattern = split.pattern

        // --- ||domain[/path] ---
        if pattern.hasPrefix("||") {
            var target = String(pattern.dropFirst(2))
            var sepAfterDomain = false
            if target.hasSuffix("^") {
                target = String(target.dropLast())
                sepAfterDomain = true
            }
            if target.isEmpty { return .skip("luật trống") }
            let slashIndex = target.firstIndex(of: "/")
            let domainRaw = slashIndex.map { String(target[..<$0]) } ?? target
            let domain = domainRaw.hasPrefix("*.") ? String(domainRaw.dropFirst(2)) : domainRaw
            if !isValidDomain(domain) {
                return .skip("domain không hợp lệ: \(domain)")
            }
            var regex = "^https?://([^/]*\\.)?" + escapeDots(domain)
            if let slashIndex = slashIndex {
                regex += patternToRegex(String(target[slashIndex...]))
            } else if sepAfterDomain {
                regex += separatorClass
            }
            if regex.count > 1000 { return .skip("pattern quá dài") }
            var trigger: [String: Any] = ["url-filter": regex]
            // Chỉ domain trần (không path): mặc định chỉ chặn third-party.
            if slashIndex == nil && opt.loadType == nil { trigger["load-type"] = ["third-party"] }
            applyOptions(&trigger, opt)
            return .rule(["trigger": trigger, "action": ["type": isWhitelist ? "ignore-previous-rules" : "block"]])
        }

        // --- Bare domain ---
        if isValidDomain(pattern) {
            var trigger: [String: Any] = [
                "url-filter": "^https?://([^/]*\\.)?" + escapeDots(pattern),
                "load-type": ["third-party"]
            ]
            applyOptions(&trigger, opt)
            return .rule(["trigger": trigger, "action": ["type": isWhitelist ? "ignore-previous-rules" : "block"]])
        }

        // --- Pattern chuỗi thường ---
        return patternRule(pattern: pattern, options: split.options, isWhitelist: isWhitelist)
    }

    private static func patternRule(pattern: String, options: [String]?, isWhitelist: Bool) -> Translation {
        if pattern == "*" {
            var trigger: [String: Any] = ["url-filter": ".*"]
            if let tokens = options {
                switch parseOptions(tokens) {
                case .skip(let reason): return .skip(reason)
                case .ok(let parsed): applyOptions(&trigger, parsed)
                }
            }
            return .rule(["trigger": trigger, "action": ["type": isWhitelist ? "ignore-previous-rules" : "block"]])
        }
        // '|' giữa pattern mà không phải anchor -> không hỗ trợ.
        let inner = pattern.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
        if inner.contains("|") { return .skip("pattern chứa | không hỗ trợ") }
        let regex = patternToRegex(pattern)
        guard !regex.isEmpty, regex.count <= 1000, isValidRegex(regex) else {
            return .skip(regex.isEmpty ? "pattern quá dài/rỗng" : "pattern lỗi")
        }
        var trigger: [String: Any] = ["url-filter": regex]
        if let tokens = options {
            switch parseOptions(tokens) {
            case .skip(let reason): return .skip(reason)
            case .ok(let parsed): applyOptions(&trigger, parsed)
            }
        }
        return .rule(["trigger": trigger, "action": ["type": isWhitelist ? "ignore-previous-rules" : "block"]])
    }

    // MARK: - Pattern -> regex

    static let separatorClass = "(?:[^A-Za-z0-9_\\-.%]|$)"

    /// '*' -> .*, '^' -> separator, '|' đầu -> ^, '|' cuối -> $.
    static func patternToRegex(_ pattern: String) -> String {
        var p = pattern
        var anchoredStart = false
        var anchoredEnd = false
        if p.hasPrefix("|") { anchoredStart = true; p = String(p.dropFirst()) }
        if p.hasSuffix("|") { anchoredEnd = true; p = String(p.dropLast()) }
        var out = ""
        for ch in p {
            if ch == "*" { out += ".*" }
            else if ch == "^" { out += separatorClass }
            else { out += escapeRegexChar(ch) }
        }
        if anchoredStart { out = "^" + out }
        if anchoredEnd { out += "$" }
        return out
    }

    private static func escapeRegexChar(_ ch: Character) -> String {
        "\\^$.|?*+()[]{}".contains(ch) ? "\\\(ch)" : String(ch)
    }

    private static func escapeDots(_ domain: String) -> String {
        domain.replacingOccurrences(of: ".", with: "\\.")
    }

    private static func looksLikeRegex(_ inner: String) -> Bool {
        inner.contains("\\") || inner.contains("(?:") || inner.contains("(?")
            || inner.contains("[") || inner.contains("{") || inner.contains("|")
            || inner.contains("^") || inner.contains("$") || inner.contains("+")
    }

    private static func isValidRegex(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }

    private static func isValidDomain(_ domain: String) -> Bool {
        guard !domain.isEmpty, domain.contains("."), !domain.contains(" "),
              !domain.contains("*"), !domain.contains("/") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
        return domain.unicodeScalars.allSatisfy { allowed.contains($0) }
            && !domain.hasPrefix(".") && !domain.hasSuffix(".")
            && !domain.hasPrefix("-") && !domain.contains("..")
    }

    private static func parseHostsLine(_ line: String) -> String? {
        for prefix in ["0.0.0.0 ", "127.0.0.1 "] {
            if line.hasPrefix(prefix) {
                let rest = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
                return rest.split(separator: " ", maxSplits: 1).first.map(String.init)
            }
        }
        return nil
    }

    // MARK: - $options

    struct ParsedOptions {
        var loadType: String? = nil
        var resourceTypes: [String]? = nil
        var ifDomain: [String]? = nil
        var unlessDomain: [String]? = nil
    }

    enum ParsedOptionsResult {
        case ok(ParsedOptions)
        case skip(String)
    }

    private static let resourceMap: [String: String] = [
        "script": "script", "image": "image", "stylesheet": "style", "css": "style",
        "font": "font", "media": "media", "xmlhttprequest": "raw", "xhr": "raw",
        "other": "raw", "ping": "raw", "websocket": "raw", "object": "raw",
        "subdocument": "document", "frame": "document", "document": "document", "doc": "document",
    ]

    private static let unsupportedOptions: Set<String> = [
        "redirect", "redirect-rule", "csp", "replace", "removeparam", "cookie",
        "permissions", "method", "to", "from", "ipaddress", "header",
        "generichide", "genericblock", "elemhide", "webrtc", "popup", "badfilter",
        "empty", "mp4", "app", "inline-script", "inline-font", "denyallow", "urlskip",
    ]

    private static let knownOptions: Set<String> = {
        var s = Set(resourceMap.keys)
        s.formUnion(["third-party", "3p", "first-party", "1p", "domain", "important",
                     "match-case", "all"])
        s.formUnion(unsupportedOptions)
        return s
    }()

    /// Tách $options sau '/' đóng của regex /.../. Trả nil nếu không phải dạng regex.
    private static func splitRegexOptions(_ line: String) -> (pattern: String, options: [String]?)? {
        guard let lastSlash = line.lastIndex(of: "/"), lastSlash > line.startIndex else {
            return nil
        }
        let after = String(line[line.index(after: lastSlash)...])
        if after.isEmpty {
            return (line, nil)
        }
        if after.hasPrefix("$") {
            let tokens = String(after.dropFirst()).split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            return (String(line[...lastSlash]), tokens)
        }
        return nil
    }

    /// Tách $options ở cuối dòng. Trả options nil nếu $ là ký tự thường.
    private static func splitOptions(_ line: String) -> (pattern: String, options: [String]?) {
        guard let dollarIndex = line.firstIndex(of: "$") else {
            return (line, nil)
        }
        let rest = String(line[line.index(after: dollarIndex)...])
        let tokens = rest.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard let first = tokens.first,
              let parsed = parseOptionToken(first),
              knownOptions.contains(parsed.name) else {
            return (line, nil)
        }
        return (String(line[..<dollarIndex]), tokens)
    }

    /// Parse 1 token option: [~]tên[=giá trị]. Trả nil nếu không đúng dạng.
    private static func parseOptionToken(_ token: String) -> (negated: Bool, name: String, value: String?)? {
        var t = token
        var negated = false
        if t.hasPrefix("~") {
            negated = true
            t = String(t.dropFirst())
        }
        let parts = t.split(separator: "=", maxSplits: 1).map(String.init)
        guard let name = parts.first, !name.isEmpty,
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            return nil
        }
        return (negated, name, parts.count > 1 ? parts[1] : nil)
    }

    private static func parseOptions(_ tokens: [String]) -> ParsedOptionsResult {
        var parsed = ParsedOptions()
        var resourceTypes = Set<String>()
        var ifDomain: [String] = []
        var unlessDomain: [String] = []
        for token in tokens {
            guard let opt = parseOptionToken(token) else {
                return .skip("option lạ: \(token)")
            }
            let name = opt.name
            if unsupportedOptions.contains(name) {
                return .skip("không hỗ trợ $\(name)")
            }
            if name == "domain" {
                guard let value = opt.value else { return .skip("$domain thiếu giá trị") }
                for entry in value.split(separator: "|").map(String.init) {
                    if entry.isEmpty { continue }
                    if entry.hasPrefix("~") {
                        let dom = String(entry.dropFirst())
                        if !dom.contains("*") { unlessDomain.append(dom) }
                    } else if !entry.contains("*") {
                        ifDomain.append(entry)
                    }
                }
                continue
            }
            if name == "important" || name == "match-case" || name == "all" { continue }
            if name == "third-party" || name == "3p" {
                parsed.loadType = opt.negated ? "first-party" : "third-party"
                continue
            }
            if name == "first-party" || name == "1p" {
                parsed.loadType = opt.negated ? "third-party" : "first-party"
                continue
            }
            if let mapped = resourceMap[name] {
                if opt.negated { return .skip("không hỗ trợ ~\(name)") }
                resourceTypes.insert(mapped)
                continue
            }
            return .skip("option lạ: \(name)")
        }
        if !resourceTypes.isEmpty { parsed.resourceTypes = Array(resourceTypes).sorted() }
        if !ifDomain.isEmpty { parsed.ifDomain = ifDomain }
        if !unlessDomain.isEmpty { parsed.unlessDomain = unlessDomain }
        return .ok(parsed)
    }

    private static func applyOptions(_ trigger: inout [String: Any], _ opt: ParsedOptions) {
        if let loadType = opt.loadType { trigger["load-type"] = [loadType] }
        if let resourceTypes = opt.resourceTypes { trigger["resource-type"] = resourceTypes }
        if let ifDomain = opt.ifDomain { trigger["if-domain"] = ifDomain }
        if let unlessDomain = opt.unlessDomain { trigger["unless-domain"] = unlessDomain }
    }
}
