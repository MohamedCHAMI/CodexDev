import Cocoa
import Network
import WebKit

/// Localhost control port used by chatgpt-web-bridge (Codex CLI ↔ ChatGPT web).
///
/// Runs ChatGPT in hidden WKWebViews that share the app's default website data store, so they are
/// already signed in, without touching the visible chat window. Only fixed operations are exposed
/// (open a chat, send text, read state, close) — no arbitrary script execution. Binds 127.0.0.1
/// only, and every request needs the bearer token in ~/.chatgpt-web-bridge/app-token (mode 600).
final class ChatBridgeControl: NSObject, WKNavigationDelegate {
    static let shared = ChatBridgeControl()
    static let port: NWEndpoint.Port = 8791

    private var listener: NWListener?
    private var tabs: [String: WKWebView] = [:]
    private var hostWindow: NSWindow?
    private var pendingLoads: [ObjectIdentifier: [() -> Void]] = [:]
    private let token = ChatBridgeControl.loadOrCreateToken()

    private static func loadOrCreateToken() -> String {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".chatgpt-web-bridge/app-token")
        if let existing = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           !existing.isEmpty {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? value.write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return value
    }

    private var bridgeProcess: Process?

    /// Starts the Node bridge (Codex CLI → this app) if it is installed and not already running,
    /// so `codex dev` works whenever CodexDev is open.
    func startBridgeServer(nodePath: String) {
        let script = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/Works/Apps/chatgpt-web-bridge/src/server.js").path
        guard bridgeProcess == nil, FileManager.default.fileExists(atPath: script),
              FileManager.default.isExecutableFile(atPath: nodePath) else { return }
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        check.arguments = ["-f", "chatgpt-web-bridge/src/server.js"]
        try? check.run()
        check.waitUntilExit()
        if check.terminationStatus == 0 { return } // already running (e.g. started from the CLI)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: nodePath)
        p.arguments = [script]
        p.standardOutput = FileHandle.nullDevice // the bridge writes its own log file
        p.standardError = FileHandle.nullDevice
        do { try p.run(); bridgeProcess = p } catch { NSLog("ChatBridgeControl: bridge start failed: \(error)") }
    }

    func stopBridgeServer() {
        bridgeProcess?.terminate()
        bridgeProcess = nil
    }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: ChatBridgeControl.port)
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params)
            l.newConnectionHandler = { [weak self] conn in
                conn.start(queue: .global(qos: .userInitiated))
                self?.receive(conn, buffer: Data())
            }
            l.start(queue: .global(qos: .userInitiated))
            listener = l
        } catch {
            NSLog("ChatBridgeControl: cannot listen on 8791: \(error)")
        }
    }

    // MARK: - Fixed page scripts (the only code ever run in the hidden tabs)

    /// Page helpers. `sel` (CSS selector lists) is passed in as data from selectors.json; the code itself is fixed.
    private static let pageLib = """
    const q = (list) => { for (const s of list || []) { for (const e of document.querySelectorAll(s)) { if (e.offsetParent !== null) return e; } } return null; };
    const all = (list) => { for (const s of list || []) { const r = document.querySelectorAll(s); if (r.length) return r; } return []; };
    const lastText = () => {
      const msgs = all(sel.assistant); const el = msgs[msgs.length - 1]; if (!el) return '';
      const clone = el.cloneNode(true);
      document.body.appendChild(clone);
      clone.style.position = 'fixed'; clone.style.left = '-99999px'; clone.style.width = '900px';
      const seen = new Set();
      for (const code of [...clone.querySelectorAll((sel.codeBlock || ['pre']).join(','))]) {
        let block = code;
        const body = code.textContent.replace(/\\n$/, '');
        // Climb to the code block's wrapper (header with language label + code), but not past the message text.
        let p = code.parentElement;
        while (p && p !== clone && p.innerText.length < body.length + 60) { block = p; p = p.parentElement; }
        if (seen.has(block)) continue; seen.add(block);
        const fromClass = (code.className.match(/language-([\\w-]+)/) || [])[1];
        const header = block.innerText.replace(code.innerText, '').trim().split('\\n')[0] || '';
        const lang = fromClass || (/^[\\w-]{1,20}$/.test(header) ? header : '');
        // A <pre> keeps the newlines when innerText is read (a bare text node would collapse them).
        const pre = document.createElement('pre');
        pre.textContent = '```' + lang + '\\n' + body + '\\n```';
        block.replaceWith(pre);
      }
      const t = clone.innerText; clone.remove(); return t;
    };
    """

    private static let stateScript = pageLib + """
    const err = q(sel.error);
    return { composer: !!q(sel.composer), loggedOut: !!q(sel.loggedOut), streaming: !!q(sel.stop),
             count: all(sel.assistant).length, lastText: lastText(), error: err ? err.innerText.trim() : '' };
    """

    private static let sendScript = pageLib + """
    const box = q(sel.composer); if (!box) return { ok: false, error: 'composer not found' };
    box.focus();
    document.execCommand('selectAll', false);
    document.execCommand('insertText', false, text);
    await new Promise((r) => setTimeout(r, 500));
    const btn = q(sel.send);
    if (btn && !btn.disabled) btn.click();
    else box.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', keyCode: 13, bubbles: true }));
    return { ok: true };
    """

    /// CSS selector lists, re-read on every call so ChatGPT UI changes need no rebuild.
    private static var selectors: [String: Any] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".chatgpt-web-bridge/selectors.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj.filter { $0.value is [String] }
    }

    // MARK: - HTTP (small JSON requests, one per connection)

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, done, error in
            guard let self = self else { return }
            var buf = buffer
            if let data = data { buf.append(data) }
            if let req = HTTPRequest(buf) {
                self.handle(req) { status, body in self.reply(conn, status: status, body: body) }
            } else if done || error != nil || buf.count > 16 << 20 {
                conn.cancel()
            } else {
                self.receive(conn, buffer: buf)
            }
        }
    }

    private func reply(_ conn: NWConnection, status: Int, body: [String: Any]) {
        let json = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{}".utf8)
        var out = Data("HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n".utf8)
        out.append(json)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func handle(_ req: HTTPRequest, done: @escaping (Int, [String: Any]) -> Void) {
        guard req.headers["authorization"] == "Bearer \(token)" else { return done(401, ["error": "unauthorized"]) }
        let body = (try? JSONSerialization.jsonObject(with: req.body)) as? [String: Any] ?? [:]
        let id = body["id"] as? String ?? "default"
        DispatchQueue.main.async {
            switch (req.method, req.path) {
            case ("GET", "/health"):
                done(200, ["ok": true, "tabs": Array(self.tabs.keys)])
            case ("POST", "/chat/open"):
                // Only chatgpt.com URLs: the bridge cannot point the hidden tabs anywhere else.
                var url = chatGPTURL
                if let s = body["url"] as? String, let u = URL(string: s), u.host == "chatgpt.com" { url = u }
                self.open(id: id, url: url) { done(200, ["ok": true]) }
            case ("POST", "/chat/send"):
                self.run(id, Self.sendScript, ["text": body["text"] as? String ?? "", "sel": Self.selectors], done)
            case ("POST", "/chat/state"):
                self.run(id, Self.stateScript, ["sel": Self.selectors], done)
            case ("POST", "/chat/show"):
                if let wv = self.tabs[id], let w = self.hostWindow {
                    w.contentView = wv
                    w.setFrameOrigin(NSPoint(x: 80, y: 80))
                    w.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                done(200, ["ok": true])
            case ("POST", "/chat/close"):
                self.tabs.removeValue(forKey: id)?.removeFromSuperview()
                done(200, ["ok": true])
            default:
                done(404, ["error": "no route \(req.method) \(req.path)"])
            }
        }
    }

    private func run(_ id: String, _ script: String, _ args: [String: Any], _ done: @escaping (Int, [String: Any]) -> Void) {
        guard let wv = tabs[id] else { return done(404, ["error": "no chat \(id); call /chat/open first"]) }
        wv.callAsyncJavaScript(script, arguments: args, in: nil, in: .page) { result in
            switch result {
            case .success(let value): done(200, ["result": (value as? [String: Any]) ?? [:]])
            case .failure(let err): done(500, ["error": err.localizedDescription])
            }
        }
    }

    // MARK: - Hidden tabs

    private func ensureHostWindow() -> NSWindow {
        if let w = hostWindow { return w }
        // Placed off-screen but ordered in, so WebKit keeps timers and rendering at full speed.
        let w = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1100, height: 900),
                         styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "CodexDev – Codex CLI bridge"
        w.isReleasedWhenClosed = false
        w.orderBack(nil)
        hostWindow = w
        return w
    }

    private func open(id: String, url: URL, completion: @escaping () -> Void) {
        let host = ensureHostWindow()
        let wv: WKWebView
        if let existing = tabs[id] {
            wv = existing
        } else {
            let config = WKWebViewConfiguration()
            config.websiteDataStore = .default() // same cookies/login as the visible chat window
            wv = WKWebView(frame: host.contentRect(forFrameRect: host.frame), configuration: config)
            wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
            wv.navigationDelegate = self
            wv.autoresizingMask = [.width, .height]
            tabs[id] = wv
        }
        host.contentView = wv
        pendingLoads[ObjectIdentifier(wv), default: []].append(completion)
        wv.load(URLRequest(url: url))
    }

    private func finishLoad(_ webView: WKWebView) {
        pendingLoads.removeValue(forKey: ObjectIdentifier(webView))?.forEach { $0() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoad(webView) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishLoad(webView) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishLoad(webView) }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    /// Returns nil until the full request (headers + Content-Length body) has arrived.
    init?(_ data: Data) {
        guard let sep = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<sep.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let first = lines.removeFirst().split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = sep.upperBound
        guard data.count - bodyStart >= length else { return nil }
        method = String(first[0])
        path = String(first[1])
        self.headers = headers
        body = Data(data[bodyStart..<(bodyStart + length)])
    }
}
