import Cocoa
import WebKit
import Carbon
import ServiceManagement

var serverScriptPath: String {
    if let exeURL = Bundle.main.executableURL {
        let path = exeURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/mcp-server/build/http.js").path
        if FileManager.default.fileExists(atPath: path) {
            return path
        }
    }
    return NSHomeDirectory() + "/Desktop/mcp-local-dev-server/build/http.js"
}
var tunnelBinary: String { PreferencesManager.shared.cloudflaredPath }
var tunnelArgs: [String] { ["tunnel", "--url", "http://127.0.0.1:8787", "run", PreferencesManager.shared.tunnelName] }

let healthURL = URL(string: "http://127.0.0.1:8787/healthz")!
let chatGPTURL = URL(string: "https://chatgpt.com/")!

func fourCharCode(_ string: String) -> Int {
    var result: Int = 0
    for char in string.utf16 {
        result = (result << 8) + Int(char)
    }
    return result
}

// Toolbar Identifiers
extension NSToolbarItem.Identifier {
    static let navBack = NSToolbarItem.Identifier("navBack")
    static let navForward = NSToolbarItem.Identifier("navForward")
    static let reload = NSToolbarItem.Identifier("reload")
    static let pin = NSToolbarItem.Identifier("pin")
    static let logs = NSToolbarItem.Identifier("logs")
    static let status = NSToolbarItem.Identifier("status")
    static let settings = NSToolbarItem.Identifier("settings")
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSToolbarDelegate {
    private var statusItem: NSStatusItem!
    private var serverProcess: Process?
    private var tunnelProcess: Process?
    private var serverPipe: Pipe?
    private var tunnelPipe: Pipe?
    private var pollTimer: Timer?
    
    private var chatWindow: NSWindow?
    private var webView: WKWebView?
    
    private var logWindow: NSWindow?
    private var logTextView: NSTextView?
    private var isAlwaysOnTop = false

    private var statusMenuItem: NSMenuItem!
    private var startMenuItem: NSMenuItem!
    private var stopMenuItem: NSMenuItem!
    
    private var serverStatusButton: NSButton?

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "⚪︎"

        let menu = NSMenu()
        
        statusMenuItem = NSMenuItem(title: "Stopped", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        startMenuItem = NSMenuItem(title: "Start Server & Tunnel", action: #selector(startAll), keyEquivalent: "s")
        startMenuItem.target = self
        menu.addItem(startMenuItem)

        stopMenuItem = NSMenuItem(title: "Stop", action: #selector(stopAll), keyEquivalent: "x")
        stopMenuItem.target = self
        menu.addItem(stopMenuItem)
        menu.addItem(.separator())

        let openChatGPT = NSMenuItem(title: "Open Codex Dev UI", action: #selector(openChatGPTWindow), keyEquivalent: "o")
        openChatGPT.target = self
        menu.addItem(openChatGPT)
        
        let toggleFloat = NSMenuItem(title: "Always on Top", action: #selector(toggleAlwaysOnTop), keyEquivalent: "t")
        toggleFloat.target = self
        menu.addItem(toggleFloat)
        
        let viewLogs = NSMenuItem(title: "View Logs", action: #selector(openLogsWindow), keyEquivalent: "l")
        viewLogs.target = self
        menu.addItem(viewLogs)

        let prefsItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        menu.addItem(prefsItem)
        
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu


        detectExistingProcesses()
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleRestartServices), name: NSNotification.Name("RestartServices"), object: nil)
        pollTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        
        startAll()
        
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }
        
        setupMainMenu()
        registerGlobalHotkey()
        
        // Show the window immediately on launch
        openChatGPTWindow()
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        let prefsItem = NSMenuItem(title: "Settings...", action: #selector(openPreferences), keyEquivalent: ",")
        prefsItem.target = self
        appMenu.addItem(prefsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit Codex Dev", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(NSMenuItem(title: "Undo", action: NSSelectorFromString("undo:"), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "Redo", action: NSSelectorFromString("redo:"), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "Cut", action: NSSelectorFromString("cut:"), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "Copy", action: NSSelectorFromString("copy:"), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "Paste", action: NSSelectorFromString("paste:"), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "Select All", action: NSSelectorFromString("selectAll:"), keyEquivalent: "a"))
        editMenuItem.submenu = editMenu
        
        NSApp.mainMenu = mainMenu
    }
    
    // Handle clicks on the Dock icon
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openChatGPTWindow()
        }
        return true
    }
    
    private func registerGlobalHotkey() {
        var hotKeyRef: EventHotKeyRef?
        var hotKeyID = EventHotKeyID()
        hotKeyID.signature = OSType(fourCharCode("CDXM"))
        hotKeyID.id = 1
        
        RegisterEventHotKey(49, UInt32(cmdKey | shiftKey), hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { (_, _, userData) -> OSStatus in
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            delegate.toggleChatWindow()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)
    }

    @objc private func toggleChatWindow() {
        DispatchQueue.main.async {
            if let win = self.chatWindow, win.isVisible, NSApp.isActive {
                win.orderOut(nil)
                NSApp.hide(nil)
            } else {
                self.openChatGPTWindow()
            }
        }
    }
    
    @objc private func toggleAlwaysOnTop() {
        isAlwaysOnTop.toggle()
        chatWindow?.level = isAlwaysOnTop ? .floating : .normal
        if let item = statusItem.menu?.items.first(where: { $0.title.contains("Always on Top") }) {
            item.state = isAlwaysOnTop ? .on : .off
        }
        
        if let toolbar = chatWindow?.toolbar,
           let items = toolbar.items as? [NSToolbarItem],
           let pinItem = items.first(where: { $0.itemIdentifier == .pin }) {
            pinItem.image = NSImage(systemSymbolName: isAlwaysOnTop ? "pin.fill" : "pin", accessibilityDescription: "Pin")
        }
    }

    private func pgrepFound(_ pattern: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", pattern]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func detectExistingProcesses() {
        if pgrepFound("build/http.js") { }
    }

        private func checkDependencies() -> Bool {
        let prefs = PreferencesManager.shared
        var missing: [String] = []
        if !FileManager.default.fileExists(atPath: prefs.nodePath) {
            missing.append("Node.js (expected at \(prefs.nodePath))")
        }
        if !FileManager.default.fileExists(atPath: prefs.cloudflaredPath) {
            missing.append("Cloudflared (expected at \(prefs.cloudflaredPath))")
        }
        
        let hasBrew = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") || FileManager.default.fileExists(atPath: "/usr/local/bin/brew")
        
        if !missing.isEmpty {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Missing Dependencies"
                
                var infoText = "CodexDev requires the following tools to run:\n\n" + missing.joined(separator: "\n") + "\n\n"
                var copyCommand = ""
                
                if !hasBrew {
                    infoText += "You need Homebrew to install them easily. Open Terminal and paste this command first to install Homebrew:\n\n/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"\n\nAfter that finishes, run:\nbrew install node cloudflared"
                    copyCommand = "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\" && brew install node cloudflared"
                } else {
                    infoText += "Please install them using Homebrew:\nbrew install node cloudflared\n\nOr if you already have them installed elsewhere, update their paths in Settings."
                    copyCommand = "brew install node cloudflared"
                }
                
                alert.informativeText = infoText
                alert.addButton(withTitle: "Open Settings")
                alert.addButton(withTitle: "Copy Install Command")
                alert.addButton(withTitle: "Ignore")
                
                let resp = alert.runModal()
                if resp == .alertFirstButtonReturn {
                    PreferencesWindowController.shared.showWindow(nil)
                } else if resp == .alertSecondButtonReturn {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.setString(copyCommand, forType: .string)
                    
                    let copiedAlert = NSAlert()
                    copiedAlert.messageText = "Command Copied!"
                    copiedAlert.informativeText = "The installation command has been copied to your clipboard. Open Terminal, paste it, and press Enter."
                    copiedAlert.runModal()
                }
            }
            return false
        }
        return true
    }

    @objc private func startAll() {
        if !checkDependencies() {
            appendLog("Dependencies missing. Cannot start server/tunnel.\n")
            return
        }
        let prefs = PreferencesManager.shared
        
        if !pgrepFound("build/http.js") {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: prefs.nodePath)
            p.arguments = [serverScriptPath]
            
            var env = ProcessInfo.processInfo.environment
            env["MCP_AUTH_TOKEN"] = prefs.authToken
            env["MCP_PROJECT_ROOT"] = prefs.projectRoot
            env["MCP_PUBLIC_BASE_URL"] = prefs.publicBaseURL
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
            p.environment = env
            
            let pipe = Pipe()
            self.serverPipe = pipe
            p.standardOutput = pipe
            p.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.count > 0, let str = String(data: data, encoding: .utf8) {
                    self?.appendLog(str)
                }
            }
            
            do {
                try p.run()
                serverProcess = p
                appendLog("Server started.\n")
            } catch {
                statusMenuItem.title = "Failed to start server"
                appendLog("Failed to start server.\n")
            }
        }

        let tunnelCmd = "cloudflared tunnel run \(prefs.tunnelName)"
        if !pgrepFound(tunnelCmd) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: prefs.cloudflaredPath)
            p.arguments = ["tunnel", "run", prefs.tunnelName]
            
            var env = ProcessInfo.processInfo.environment
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
            if env["HOME"] == nil || env["HOME"] == "/" || env["HOME"]!.contains("agy-home") {
                env["HOME"] = NSHomeDirectory()
            }
            p.environment = env
            
            let tPipe = Pipe()
            self.tunnelPipe = tPipe
            p.standardOutput = tPipe
            p.standardError = tPipe
            tPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.count > 0, let str = String(data: data, encoding: .utf8) {
                    self?.appendLog(str)
                }
            }
            
            do {
                try p.run()
                tunnelProcess = p
                appendLog("Tunnel started.\n")
            } catch {
                statusMenuItem.title = "Failed to start tunnel"
                appendLog("Failed to start tunnel.\n")
            }
        }
        
        refreshStatus()
    }

    @objc private func stopAll() {
        serverProcess?.terminate()
        serverProcess = nil
        tunnelProcess?.terminate()
        tunnelProcess = nil

        killByPattern("build/http.js")
        killByPattern("cloudflared tunnel run codex-local")
        appendLog("Processes stopped.\n")

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshStatus()
        }
    }

    private func killByPattern(_ pattern: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        p.arguments = ["-f", pattern]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
    }

    private func refreshStatus() {
        let serverUp = pgrepFound("build/http.js")
        let tunnelUp = PreferencesManager.shared.tunnelName.isEmpty ? true : pgrepFound("cloudflared tunnel run \(PreferencesManager.shared.tunnelName)")

        func updateUI(symbol: String, menuText: String, statusText: String) {
            DispatchQueue.main.async {
                self.statusItem.button?.title = symbol
                self.statusMenuItem.title = menuText
                self.serverStatusButton?.title = " " + symbol + " " + statusText + " "
            }
        }

        if serverUp && tunnelUp {
            checkHealth { healthy in
                if healthy {
                    updateUI(symbol: "🟢", menuText: "Running — server + tunnel OK", statusText: "Online")
                } else {
                    updateUI(symbol: "🟡", menuText: "Starting… (processes up, not answering)", statusText: "Starting...")
                }
            }
        } else if serverUp || tunnelUp {
            let msg = serverUp ? "Server up, tunnel down" : "Tunnel up, server down"
            updateUI(symbol: "🟡", menuText: msg, statusText: "Partial")
        } else {
            updateUI(symbol: "⚪︎", menuText: "Stopped", statusText: "Offline")
        }
    }

    
    @objc private func toggleServices() {
        let serverUp = pgrepFound("build/http.js")
        let tunnelUp = PreferencesManager.shared.tunnelName.isEmpty ? true : pgrepFound("cloudflared tunnel run \(PreferencesManager.shared.tunnelName)")
        if serverUp || tunnelUp {
            stopAll()
            showToast(message: "Stopping CodexDev Services...")
        } else {
            startAll()
            showToast(message: "Starting CodexDev Services...")
        }
    }
    
    private func showToast(message: String) {
        let js = """
        (function() {
            let existing = document.getElementById('codex-dev-toast');
            if (existing) existing.remove();
            let toast = document.createElement('div');
            toast.id = 'codex-dev-toast';
            toast.textContent = '\(message)';
            toast.style.position = 'fixed';
            toast.style.top = '20px';
            toast.style.left = '50%';
            toast.style.transform = 'translateX(-50%)';
            toast.style.backgroundColor = 'rgba(0, 0, 0, 0.8)';
            toast.style.color = 'white';
            toast.style.padding = '12px 24px';
            toast.style.borderRadius = '24px';
            toast.style.zIndex = '999999';
            toast.style.boxShadow = '0 4px 12px rgba(0,0,0,0.15)';
            toast.style.fontFamily = '-apple-system, system-ui, sans-serif';
            toast.style.fontSize = '14px';
            toast.style.fontWeight = '500';
            toast.style.transition = 'opacity 0.3s ease';
            document.body.appendChild(toast);
            setTimeout(() => {
                toast.style.opacity = '0';
                setTimeout(() => toast.remove(), 300);
            }, 3000);
        })();
        """
        webView?.evaluateJavaScript(js, completionHandler: nil)
    }

private func checkHealth(completion: @escaping (Bool) -> Void) {
        let task = URLSession.shared.dataTask(with: healthURL) { data, response, error in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                completion(true)
            } else {
                completion(false)
            }
        }
        task.resume()
    }
    
    private func appendLog(_ text: String) {
        DispatchQueue.main.async {
            self.logTextView?.string += text
            self.logTextView?.scrollToEndOfDocument(nil)
        }
    }
    
    @objc private func openLogsWindow() {
        if logWindow == nil {
            let rect = NSRect(x: 0, y: 0, width: 600, height: 400)
            let win = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            win.title = "Server Logs"
            win.center()
            win.isReleasedWhenClosed = false
            
            let scrollView = NSScrollView(frame: rect)
            scrollView.hasVerticalScroller = true
            
            let tv = NSTextView(frame: rect)
            tv.isEditable = false
            tv.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            tv.backgroundColor = NSColor.windowBackgroundColor
            
            scrollView.documentView = tv
            win.contentView = scrollView
            
            logTextView = tv
            logWindow = win
            appendLog("Logs initialized...\n")
        }
        logWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func navBack() { webView?.goBack() }
    @objc private func navForward() { webView?.goForward() }
    @objc private func navReload() { webView?.reload() }

    @objc private func openChatGPTWindow() {
        if chatWindow == nil {
            let rect = NSRect(x: 0, y: 0, width: 1000, height: 800)
            let win = NSWindow(contentRect: rect, 
                               styleMask: [.titled, .closable, .resizable, .miniaturizable], 
                               backing: .buffered, defer: false)
            win.title = "Codex Dev"
            win.titlebarAppearsTransparent = true
            win.center()
            win.isReleasedWhenClosed = false
            
            let toolbar = NSToolbar(identifier: "MainWindowToolbar")
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            win.toolbar = toolbar
            
            let css = ".flex-shrink-0.overflow-x-hidden { display: none !important; }"
            let js = "var style = document.createElement('style'); style.innerHTML = '\(css)'; document.head.appendChild(style);"
            let script = WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            
            let blobScriptStr = """
            const originalClick = HTMLAnchorElement.prototype.click;
            HTMLAnchorElement.prototype.click = function() {
                if (this.href && this.href.startsWith('blob:')) {
                    let filename = this.download || 'downloaded_file';
                    let xhr = new XMLHttpRequest();
                    xhr.open('GET', this.href, true);
                    xhr.responseType = 'blob';
                    xhr.onload = function(e) {
                        if (this.status == 200) {
                            let blob = this.response;
                            let reader = new FileReader();
                            reader.readAsDataURL(blob);
                            reader.onloadend = function() {
                                window.webkit.messageHandlers.blobDownload.postMessage({
                                    filename: filename,
                                    data: reader.result
                                });
                            };
                        }
                    };
                    xhr.send();
                    return;
                }
                originalClick.call(this);
            };
            """
            let blobScript = WKUserScript(source: blobScriptStr, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            
            let clipboardScriptStr = """
            if (!navigator.clipboard) {
                navigator.clipboard = {};
            }
            navigator.clipboard.writeText = function(text) {
                return new Promise((resolve, reject) => {
                    window.webkit.messageHandlers.clipboardHandler.postMessage(text);
                    
                    let toast = document.createElement('div');
                    toast.innerText = '✓ Copied to clipboard';
                    
                    Object.assign(toast.style, {
                        position: 'fixed',
                        bottom: '40px',
                        left: '50%',
                        transform: 'translateX(-50%) translateY(20px)',
                        backgroundColor: 'rgba(0, 0, 0, 0.75)',
                        backdropFilter: 'blur(12px)',
                        WebkitBackdropFilter: 'blur(12px)',
                        color: '#ffffff',
                        padding: '12px 24px',
                        borderRadius: '999px',
                        fontFamily: 'system-ui, -apple-system, sans-serif',
                        fontSize: '14px',
                        fontWeight: '500',
                        letterSpacing: '0.2px',
                        zIndex: '999999',
                        boxShadow: '0 8px 32px rgba(0,0,0,0.24), 0 0 0 1px rgba(255,255,255,0.08)',
                        opacity: '0',
                        transition: 'all 0.4s cubic-bezier(0.16, 1, 0.3, 1)',
                        pointerEvents: 'none'
                    });
                    
                    document.body.appendChild(toast);
                    
                    // Trigger smooth pop-up animation
                    requestAnimationFrame(() => {
                        toast.style.opacity = '1';
                        toast.style.transform = 'translateX(-50%) translateY(0)';
                    });
                    
                    // Fade out and slide down
                    setTimeout(() => {
                        toast.style.opacity = '0';
                        toast.style.transform = 'translateX(-50%) translateY(10px)';
                        setTimeout(() => toast.remove(), 400);
                    }, 2500);
                    
                    resolve();
                });
            };
            document.hasFocus = function() { return true; };
            """
            let clipboardScript = WKUserScript(source: clipboardScriptStr, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            
            let contentController = WKUserContentController()
            contentController.addUserScript(script)
            contentController.addUserScript(blobScript)
            contentController.addUserScript(clipboardScript)
            contentController.add(self, name: "blobDownload")
            contentController.add(self, name: "clipboardHandler")
            
            let config = WKWebViewConfiguration()
            config.userContentController = contentController
            
            let wv = WKWebView(frame: rect, configuration: config)
            wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"
            wv.navigationDelegate = self
            wv.load(URLRequest(url: chatGPTURL))
            win.contentView = wv
            
            self.webView = wv
            self.chatWindow = win
        }
        
        chatWindow?.level = isAlwaysOnTop ? .floating : .normal
        chatWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // MARK: - NSToolbarDelegate
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.navBack, .navForward, .reload, .flexibleSpace, .pin, .logs, .status]
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.navBack, .navForward, .reload, .flexibleSpace, .status, .settings, .logs, .pin]
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)
        
        switch itemIdentifier {
        case .navBack:
            item.label = "Back"
            item.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
            item.target = self
            item.action = #selector(navBack)
        case .navForward:
            item.label = "Forward"
            item.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")
            item.target = self
            item.action = #selector(navForward)
        case .reload:
            item.label = "Reload"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Reload")
            item.target = self
            item.action = #selector(navReload)
        case .pin:
            item.label = "Pin"
            item.image = NSImage(systemSymbolName: isAlwaysOnTop ? "pin.fill" : "pin", accessibilityDescription: "Pin")
            item.target = self
            item.action = #selector(toggleAlwaysOnTop)
        case .logs:
            item.label = "Logs"
            item.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Logs")
            item.target = self
            item.action = #selector(openLogsWindow)
        case .settings:
            item.label = "Settings"
            item.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "Settings")
            item.target = self
            item.action = #selector(openPreferences)
        case .status:
            item.label = "Status"
            let btn = NSButton(title: " ⚪︎ Offline ", target: self, action: #selector(toggleServices))
            btn.bezelStyle = .recessed
            btn.showsBorderOnlyWhileMouseInside = true
            btn.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            
            self.serverStatusButton = btn
            item.view = btn
            
            refreshStatus()
        default:
            return nil
        }
        
        return item
    }

        @objc private func openPreferences() {
        PreferencesWindowController.shared.showWindow(nil)
    }
    

    @objc private func handleRestartServices() {
        showToast(message: "✓ Settings Saved. Restarting...")
        restartServices()
    }

    @objc private func restartServices() {
        stopAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startAll()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}


// MARK: - WKNavigationDelegate & WKDownloadDelegate
extension AppDelegate: WKNavigationDelegate, WKDownloadDelegate, WKScriptMessageHandler {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if navigationAction.shouldPerformDownload {
            decisionHandler(.download, preferences)
            return
        }
        
        // Handle target="_blank" links (often used by ChatGPT for downloads)
        if navigationAction.targetFrame == nil {
            if let url = navigationAction.request.url {
                // If it's explicitly a download endpoint, we could try to download directly,
                // but loading it in the current webview will trigger navigationResponse which handles attachments.
                webView.load(navigationAction.request)
            }
            decisionHandler(.cancel, preferences)
            return
        }
        
        decisionHandler(.allow, preferences)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let httpResponse = navigationResponse.response as? HTTPURLResponse,
           let contentDisposition = httpResponse.allHeaderFields["Content-Disposition"] as? String,
           contentDisposition.lowercased().contains("attachment") {
            decisionHandler(.download)
            return
        }
        
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            decisionHandler(.download)
        }
    }
    
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }
    
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }
    
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        let saveDir = URL(fileURLWithPath: PreferencesManager.shared.downloadsPath)
        if !FileManager.default.fileExists(atPath: saveDir.path) {
            try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        }
        let saveURL = saveDir.appendingPathComponent(suggestedFilename)
        completionHandler(saveURL)
        
        let notif = NSUserNotification()
        notif.title = "Download Started"
        notif.informativeText = "Saving to \(saveURL.path)"
        NSUserNotificationCenter.default.deliver(notif)
    }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "clipboardHandler", let text = message.body as? String {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return
        }
        
        if message.name == "blobDownload",
           let dict = message.body as? [String: Any],
           let filename = dict["filename"] as? String,
           let base64String = dict["data"] as? String {
            
            let components = base64String.components(separatedBy: ",")
            if components.count == 2, let data = Data(base64Encoded: components[1]) {
                let saveDir = URL(fileURLWithPath: PreferencesManager.shared.downloadsPath)
                if !FileManager.default.fileExists(atPath: saveDir.path) {
                    try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
                }
                let saveURL = saveDir.appendingPathComponent(filename)
                try? data.write(to: saveURL)
                
                // Show a native notification that file was saved
                let notif = NSUserNotification()
                notif.title = "File Downloaded"
                notif.informativeText = "Saved to \(saveURL.path)"
                NSUserNotificationCenter.default.deliver(notif)
            }
        }
    }
}

// CLI Mode
func cliPgrepFound(_ pattern: String) -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    p.arguments = ["-f", pattern]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    do { try p.run(); p.waitUntilExit(); return p.terminationStatus == 0 } catch { return false }
}

func cliKill(_ pattern: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    p.arguments = ["-f", pattern]
    p.standardOutput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    try? p.run()
    p.waitUntilExit()
}

func cliCheckHealth() -> Bool {
    let semaphore = DispatchSemaphore(value: 0)
    var healthy = false
    let task = URLSession.shared.dataTask(with: healthURL) { _, response, _ in
        if let http = response as? HTTPURLResponse, http.statusCode == 200 { healthy = true }
        semaphore.signal()
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 5)
    return healthy
}

func cliStart() {
    if cliPgrepFound("build/http.js") { print("server: already running") } else {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-c", serverScriptPath]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run(); print("server: started")
    }

    if cliPgrepFound("cloudflared tunnel run codex-local") { print("tunnel: already running") } else {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tunnelBinary)
        p.arguments = tunnelArgs
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run(); print("tunnel: started")
    }

    print("waiting for health check...")
    Thread.sleep(forTimeInterval: 2.0)
    if cliCheckHealth() { print("✅ healthy — https://codex.mcsolution.tech/healthz is responding") } else { print("⏳ not answering yet — give it a few more seconds, then run: codexdev status") }
}

func cliStop() {
    cliKill("build/http.js")
    cliKill("cloudflared tunnel run \(PreferencesManager.shared.tunnelName)")
    print("stopped server and tunnel")
}

func cliStatus() {
    let serverUp = cliPgrepFound("build/http.js")
    let tunnelUp = cliPgrepFound("cloudflared tunnel run \(PreferencesManager.shared.tunnelName)")
    print("server: \(serverUp ? "running" : "stopped")")
    print("tunnel: \(tunnelUp ? "running" : "stopped")")
    if serverUp && tunnelUp { print("health: \(cliCheckHealth() ? "✅ ok" : "⚠️ processes up but not answering")") }
}

let cliArgs = CommandLine.arguments.dropFirst()
if let command = cliArgs.first {
    switch command {
    case "start": cliStart(); exit(0)
    case "stop": cliStop(); exit(0)
    case "status": cliStatus(); exit(0)
    default: print("Usage: codexdev [start|stop|status]"); exit(1)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
