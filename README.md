# ValenTech Anvil

A GDD-to-Unity pipeline tool. Load a Game Design Document, extract game systems with semantic category colours, and let Claude propose feature checklists — one system at a time.

---

## Requirements

- Windows 10/11
- [Git for Windows](https://git-scm.com/) — provides Git Bash (required for the monitor scripts)
- [Claude Code](https://claude.ai/claude-code) — Claude must be running alongside the app to respond to node selections

---

## Setup (first time)

### 1. Clone the repo
```bash
git clone https://github.com/404Valentine/valentech-anvil.git
cd valentech-anvil
```

### 2. Create the desktop shortcut
Open PowerShell in the cloned folder and run:
```powershell
$ROOT    = (Get-Location).Path
$wsh     = New-Object -ComObject WScript.Shell
$sc      = $wsh.CreateShortcut("$env:USERPROFILE\Desktop\ValenTech Anvil.lnk")
$sc.TargetPath       = "wscript.exe"
$sc.Arguments        = "`"$ROOT\run_hidden.vbs`" `"$ROOT\launch_crafter.ps1`""
$sc.WorkingDirectory = $ROOT
$sc.IconLocation     = "$ROOT\valentech.ico,0"
$sc.Description      = "ValenTech Anvil"
$sc.Save()
Write-Output "Shortcut created on Desktop"
```

---

## Running the tool

ValenTech Anvil has **two parts** that must both be running:

### Part 1 — Start the monitor in Claude Code
Open Claude Code in the project folder and tell Claude:

> **"Start the ValenTech Anvil monitor"**

Claude will run `auto_monitor.sh` and wait for events. It must stay open while you use the tool.

### Part 2 — Launch the app
Double-click **ValenTech Anvil** on your desktop (or run `launch_crafter.ps1` directly).

---

## Workflow

1. Click **BROWSE FILE** → select your GDD (`.pdf`, `.txt`, or `.md`)
2. The GDD is parsed into colour-coded system nodes in the left panel
3. Click any node → Claude proposes a feature checklist with 3–6 components
4. Check/uncheck the components you want → click **CONFIRM** to save them
5. Click **REROLL** for a fresh proposal, or click a different node to move on
6. When done, click **GENERATE** to export a full framework markdown file

---

## Colour guide

| Colour | Category |
|--------|----------|
| 🔴 Red | Combat / Catching |
| 🟠 Orange | Economy / Trading |
| 🟡 Gold | Progression |
| 🟢 Green | Plant Systems |
| 🩵 Teal | Animal + Plant |
| 🔵 Cyan | Exploration |
| 💙 Blue | Animal / Creature |
| 🟣 Purple | Social / Community |
| 🔘 Steel | Building / Management |
| ⚪ Grey | UI / General |

---

## Files

| File | Purpose |
|------|---------|
| `window.ps1` | Main WinForms UI |
| `launch_crafter.ps1` | Resets state and launches the window |
| `propose_one.ps1` | Called by Claude to write a proposal to state.json |
| `get_decision.ps1` | Polls state.json until the user clicks CONFIRM/REROLL/DENY |
| `generate_framework.ps1` | Writes the confirmed features to a markdown file |
| `auto_monitor.sh` | Persistent outer monitor — detects app launches |
| `monitor.sh` | Inner monitor — fires NODE_SELECTED and other events to Claude |
| `run_hidden.vbs` | Launches PowerShell silently (no console flash) |
| `state.json` | Shared runtime state (auto-generated, not committed) |
| `features.json` | Confirmed features for the current session (auto-generated) |
| `saves/` | Named project saves (auto-generated) |
