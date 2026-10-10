import Cocoa

class PreferencesManager {
    static let shared = PreferencesManager()
    private let defaults = UserDefaults.standard
    
    var authToken: String {
        get { defaults.string(forKey: "MCP_AUTH_TOKEN") ?? "YOUR_SECURE_TOKEN_HERE" }
        set { defaults.set(newValue, forKey: "MCP_AUTH_TOKEN") }
    }
    
    var projectRoot: String {
        get { defaults.string(forKey: "MCP_PROJECT_ROOT") ?? "/Users/\(NSUserName())/Desktop/Works/Apps" }
        set { defaults.set(newValue, forKey: "MCP_PROJECT_ROOT") }
    }
    
    var publicBaseURL: String {
        get { defaults.string(forKey: "MCP_PUBLIC_BASE_URL") ?? "https://codex.mcsolution.tech" }
        set { defaults.set(newValue, forKey: "MCP_PUBLIC_BASE_URL") }
    }
    
    var tunnelName: String {
        get { defaults.string(forKey: "CF_TUNNEL_NAME") ?? "codex-local" }
        set { defaults.set(newValue, forKey: "CF_TUNNEL_NAME") }
    }
    
    var cloudflaredPath: String {
        get { defaults.string(forKey: "CF_BINARY_PATH") ?? "/opt/homebrew/bin/cloudflared" }
        set { defaults.set(newValue, forKey: "CF_BINARY_PATH") }
    }
    
    var downloadsPath: String {
        get { defaults.string(forKey: "DOWNLOADS_PATH") ?? (NSHomeDirectory() + "/Downloads") }
        set { defaults.set(newValue, forKey: "DOWNLOADS_PATH") }
    }
    
    var nodePath: String {
        get { defaults.string(forKey: "NODE_BINARY_PATH") ?? "/usr/local/bin/node" }
        set { defaults.set(newValue, forKey: "NODE_BINARY_PATH") }
    }
}

class PreferencesWindowController: NSWindowController {
    static let shared = PreferencesWindowController()
    
    private let tokenField = NSTextField()
    private let rootField = NSTextField()
    private let urlField = NSTextField()
    private let tunnelField = NSTextField()
    private let cfPathField = NSTextField()
    private let nodePathField = NSTextField()
    private let downloadsPathField = NSTextField()
    
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 550, height: 450),
                              styleMask: [.titled, .closable],
                              backing: .buffered, defer: false)
        window.title = "CodexDev Configuration"
        window.center()
        
        super.init(window: window)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    private func setupUI() {
        let windowHeight: CGFloat = 630
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 580, height: windowHeight))
        
        // Increase window height and center
        window?.setContentSize(NSSize(width: 580, height: windowHeight))
        window?.center()
        
        let labels = ["MCP Auth Token:", "Project Root:", "Downloads Path:", "Public Base URL:", "Tunnel Name:", "Cloudflared Path:", "Node.js Path:"]
        let descriptions = [
            "Secret token used to authenticate with your MCP server.",
            "The main folder where your projects and codebase are stored.",
            "Where ChatGPT's pasted folders and archived files are saved.",
            "Your public Cloudflare tunnel URL (e.g. https://codex.domain.com).",
            "The name of your Cloudflare tunnel (used in 'cloudflared run').",
            "Absolute path to the cloudflared executable (e.g. /opt/homebrew/bin/cloudflared).",
            "Absolute path to the node executable (e.g. /usr/local/bin/node)."
        ]
        
        let fields = [tokenField, rootField, downloadsPathField, urlField, tunnelField, cfPathField, nodePathField]
        
        let browseConfig: [Int: (isDirectory: Bool, title: String)] = [
            1: (true, "Choose..."), // Project Root
            2: (true, "Choose..."), // Downloads Path
            5: (false, "Choose..."), // Cloudflared Path
            6: (false, "Choose...")  // Node.js Path
        ]
        
        let startY = windowHeight - 60
        let rowHeight: CGFloat = 75
        
        for (i, labelStr) in labels.enumerated() {
            let y = startY - (CGFloat(i) * rowHeight)
            
            // Main Label
            let label = NSTextField(labelWithString: labelStr)
            label.frame = NSRect(x: 20, y: y, width: 140, height: 22)
            label.alignment = .right
            label.font = NSFont.systemFont(ofSize: 13, weight: .medium)
            label.isEditable = false
            label.isBordered = false
            label.backgroundColor = .clear
            view.addSubview(label)
            
            // Input Field
            let field = fields[i]
            field.toolTip = descriptions[i]
            if let config = browseConfig[i] {
                field.frame = NSRect(x: 170, y: y, width: 270, height: 22)
                let btn = NSButton(title: config.title, target: self, action: #selector(browseClicked(_:)))
                btn.frame = NSRect(x: 445, y: y - 5, width: 90, height: 32)
                btn.bezelStyle = .rounded
                btn.tag = i
                view.addSubview(btn)
                
                if i == 6 { // Node.js Path
                    let helpBtn = NSButton(title: "?", target: self, action: #selector(helpNodeClicked))
                    helpBtn.frame = NSRect(x: 535, y: y - 2, width: 25, height: 25)
                    helpBtn.bezelStyle = .helpButton
                    view.addSubview(helpBtn)
                }
                if i == 5 { // Cloudflared Path
                    let helpBtn = NSButton(title: "?", target: self, action: #selector(helpCfClicked))
                    helpBtn.frame = NSRect(x: 535, y: y - 2, width: 25, height: 25)
                    helpBtn.bezelStyle = .helpButton
                    view.addSubview(helpBtn)
                }
            } else if i == 0 { // Auth Token
                field.frame = NSRect(x: 170, y: y, width: 330, height: 22)
                let helpBtn = NSButton(title: "?", target: self, action: #selector(helpTokenClicked))
                helpBtn.frame = NSRect(x: 505, y: y - 2, width: 25, height: 25)
                helpBtn.bezelStyle = .helpButton
                view.addSubview(helpBtn)
            } else if i == 3 { // Public Base URL
                field.frame = NSRect(x: 170, y: y, width: 330, height: 22)
                let helpBtn = NSButton(title: "?", target: self, action: #selector(helpTunnelClicked))
                helpBtn.frame = NSRect(x: 505, y: y - 2, width: 25, height: 25)
                helpBtn.bezelStyle = .helpButton
                view.addSubview(helpBtn)
            } else {
                field.frame = NSRect(x: 170, y: y, width: 360, height: 22)
            }
            view.addSubview(field)
            
            // Description/Helper Text under the field
            let descLabel = NSTextField(labelWithString: descriptions[i])
            descLabel.frame = NSRect(x: 172, y: y - 20, width: 380, height: 16)
            descLabel.alignment = .left
            descLabel.font = NSFont.systemFont(ofSize: 11)
            descLabel.textColor = NSColor.secondaryLabelColor
            descLabel.isEditable = false
            descLabel.isBordered = false
            descLabel.backgroundColor = .clear
            view.addSubview(descLabel)
        }
        
        let saveBtn = NSButton(title: "Save & Restart Services", target: self, action: #selector(save))
        saveBtn.frame = NSRect(x: 170, y: 30, width: 220, height: 32)
        saveBtn.bezelStyle = .rounded
        view.addSubview(saveBtn)
        
        let howBtn = NSButton(title: "How does this work?", target: self, action: #selector(howItWorksClicked))
        howBtn.frame = NSRect(x: 20, y: 30, width: 140, height: 32)
        howBtn.bezelStyle = .rounded
        view.addSubview(howBtn)
        
        window?.contentView = view
    }
    
    @objc private func helpNodeClicked() {
        let alert = NSAlert()
        alert.messageText = "Node.js Setup"
        alert.informativeText = ""
        
        let customView = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 210))
        
        let title = NSTextField(labelWithString: "Why do I need Node.js?")
        title.font = .boldSystemFont(ofSize: 13)
        title.frame = NSRect(x: 0, y: 190, width: 450, height: 20)
        customView.addSubview(title)
        
        let desc = NSTextField(wrappingLabelWithString: "CodexDev runs a local Node.js server inside the app to securely grant ChatGPT access to your filesystem. You must have Node installed to start the server.")
        desc.font = .systemFont(ofSize: 12)
        desc.textColor = .secondaryLabelColor
        desc.frame = NSRect(x: 0, y: 145, width: 450, height: 40)
        customView.addSubview(desc)
        
        let installTitle = NSTextField(labelWithString: "How to install & find the path")
        installTitle.font = .boldSystemFont(ofSize: 13)
        installTitle.frame = NSRect(x: 0, y: 115, width: 450, height: 20)
        customView.addSubview(installTitle)
        
        let codeBox = NSBox(frame: NSRect(x: 0, y: 40, width: 450, height: 65))
        codeBox.boxType = .custom
        codeBox.cornerRadius = 8
        codeBox.fillColor = NSColor.windowBackgroundColor
        codeBox.borderColor = NSColor.separatorColor
        codeBox.borderWidth = 1
        
        let codeText = NSTextField(wrappingLabelWithString: "1. Install via Homebrew: brew install node\n2. Find where it was installed: which node\n3. Copy the output and paste it here.")
        codeText.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        codeText.textColor = .labelColor
        codeText.frame = NSRect(x: 12, y: 8, width: 426, height: 50)
        codeBox.addSubview(codeText)
        customView.addSubview(codeBox)
        
        let footDesc = NSTextField(wrappingLabelWithString: "Default paths are usually /usr/local/bin/node or /opt/homebrew/bin/node")
        footDesc.font = .systemFont(ofSize: 11)
        footDesc.textColor = .tertiaryLabelColor
        footDesc.frame = NSRect(x: 0, y: 10, width: 450, height: 20)
        customView.addSubview(footDesc)
        
        alert.accessoryView = customView
        
        alert.addButton(withTitle: "Got it")
        alert.addButton(withTitle: "Copy Command")
        
        if alert.runModal() == .alertSecondButtonReturn {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString("brew install node", forType: .string)
        }
    }
    
    @objc private func helpCfClicked() {
        let alert = NSAlert()
        alert.messageText = "Cloudflared Setup"
        alert.informativeText = ""
        
        let customView = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 260))
        
        let title = NSTextField(labelWithString: "Why is Cloudflared good for you?")
        title.font = .boldSystemFont(ofSize: 13)
        title.frame = NSRect(x: 0, y: 240, width: 450, height: 20)
        customView.addSubview(title)
        
        let desc = NSTextField(wrappingLabelWithString: "It acts as a secure, invisible cable connecting your local app directly to the outside world:\n• Instant Public HTTPS URL for your local code.\n• Zero router config or firewall port forwarding.\n• Instantly share your work or test external Webhooks.")
        desc.font = .systemFont(ofSize: 12)
        desc.textColor = .secondaryLabelColor
        desc.frame = NSRect(x: 0, y: 145, width: 450, height: 90)
        customView.addSubview(desc)
        
        let installTitle = NSTextField(labelWithString: "How to install & find the path")
        installTitle.font = .boldSystemFont(ofSize: 13)
        installTitle.frame = NSRect(x: 0, y: 115, width: 450, height: 20)
        customView.addSubview(installTitle)
        
        let codeBox = NSBox(frame: NSRect(x: 0, y: 40, width: 450, height: 65))
        codeBox.boxType = .custom
        codeBox.cornerRadius = 8
        codeBox.fillColor = NSColor.windowBackgroundColor
        codeBox.borderColor = NSColor.separatorColor
        codeBox.borderWidth = 1
        
        let codeText = NSTextField(wrappingLabelWithString: "1. Install via Homebrew: brew install cloudflared\n2. Find where it was installed: which cloudflared\n3. Copy the output and paste it here.")
        codeText.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        codeText.textColor = .labelColor
        codeText.frame = NSRect(x: 12, y: 8, width: 426, height: 50)
        codeBox.addSubview(codeText)
        customView.addSubview(codeBox)
        
        let footDesc = NSTextField(wrappingLabelWithString: "Default paths are usually /usr/local/bin/cloudflared or /opt/homebrew/bin/cloudflared")
        footDesc.font = .systemFont(ofSize: 11)
        footDesc.textColor = .tertiaryLabelColor
        footDesc.frame = NSRect(x: 0, y: 10, width: 450, height: 20)
        customView.addSubview(footDesc)
        
        alert.accessoryView = customView
        
        alert.addButton(withTitle: "Got it")
        alert.addButton(withTitle: "Copy Command")
        
        if alert.runModal() == .alertSecondButtonReturn {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString("brew install cloudflared", forType: .string)
        }
    }

    @objc private func helpTunnelClicked() {
        let alert = NSAlert()
        alert.messageText = "Setup Access Mode"
        alert.informativeText = ""
        
        let customView = NSView(frame: NSRect(x: 0, y: 0, width: 450, height: 280))
        
        // --- Local Mode ---
        let localTitle = NSTextField(labelWithString: "Local Only Mode")
        localTitle.font = .boldSystemFont(ofSize: 13)
        localTitle.frame = NSRect(x: 0, y: 260, width: 450, height: 20)
        customView.addSubview(localTitle)
        
        let localDesc = NSTextField(wrappingLabelWithString: "If you only need to run this locally, set 'Public Base URL' to http://127.0.0.1:8787 and completely CLEAR the 'Tunnel Name' field. The app will skip Cloudflare and run securely on your local network.")
        localDesc.font = .systemFont(ofSize: 12)
        localDesc.textColor = .secondaryLabelColor
        localDesc.frame = NSRect(x: 0, y: 215, width: 450, height: 40)
        customView.addSubview(localDesc)
        
        let separator = NSBox(frame: NSRect(x: 0, y: 195, width: 450, height: 1))
        separator.boxType = .separator
        customView.addSubview(separator)
        
        // --- Public Mode ---
        let pubTitle = NSTextField(labelWithString: "Public Cloudflare Mode (For ChatGPT)")
        pubTitle.font = .boldSystemFont(ofSize: 13)
        pubTitle.frame = NSRect(x: 0, y: 165, width: 450, height: 20)
        customView.addSubview(pubTitle)
        
        let codeBox = NSBox(frame: NSRect(x: 0, y: 55, width: 450, height: 100))
        codeBox.boxType = .custom
        codeBox.cornerRadius = 8
        codeBox.fillColor = NSColor.windowBackgroundColor
        codeBox.borderColor = NSColor.separatorColor
        codeBox.borderWidth = 1
        
        let codeText = NSTextField(wrappingLabelWithString: "1. brew install cloudflared\n2. cloudflared tunnel login\n3. cloudflared tunnel create my-tunnel\n4. cloudflared tunnel route dns my-tunnel api.yourdomain.com")
        codeText.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        codeText.textColor = .labelColor
        codeText.frame = NSRect(x: 12, y: 12, width: 426, height: 76)
        codeBox.addSubview(codeText)
        customView.addSubview(codeBox)
        
        let pubDesc = NSTextField(wrappingLabelWithString: "After running these, enter 'api.yourdomain.com' in the URL field and 'my-tunnel' in the Tunnel Name field.")
        pubDesc.font = .systemFont(ofSize: 12)
        pubDesc.textColor = .secondaryLabelColor
        pubDesc.frame = NSRect(x: 0, y: 5, width: 450, height: 40)
        customView.addSubview(pubDesc)
        
        alert.accessoryView = customView
        
        alert.addButton(withTitle: "Got it")
        alert.addButton(withTitle: "Copy Commands")
        
        if alert.runModal() == .alertSecondButtonReturn {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString("brew install cloudflared\ncloudflared tunnel login\ncloudflared tunnel create my-tunnel\ncloudflared tunnel route dns my-tunnel api.yourdomain.com", forType: .string)
        }
    }

        @objc private func helpTokenClicked() {
        let alert = NSAlert()
        alert.messageText = "What is the MCP Auth Token?"
        alert.informativeText = "This token is a secure password that protects your local server from unauthorized access.\n\nClick 'Generate Token' to create a new secure password. You must then copy this token and paste it into ChatGPT (in your Custom GPT Action -> Authentication -> API Key) so ChatGPT has permission to securely access your machine."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Generate Token")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            let newToken = UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            tokenField.stringValue = String(newToken.prefix(40))
        }
    }
    
    @objc private func browseClicked(_ sender: NSButton) {
        let tag = sender.tag
        let fields = [tokenField, rootField, downloadsPathField, urlField, tunnelField, cfPathField, nodePathField]
        let field = fields[tag]
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = (tag == 5 || tag == 6)
        panel.canChooseDirectories = (tag == 1 || tag == 2)
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.prompt = "Select"
        
        if !field.stringValue.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: field.stringValue)
        }
        
        if panel.runModal() == .OK, let url = panel.url {
            field.stringValue = url.path
        }
    }
    
    override func showWindow(_ sender: Any?) {
        let prefs = PreferencesManager.shared
        tokenField.stringValue = prefs.authToken
        rootField.stringValue = prefs.projectRoot
        downloadsPathField.stringValue = prefs.downloadsPath
        urlField.stringValue = prefs.publicBaseURL
        tunnelField.stringValue = prefs.tunnelName
        cfPathField.stringValue = prefs.cloudflaredPath
        nodePathField.stringValue = prefs.nodePath
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    

    @objc private func howItWorksClicked() {
        let alert = NSAlert()
        alert.messageText = "How CodexDev Works"
        alert.informativeText = ""
        
        let customView = NSView(frame: NSRect(x: 0, y: 0, width: 500, height: 360))
        
        let yStart: CGFloat = 340
        
        let components = [
            ("🧠 ChatGPT (The Brain)", "Sends a request over the internet like 'Read index.js'."),
            ("🌉 Cloudflare Tunnel (The Pipe)", "A secure, invisible tunnel that catches ChatGPT's request and blindly passes it down to your local Mac. It DOES NOT touch your files."),
            ("🛡️ API Key (The Bouncer)", "CodexDev checks the API Key attached to the request. If it matches, it allows the request. If not, it blocks hackers instantly."),
            ("🤖 Node.js Server (The Hands)", "This is the local server running inside CodexDev. It is the ONLY thing that actually reads and writes to your Mac's file system using local commands.")
        ]
        
        var currentY = yStart
        for (titleText, descText) in components {
            let title = NSTextField(labelWithString: titleText)
            title.font = .boldSystemFont(ofSize: 13)
            title.frame = NSRect(x: 0, y: currentY - 20, width: 500, height: 20)
            customView.addSubview(title)
            
            let desc = NSTextField(wrappingLabelWithString: descText)
            desc.font = .systemFont(ofSize: 12)
            desc.textColor = .secondaryLabelColor
            let h: CGFloat = titleText.contains("Cloudflare") || titleText.contains("Node.js") ? 45 : 30
            desc.frame = NSRect(x: 0, y: currentY - 20 - h, width: 500, height: h)
            customView.addSubview(desc)
            
            currentY -= (20 + h + 15)
        }
        
        let summary = NSTextField(wrappingLabelWithString: "Summary: Cloudflare acts as the delivery driver, the API Key ensures security, and Node.js actually opens the files.")
        summary.font = .boldSystemFont(ofSize: 12)
        summary.textColor = .labelColor
        summary.frame = NSRect(x: 0, y: currentY - 30, width: 500, height: 30)
        customView.addSubview(summary)
        
        alert.accessoryView = customView
        alert.addButton(withTitle: "Got it!")
        alert.runModal()
    }

    @objc private func save() {
        let root = rootField.stringValue
        let node = nodePathField.stringValue
        let cf = cfPathField.stringValue
        let tunnel = tunnelField.stringValue
        let fm = FileManager.default
        
        var errorMsgs = [String]()
        
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: root, isDirectory: &isDir) || !isDir.boolValue {
            errorMsgs.append("Project Root directory does not exist.")
        }
        
        if !fm.fileExists(atPath: node) {
            errorMsgs.append("Node.js executable not found at the specified path.")
        }
        
        // Only validate cloudflared if a tunnel name is provided (not local mode)
        let trimmedTunnel = tunnel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTunnel.isEmpty && !fm.fileExists(atPath: cf) {
            errorMsgs.append("Cloudflared executable not found at the specified path.")
        }
        
        if !errorMsgs.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Validation Error"
            alert.informativeText = "Please fix the following errors:\n\n" + errorMsgs.joined(separator: "\n")
            alert.alertStyle = .critical
            alert.runModal()
            return
        }

        let prefs = PreferencesManager.shared
        prefs.authToken = tokenField.stringValue
        prefs.projectRoot = root
        prefs.downloadsPath = downloadsPathField.stringValue
        prefs.publicBaseURL = urlField.stringValue
        prefs.tunnelName = trimmedTunnel
        prefs.cloudflaredPath = cf
        prefs.nodePath = node
        
        window?.close()
        
        // Notify app delegate to restart
        NotificationCenter.default.post(name: NSNotification.Name("RestartServices"), object: nil)
    }
}
