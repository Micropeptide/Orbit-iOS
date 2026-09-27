import Foundation

/// orbit:// links, from a notification, a push (its Click), a Shortcut or another app:
///
///   orbit://pair?url=…&token=…        pair with a Mac (asks first if already paired)
///   orbit://chat/<id>                 open that chat
///   orbit://new?text=…                a new chat, with the text waiting in its box
///   orbit://scheduled | files | library | settings    that tab
extension AppState {
    @discardableResult
    func handle(url: URL) -> Bool {
        guard url.scheme == "orbit" else { return false }
        switch url.host ?? "" {
        case "pair":
            return pair(from: url)
        case "chat":
            let sid = url.pathComponents.dropFirst().first ?? ""
            guard !sid.isEmpty, isPaired else { return false }
            tab = "chats"; deepLink = sid
            return true
        case "new":
            guard isPaired else { return false }
            let text = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "text" }?.value ?? ""
            Task {
                guard let sid = await newChat() else { return }
                // the words wait in the box: a link never sends on its own
                if !text.isEmpty { Drafts.save(sid, String(text.prefix(20_000))) }
                tab = "chats"; deepLink = sid
            }
            return true
        case "scheduled", "files", "library", "settings", "chats":
            tab = url.host!
            return true
        default:
            return false
        }
    }

    /// A reply typed on a notification: it joins that chat's queue on the Mac, which
    /// sends it straight away when the chat is free. The app may be running only in the
    /// background for this, so it goes as one request, not a stream to follow.
    func replyFromNotification(sid: String, text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        for _ in 0..<40 where server == nil { try? await Task.sleep(for: .milliseconds(100)) }
        guard let server else { return }
        do {
            try await server.queue(sid: sid, op: "add", ["text": t])
            toast("Sent")
        } catch {
            toast("Couldn't send that: " + error.localizedDescription)
        }
    }

    /// A question answered from its notification.
    func answerFromNotification(questionID: String, text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !questionID.isEmpty else { return }
        for _ in 0..<40 where server == nil { try? await Task.sleep(for: .milliseconds(100)) }
        guard let server else { return }
        do {
            try await server.answerQuestion(questionID, answer: [t], multiple: false)
            if chatExtras.question?.id == questionID { chatExtras.question = nil }
            toast("Answered")
        } catch {
            toast("That question had already been answered")
        }
    }
}
