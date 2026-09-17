import Foundation

/// The shapes Orbit's HTTP API speaks. Kept deliberately close to the JSON so
/// there is one obvious place to look when the server changes.

struct Pairing: Codable, Equatable {
    var url: String          // http://host:port, no trailing slash
    var token: String
    var name: String         // the Mac's name, for the UI
    /// Other addresses the same Mac answers on; tried when `url` fails.
    var alts: [String]? = nil

    var base: URL? { URL(string: url) }
}

struct ChatSummary: Identifiable, Codable, Hashable {
    let id: String
    var title: String?
    var n: Int
    var mtime: Double
    var pinned: Bool?
    var archived: Bool?
    var project: String?
    var tags: [String]?

    var displayTitle: String { (title?.isEmpty == false ? title! : "New chat") }
    var date: Date { Date(timeIntervalSince1970: mtime) }

    enum CodingKeys: String, CodingKey {
        case id, title, n, mtime, pinned, archived, project, tags
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        n = (try? c.decode(Int.self, forKey: .n)) ?? 0
        mtime = (try? c.decode(Double.self, forKey: .mtime)) ?? 0
        pinned = try? c.decode(Bool.self, forKey: .pinned)
        archived = try? c.decode(Bool.self, forKey: .archived)
        project = try? c.decode(String.self, forKey: .project)
        tags = try? c.decode([String].self, forKey: .tags)
    }
}

struct ChatList: Codable {
    var items: [ChatSummary]
    var total: Int?
}

/// One turn as the server stores it. `model` is the byline: which model wrote it.
struct Message: Identifiable, Codable, Hashable {
    var id = UUID()
    var role: String
    var text: String
    var images: [String]?
    var plots: [String]?
    var tools: [String]?
    var model: String?
    /// Reasoning, when the model exposes it — from a live answer, or recovered
    /// from a completed or stopped-mid-stream one the Mac saved.
    var thinking: String?
    /// A note sent while an answer was running, which it read at its next step.
    var note: Bool? = nil

    var isUser: Bool { role == "user" }

    enum CodingKeys: String, CodingKey { case role, text, images, plots, tools, model, thinking, note }
}

struct ChatDetail: Codable {
    var sid: String
    var title: String?
    var messages: [Message]
    /// Raw message count on the Mac (system and tool records included) — the
    /// number the change watcher compares against.
    var n: Int?
    var running: Bool?
    var context: ContextState?
}

struct ContextState: Codable, Hashable {
    var used: Int
    var max: Int
    var pct: Double
    var basis: String?
}

struct ModelInfo: Identifiable, Codable, Hashable {
    var id: String
    var label: String?
    var model: String
    var provider: String
    var provider_label: String?
    var ready: Bool?
    var context: Int?
    var note: String?

    var display: String { label ?? model }
    var isReady: Bool { ready ?? true }
    /// The group a picker files it under. Harness groups (Codex, Claude Code)
    /// can arrive without a provider of their own, so fall back to the id's prefix.
    var group: String {
        if let p = provider_label, !p.isEmpty { return p }
        if !provider.isEmpty { return provider }
        return id.split(separator: ":").first.map(String.init) ?? "other"
    }

    enum CodingKeys: String, CodingKey {
        case id, label, model, provider, provider_label, ready, context, note
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        label = try? c.decode(String.self, forKey: .label)
        // one odd entry must not take the whole list down with it
        model = (try? c.decode(String.self, forKey: .model)) ?? id
        provider = (try? c.decode(String.self, forKey: .provider)) ?? ""
        provider_label = try? c.decode(String.self, forKey: .provider_label)
        ready = try? c.decode(Bool.self, forKey: .ready)
        context = try? c.decode(Int.self, forKey: .context)
        note = try? c.decode(String.self, forKey: .note)
    }
}

struct ModelList: Codable {
    var models: [ModelInfo]
    var current: String?
    var `default`: String?
    /// Which harness new chats use — Claude Code, Codex, or (both false) Orbit's own.
    var harness_mode: Bool?
    var codex_mode: Bool?
    /// The models last used in each harness, newest first.
    var harness_recent: [RecentModel]?
    var codex_recent: [RecentModel]?

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        models = try c.decode([ModelInfo].self, forKey: .models)
        current = try? c.decode(String.self, forKey: .current)
        `default` = try? c.decode(String.self, forKey: .default)
        // newer fields must never cost the model list itself
        harness_mode = c.lenientBool(.harness_mode)
        codex_mode = c.lenientBool(.codex_mode)
        harness_recent = try? c.decode([RecentModel].self, forKey: .harness_recent)
        codex_recent = try? c.decode([RecentModel].self, forKey: .codex_recent)
    }
}

struct RecentModel: Codable, Hashable {
    var id: String
    var label: String?
}

/// The Mac's automatic backup — where it goes and when it last ran.
struct BackupStatus: Codable {
    var enabled: Bool
    var dest: String
    var every_hours: Int
    var keep: Int
    var icloud: Bool
    var in_icloud: Bool
    var count: Int
    var last: BackupEntry?
    var backups: [BackupEntry]?
    var total_bytes: Int?
    var include_workspace: Bool?
    var include_secrets: Bool?
}

struct BackupEntry: Codable, Identifiable, Hashable {
    var name: String
    var bytes: Int
    var mtime: Double
    var id: String { name }
    var date: Date { Date(timeIntervalSince1970: mtime) }
}

/// Something in the Mac's bin, waiting to be purged or put back.
struct TrashItem: Codable, Identifiable, Hashable {
    var name: String
    var kind: String
    var original: String?
    var deleted: Double
    var age_days: Double?
    var purges_in_days: Double?
    var title: String?
    var bytes: Int?

    var id: String { name }
    var displayName: String {
        if let t = title, !t.isEmpty { return t }
        return name.components(separatedBy: "__").last ?? name
    }
    var subtitle: String {
        var bits = [kind == "session" ? "chat" : kind]
        let f = RelativeDateTimeFormatter(); f.unitsStyle = .abbreviated
        bits.append("binned " + f.localizedString(for: Date(timeIntervalSince1970: deleted), relativeTo: .now))
        if let p = purges_in_days { bits.append("purged in \(max(0, Int(p))) d") }
        return bits.joined(separator: " · ")
    }
}

struct ProjectInfo: Identifiable, Hashable {
    var id: String
    var name: String
    var color: String?
    var instructions: String?
}

/// Events the chat stream emits. One case per `k` the server sends.
enum StreamEvent {
    case model(String)               // which model is answering
    case thinking(String)            // reasoning delta
    case content(String)             // answer delta
    case tool(name: String, args: String)
    case toolResult(name: String, output: String)
    case status(String)              // cold start, compaction, trimming
    case blocked(reason: String)
    case autoApproved(name: String, reason: String)
    case approval(name: String, reason: String, id: String?)
    /// Something worth a line in the answer that is not the answer itself —
    /// a fallback to another model, a message put off until later.
    case notice(String)
    case error(String)
    case end(sid: String?, title: String?)
}


/// A hit from searching every conversation, not just their titles.
struct SearchHit: Identifiable, Codable, Hashable {
    var sid: String
    var title: String?
    var role: String
    var index: Int
    /// Position among the messages the app displays (the Mac skips tool
    /// records when it renders). Older Macs only send `index`.
    var row: Int?
    var snippet: String
    var mtime: Double

    var id: String { "\(sid)-\(index)" }
    var rowIndex: Int { row ?? index }
    var chatTitle: String { (title?.isEmpty == false ? title! : "New chat") }
}

// ------------------------------------------------------------------ scheduling

/// Lenient readers for JSON the Mac grows over time: a number may arrive as a
/// string, a missing key is simply nil.
extension KeyedDecodingContainer {
    func lenientString(_ k: Key) -> String? {
        if let s = try? decode(String.self, forKey: k) { return s }
        if let i = try? decode(Int.self, forKey: k) { return String(i) }
        if let d = try? decode(Double.self, forKey: k) { return String(d) }
        return nil
    }
    func lenientDouble(_ k: Key) -> Double? {
        if let d = try? decode(Double.self, forKey: k) { return d }
        if let s = try? decode(String.self, forKey: k) { return Double(s) }
        return nil
    }
    func lenientBool(_ k: Key) -> Bool? {
        if let b = try? decode(Bool.self, forKey: k) { return b }
        if let i = try? decode(Int.self, forKey: k) { return i != 0 }
        return nil
    }
}

/// How often a message sent later goes out again.
enum Repeat: String, CaseIterable, Identifiable {
    case once = "", daily, weekdays, weekly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .once: return "Once"
        case .daily: return "Every day"
        case .weekdays: return "Every weekday"
        case .weekly: return "Every week"
        }
    }
    init(server: String?) { self = Repeat(rawValue: server ?? "") ?? .once }
    /// What the Mac expects: nothing for a one-off.
    var server: Any { self == .once ? NSNull() : rawValue }
}

struct AttachmentRef: Codable, Hashable {
    var name: String?
    var kind: String?
}

/// A message waiting in one chat's queue — now (queued behind a running
/// answer) or at a time you chose.
struct QueueItem: Identifiable, Codable, Hashable {
    var id: String
    var text: String
    var at: Double?
    var repeatKind: String?
    var missed: Bool
    var model: String?
    var attachments: [AttachmentRef]

    var isScheduled: Bool { at != nil }
    var date: Date? { at.map { Date(timeIntervalSince1970: $0) } }

    enum CodingKeys: String, CodingKey { case id, text, at, repeatKind = "repeat", missed, model, attachments }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? UUID().uuidString
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        at = c.lenientDouble(.at)
        repeatKind = try? c.decode(String.self, forKey: .repeatKind)
        missed = c.lenientBool(.missed) ?? false
        model = try? c.decode(String.self, forKey: .model)
        attachments = (try? c.decode([AttachmentRef].self, forKey: .attachments)) ?? []
    }
}

struct QueueState: Codable, Hashable {
    var items: [QueueItem]
    var paused: Bool?
    var running: Bool?

    static let empty = QueueState(items: [], paused: nil, running: nil)
}

/// A message scheduled in some chat, as the Scheduled screen lists them.
struct ScheduledMessage: Identifiable, Codable, Hashable {
    var sid: String
    var title: String?
    var itemID: String
    var text: String
    var at: Double
    var repeatKind: String?
    var missed: Bool
    /// nil = the chat's own model
    var model: String?
    var chat_model: String?
    var attachments: [AttachmentRef]

    var id: String { "\(sid)/\(itemID)" }
    var date: Date { Date(timeIntervalSince1970: at) }
    var chatTitle: String { (title?.isEmpty == false ? title! : "New chat") }

    enum CodingKeys: String, CodingKey {
        case sid, title, itemID = "id", text, at, repeatKind = "repeat", missed, model, chat_model, attachments
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        sid = try c.decode(String.self, forKey: .sid)
        title = try? c.decode(String.self, forKey: .title)
        itemID = c.lenientString(.itemID) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        at = c.lenientDouble(.at) ?? 0
        repeatKind = try? c.decode(String.self, forKey: .repeatKind)
        missed = c.lenientBool(.missed) ?? false
        model = try? c.decode(String.self, forKey: .model)
        chat_model = try? c.decode(String.self, forKey: .chat_model)
        attachments = (try? c.decode([AttachmentRef].self, forKey: .attachments)) ?? []
    }
}

/// A scheduled task: a prompt the Mac runs on its own, on a timetable.
struct ScheduledTask: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var prompt: String
    var every: String            // once | minutes | hours | daily | weekly
    var at: String?              // "HH:MM"
    var at_ts: Double?           // a one-off's moment
    var n: Double?
    var weekday: Int?            // 0 = Monday
    var stop_at: String?
    var model: String?
    var agent: String?
    var sid: String?
    var project: String?
    var enabled: Bool
    var last_run: Double?
    var last_ok: Bool?
    var last_result: String?
    var last_sid: String?
    var next_ts: Double?
    /// Older Macs describe the next run as text ("09:00 Mon") instead.
    var next: String?

    enum CodingKeys: String, CodingKey {
        case id, name, prompt, every, at, at_ts, n, weekday, stop_at, model, agent, sid, project,
             enabled, last_run, last_ok, last_result, last_sid, next_ts, next
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = c.lenientString(.id) ?? ""
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        prompt = (try? c.decode(String.self, forKey: .prompt)) ?? ""
        every = (try? c.decode(String.self, forKey: .every)) ?? "daily"
        at = try? c.decode(String.self, forKey: .at)
        at_ts = c.lenientDouble(.at_ts)
        n = c.lenientDouble(.n)
        weekday = (try? c.decode(Int.self, forKey: .weekday)) ?? c.lenientString(.weekday).flatMap { Int($0) }
        stop_at = try? c.decode(String.self, forKey: .stop_at)
        model = try? c.decode(String.self, forKey: .model)
        agent = try? c.decode(String.self, forKey: .agent)
        sid = try? c.decode(String.self, forKey: .sid)
        project = try? c.decode(String.self, forKey: .project)
        enabled = c.lenientBool(.enabled) ?? true
        last_run = c.lenientDouble(.last_run)
        last_ok = c.lenientBool(.last_ok)
        last_result = try? c.decode(String.self, forKey: .last_result)
        last_sid = try? c.decode(String.self, forKey: .last_sid)
        next_ts = c.lenientDouble(.next_ts)
        next = try? c.decode(String.self, forKey: .next)
    }

    init(new: Void = ()) {
        id = ""; name = ""; prompt = ""; every = "daily"; at = "09:00"; enabled = true
    }

    static let weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// "Every day at 09:00", "Every 30 minutes", "Once, Tue 14:00".
    var scheduleDescription: String {
        switch every {
        case "once":
            if let t = at_ts { return "Once, " + When.describe(Date(timeIntervalSince1970: t)) }
            return "Once"
        case "minutes":
            return "Every \(Int(n ?? 30)) minutes" + (stop_at.map { " until \($0)" } ?? "")
        case "hours":
            let h = Int(n ?? 6)
            return (h == 1 ? "Every hour" : "Every \(h) hours") + (stop_at.map { " until \($0)" } ?? "")
        case "weekly":
            let d = Self.weekdays[max(0, min(6, weekday ?? 0))]
            return "Every \(d) at \(at ?? "09:00")"
        default:
            return "Every day at \(at ?? "09:00")" + (stop_at.map { " until \($0)" } ?? "")
        }
    }

    var nextDescription: String? {
        if !enabled { return "paused" }
        if let t = next_ts { return When.describe(Date(timeIntervalSince1970: t)) }
        if let s = next, !s.isEmpty { return s }
        return nil
    }
}

/// Relative, readable times: "today 21:00", "tomorrow 09:00", "Wed 09:00".
enum When {
    static func describe(_ d: Date, now: Date = .now) -> String {
        let cal = Calendar.current
        let time = d.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(d) { return "today \(time)" }
        if cal.isDateInTomorrow(d) { return "tomorrow \(time)" }
        if cal.isDateInYesterday(d) { return "yesterday \(time)" }
        if let week = cal.date(byAdding: .day, value: 6, to: now), d > now, d < week {
            return d.formatted(.dateTime.weekday(.abbreviated)) + " \(time)"
        }
        return d.formatted(.dateTime.month(.abbreviated).day()) + " \(time)"
    }
}

// ------------------------------------------------------------------ file links

/// A name in an answer, looked up where the chat works.
struct ResolvedPath: Codable, Hashable, Identifiable {
    var exists: Bool
    var path: String?
    var name: String?
    var kind: String?            // file | folder
    var category: String?        // image, pdf, html, markdown, table, code, text, doc, sheet…
    var size: Double?
    var url: String?             // a preview link relative to the Mac, needs no token
    var host: String?
    var line: Int?

    var id: String { path ?? name ?? "?" }
    var displayName: String { name ?? (path as NSString?)?.lastPathComponent ?? "file" }
    var isFolder: Bool { kind == "folder" }

    enum CodingKeys: String, CodingKey { case exists, path, name, kind, category, size, url, host, line }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        exists = c.lenientBool(.exists) ?? false
        path = try? c.decode(String.self, forKey: .path)
        name = try? c.decode(String.self, forKey: .name)
        kind = try? c.decode(String.self, forKey: .kind)
        category = try? c.decode(String.self, forKey: .category)
        size = c.lenientDouble(.size)
        url = try? c.decode(String.self, forKey: .url)
        host = try? c.decode(String.self, forKey: .host)
        line = try? c.decode(Int.self, forKey: .line)
    }
}
