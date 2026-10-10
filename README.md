# CodexDev 🚀

[![Download for macOS](https://img.shields.io/badge/Download_for_macOS-000000?style=for-the-badge&logo=apple&logoColor=white)](https://github.com/MohamedCHAMI/CodexDev/releases/download/v1.0.0/CodexDev-macOS.zip)

**CodexDev** is a beautiful, native macOS application that seamlessly bridges the gap between **ChatGPT** and your local Mac file system. It acts as a secure, one-click manager for your local Model Context Protocol (MCP) server.

By running a local Node.js server and integrating with Cloudflare Tunnels natively, CodexDev allows ChatGPT to read, write, and manage your local codebase securely—acting as your ultimate AI co-developer without ever compromising your computer's security.

---

## 🌟 Why CodexDev?

Setting up a local MCP server for ChatGPT usually requires leaving terminal windows open, configuring router port-forwarding, dealing with firewall rules, and handling complex environment variables.

**CodexDev solves all of this with a beautiful Apple-native UI:**
- 🔌 **Zero-Config Cloudflare Tunnels:** Get an instant public HTTPS URL for your local code. No router configuration or firewall port-forwarding required.
- 🛡️ **Built-in Security (The Bouncer):** Generates and manages a secure API Auth Token. ChatGPT must use this token to access your files, keeping hackers out instantly.
- 🍏 **Native macOS Experience:** Lives in your menu bar. Start, stop, and configure your local server with beautiful native preference windows and interactive toast notifications.
- 🤖 **Smart Dependency Checking:** Automatically detects if you are missing Node.js or Cloudflared, and provides exact one-click copyable terminal commands to install them via Homebrew.
- 🔒 **Local-Only Mode:** Want to work entirely offline? Just clear the Tunnel Name and the app securely runs exclusively on your local network.

## 🛠️ How It Works

CodexDev acts as the orchestrator for three main components:

1. **🧠 ChatGPT (The Brain)**: Sends a request over the internet like *"Read index.js"*.
2. **🌉 Cloudflare Tunnel (The Pipe)**: A secure, invisible tunnel that catches ChatGPT's request and blindly passes it down to your local Mac. It DOES NOT touch your files.
3. **🤖 Node.js Server (The Hands)**: This is the local server running inside CodexDev. It is the ONLY thing that actually reads and writes to your Mac's file system using local commands.

## 🚀 Getting Started

1. Download or clone this repository.
2. Compile the app using Swift (`swift build -c release`).
3. Open **CodexDev.app** and click the settings gear ⚙️ to open the Configuration window.
4. Set your **Project Root** (the folder ChatGPT is allowed to see).
5. Generate an **MCP Auth Token** and paste it into ChatGPT's Custom Action authentication settings.
6. Provide your Cloudflare Tunnel Name (or leave blank for Local Mode).
7. Click **Save & Restart Services** and you are ready to code with AI!

## 📦 Dependencies
- macOS 12.0+
- **Node.js** (for running the local MCP server)
- **Cloudflared** (for exposing the secure public tunnel)

*CodexDev will automatically help you install these via Homebrew if you don't have them!*

## 🛡️ Security Promise
CodexDev was built with security as a priority. Your Cloudflare Tunnel simply acts as a blind delivery driver. Absolutely no file access is granted unless the request contains your exact, locally-generated MCP Auth Token.

---
*Built to make AI Pair Programming on macOS magical.*
