# Codex Dev: Native Navigation & Feature Plan

Since we are keeping `chatgpt.com` in the center and wrapping it with native macOS controls, the best approach is to implement an **`NSToolbar`**. This integrates directly into the window's title bar, saving vertical space while providing native, recognizable controls.

## 1. Proposed Native Toolbar Items

| Item | Type | Action |
| :--- | :--- | :--- |
| **Back / Forward** | Segmented Control | Navigates the WKWebView history. |
| **Reload** | Button (Symbol: `arrow.clockwise`) | Refreshes the ChatGPT page. |
| **Pin / Unpin** | Toggle Button (Symbol: `pin`) | Toggles the "Always on Top" floating mode. |
| **Flexible Space** | Spacer | Pushes the following items to the right side of the window. |
| **Server Status** | Status View | A live indicator (🟢 / 🟡 / 🔴) showing if the local MCP server and tunnel are active. |
| **Logs** | Button (Symbol: `terminal`) | Opens the Server Logs window. |
| **Start / Stop** | Button | Quickly restarts or stops the backend MCP server without needing the menu bar. |

## 2. Implementation Steps

1. **Adopt NSToolbarDelegate**: Update `AppDelegate` to handle toolbar item creation and validation.
2. **Configure the Window**: Attach an `NSToolbar` to the main `chatWindow`. Set `titleVisibility = .hidden` if we want the modern macOS look where the toolbar items merge with the title bar.
3. **Wire up the Actions**: 
   - Connect the Pin button to our existing `toggleAlwaysOnTop()`.
   - Connect the Logs button to `openLogsWindow()`.
   - Connect the Navigation buttons directly to the `WKWebView`'s `goBack()` / `goForward()`.
4. **Build & Test**: Recompile `main.swift` and replace the binary in the App folder to test the new layout.

## 3. Future "All Features" Expansion

If you ever want to add more advanced features (like local file browsers or a list of active MCP tools), we can add an **`NSSplitView` (Sidebar)** that slides out from the left or right, leaving the top toolbar strictly for window controls and status.
