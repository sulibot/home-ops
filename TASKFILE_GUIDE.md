# Taskfile Interactive Guide

## Overview

Your Taskfile now includes **Charm-powered interactive menus** for a beautiful terminal UI experience!

## Prerequisites

Before using the Taskfile, you need several tools installed. The Taskfile now includes **automated dependency installation**!

## Quick Start

### 1. Check & Install Dependencies

First, check what tools you have:

```bash
task install:check
```

Output:
```
Checking dependencies...

Charm Tools (Interactive UI):
✓ gum                  gum version 0.17.0
✓ glow                 glow version 2.1.1
✓ mods                 mods version 1.8.1

Kubernetes Tools:
✓ kubectl              Client Version: v1.31.1
✓ helm                 v3.16.3
✓ flux                 flux version 2.7.3

Talos Tools:
✓ talosctl             1.11.5
✓ talhelper            talhelper version 3.0.39

Infrastructure Tools:
✓ terraform            Terraform v1.12.2
✓ terragrunt           terragrunt version 0.83.2

Utilities:
✓ jinja2-cli           jinja2-cli v0.8.2
✓ sops                 sops 3.10.2
✓ age                  v1.2.0
✓ python3              Python 3.14.0

Legend:
✓ Installed  ✗ Missing (required)  ○ Missing (optional)
```

Install all missing dependencies:

```bash
# Interactive installation (recommended)
task install

# Or install everything without prompts
task install:all

# Or install specific categories
task install:charm       # gum, glow, mods
task install:kubernetes  # kubectl, helm, flux
task install:talos       # talosctl, talhelper
task install:infra       # terraform, terragrunt
task install:utils       # jinja2-cli, sops, age
```

### 2. Launch Interactive Menu

```bash
# Simply run task (default now shows menu)
task

# Or explicitly
task menu
```

This gives you a beautiful interactive menu with:
- 🚀 Cluster creation wizard
- 📊 Status dashboards
- 📜 Log viewers
- ⚙️  Operations menu
- 🤖 AI troubleshooting assistant
- 📚 Documentation browser

### 3. Browse All Tasks (Interactive)

```bash
# Interactive task browser with arrow keys + fuzzy search
task list
```

**Features:**
- **30 lines visible** at once (shows ~60 total tasks)
- **Arrow keys** (↑↓) to navigate
- **Page Up/Down** to scroll quickly
- **Type to filter** (fuzzy search)
- **Press Enter** to see task details
- **Run tasks** directly from browser
- **Auto-detect arguments** (prompts if needed)

**Example:**
```
→ Search tasks: clus

> cluster:create           🚀 Create complete cluster
  cluster:bootstrap        4️⃣  Bootstrap Talos cluster
  cluster:destroy          🗑️  Destroy complete cluster
  status:cluster           Show overall cluster health
```

### Interactive Cluster Creation

```bash
# From menu: Select "🚀 Create Cluster"
# Or directly:
task menu:create

# Features:
# - Input validation with prompts
# - Progress spinners for each step
# - Visual checkmarks on completion
# - Beautiful success messages
```

### AI-Powered Troubleshooting

```bash
# From menu: Select "🤖 AI Assistant"
# Or directly:
task menu:ai

# Capabilities:
# - Analyze recent cluster events
# - Troubleshoot failing pods
# - Diagnose Flux reconciliation issues
# - Network connectivity analysis
# - Ask custom questions with context
```

## Charm Tools Used

### 🍬 Gum - Interactive Components
- **Installed**: `brew install gum`
- **Features**: Menus, input prompts, spinners, styled output
- **Status**: ✅ Installed

### ✨ Glow - Markdown Viewer
- **Installed**: `brew install glow`
- **Features**: Beautiful markdown rendering in terminal
- **Status**: ✅ Installed

### 🤖 Mods - AI Assistant
- **Installed**: `brew install mods`
- **Features**: ChatGPT/Claude in terminal
- **Configuration**: Run `mods --settings` to configure API keys
- **Status**: ✅ Installed

## Interactive Menu Structure

```
🏠 Main Menu
├── 🚀 Create Cluster ────────── Full cluster creation wizard
├── 🗑️  Destroy Cluster ───────── Safely destroy cluster (with protection)
├── 🔧 Bootstrap Talos ────────── Bootstrap existing VMs
├── 📦 Install Flux ───────────── Install Flux GitOps
├── 📊 Status Dashboard
│   ├── Cluster Overview
│   ├── Node Status
│   ├── Flux Status
│   ├── Cilium Status
│   ├── Storage Status
│   ├── All Pods
│   └── Complete Health Check
├── 📜 View Logs
│   ├── Talos System Logs
│   ├── Flux Controller Logs
│   ├── Cilium Logs
│   └── Pod Logs (fuzzy search)
├── ⚙️  Operations
│   ├── Drain Node
│   ├── Cordon/Uncordon Node
│   ├── Reboot Node
│   ├── Node Shell
│   └── Upgrade Talos
├── 🐛 Debug & Troubleshoot
│   ├── Watch Events
│   ├── Test Network
│   ├── Test DNS
│   ├── Debug Pod
│   └── Debug Node
├── 🤖 AI Assistant
│   ├── Analyze Recent Events
│   ├── Troubleshoot Pod Issues
│   ├── Analyze Flux Errors
│   ├── Network Diagnostics
│   └── Ask Custom Question
├── 📚 Documentation ────────────── Browse all .md files with Glow
└── 🔧 Install Dependencies
    ├── Check All Dependencies
    ├── Install All Dependencies
    ├── Install Charm Tools
    ├── Install Kubernetes Tools
    ├── Install Talos Tools
    ├── Install Infrastructure Tools
    └── Install Utilities
```

## Dependency Management

### Check What's Installed

```bash
task install:check
```

This shows:
- ✓ = Installed (with version)
- ✗ = Missing (required for core functionality)
- ○ = Missing (optional, for enhanced UI)

### Install Categories

**All Dependencies:**
```bash
task install           # Interactive with confirmation
task install:all       # Install everything
```

**By Category:**
```bash
# Charm tools (optional - for interactive UI)
task install:charm
# → gum, glow, mods

# Kubernetes tools (required)
task install:kubernetes
# → kubectl, helm, flux

# Talos tools (required)
task install:talos
# → talosctl, talhelper

# Infrastructure tools (required)
task install:infra
# → terraform, terragrunt

# Utilities (required)
task install:utils
# → jinja2-cli, sops, age, python3
```

### CI/CD Installation

For GitHub Actions or other CI/CD:

```bash
# Install only required tools (skips Charm)
task install:ci
```

Example GitHub Actions workflow:

```yaml
- name: Install dependencies
  run: |
    sh -c "$(curl -sL https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin
    task install:ci
```

### Platform Support

- **macOS**: Uses Homebrew (`brew install ...`)
- **Linux**: Downloads binaries directly from GitHub releases
- **Windows**: Not supported (use WSL2)

## CI/CD Compatibility

Tasks automatically detect interactive vs CI/CD environments:

### Local Development (Interactive)
```bash
task cluster:create -- 101
# → Shows Gum progress bars and spinners
# → Beautiful colored output
# → Interactive prompts
```

### GitHub Actions (Non-interactive)
```yaml
- name: Create cluster
  run: task cluster:create -- 101
  # → Plain text output
  # → No interactive components
  # → CI-friendly logging
```

Detection logic:
```bash
if [ -t 0 ] && command -v gum &> /dev/null; then
  # Interactive mode
else
  # CI/CD mode
fi
```

## Common Workflows

### 1. Create New Cluster
```bash
task menu
# → Select "🚀 Create Cluster"
# → Enter cluster ID (e.g., 102)
# → Confirm creation
# → Watch progress bars
# → Cluster ready in ~15 minutes
```

### 2. Destroy Cluster (Safely)
```bash
task menu
# → Select "🗑️  Destroy Cluster"
# → Enter cluster ID
# → Review warning (VMs, data, configs deleted)
# → Confirm destruction
# → For cluster-101: Type 'sol' to confirm (production protection)
# → Final confirmation required
# → Watch destruction progress
```

**Safety Features:**
- ⚠️ Multiple confirmations required
- 🛑 Production cluster (101) requires typing cluster name
- 🔴 Red/warning colored output
- ❌ Easy to cancel at any point

**Direct command:**
```bash
# Interactive with all safety checks
task cluster:destroy -- 102

# Skip confirmations (USE WITH CAUTION)
SKIP_CONFIRM=1 task cluster:destroy -- 102
```

### 3. Check Cluster Health
```bash
task menu
# → Select "📊 Status Dashboard"
# → Select "Complete Health Check"
# → View all system status
```

### 4. Debug Pod Issues
```bash
task menu
# → Select "🐛 Debug & Troubleshoot"
# → Select "Debug Pod"
# → Fuzzy search for pod
# → View diagnostics
```

### 5. AI Troubleshooting
```bash
task menu
# → Select "🤖 AI Assistant"
# → Select "Troubleshoot Pod Issues"
# → Fuzzy search for failing pod
# → AI analyzes logs and suggests fixes
```

### 6. View Documentation
```bash
task menu
# → Select "📚 Documentation"
# → Fuzzy search for .md file
# → Beautiful rendered view
```

### 7. Manage Dependencies
```bash
task menu
# → Select "🔧 Install Dependencies"
# → Check what's installed
# → Install missing tools by category
```

## Traditional CLI Still Works

All original commands work exactly as before:

```bash
# Direct task execution (no interactivity)
task infra:provision -- 101
task talos:bootstrap -- 101
task flux:install -- 101

# Status checks
task status:cluster
task status:all

# Operations
task ops:drain -- worker01
task ops:upgrade:talos -- 101 1.11.6

# Logs
task logs:talos -- 101
task logs:pod -- kube-system/cilium-abc123
```

## Configuration

### Configure Mods (AI)

First time setup:
```bash
mods --settings
```

This opens the config file where you can add:
```yaml
# ~/.config/mods/mods.yml
default-model: gpt-4
apis:
  openai:
    api-key: sk-...
    # Or use: api-key-env: OPENAI_API_KEY

  anthropic:
    api-key: sk-ant-...
    # Or use: api-key-env: ANTHROPIC_API_KEY
```

Then test:
```bash
mods "explain kubernetes pods"
```

## Tips & Tricks

### Fuzzy Search
Many menus support fuzzy search:
- Type partial matches
- Use spaces for multiple terms
- Case insensitive

### Navigation
- Arrow keys to move
- Enter to select
- Ctrl+C to cancel/exit
- ESC to go back (in submenus)

### Gum Commands
You can also use Gum directly in your own scripts:

```bash
# Input
CLUSTER=$(gum input --placeholder "Cluster ID")

# Confirm
gum confirm "Deploy to production?" && deploy

# Choose
ENV=$(gum choose "dev" "staging" "prod")

# Filter (fuzzy search)
POD=$(kubectl get pods -A | gum filter)

# Spin (loading)
gum spin --title "Deploying..." -- kubectl apply -f app.yaml

# Style (colors/borders)
gum style --foreground 212 --bold "Success!"
```

## GitHub Actions Example

```yaml
name: Create Cluster
on:
  workflow_dispatch:
    inputs:
      cluster_id:
        required: true
        default: "101"

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Install Task
      - name: Install Task
        run: sh -c "$(curl -sL https://taskfile.dev/install.sh)" -- -d -b /usr/local/bin

      # Task automatically uses plain text mode in CI
      - name: Create cluster
        run: task cluster:create -- ${{ inputs.cluster_id }}

      - name: Install Flux
        run: task flux:install -- ${{ inputs.cluster_id }}
```

## Troubleshooting

### Gum not found
```bash
brew install gum
```

### Mods not configured
```bash
mods --settings
# Add your API key
```

### Menu display issues
```bash
# Check terminal size
echo $COLUMNS $LINES

# Try resizing terminal
# Ensure TERM is set correctly
echo $TERM
```

### CI/CD mode not activating
The task should auto-detect, but you can force plain mode:
```bash
# Remove TTY (forces CI mode)
task cluster:create -- 101 < /dev/null
```

## Documentation

- [Charm Tools](https://charm.sh)
- [Gum](https://github.com/charmbracelet/gum)
- [Glow](https://github.com/charmbracelet/glow)
- [Mods](https://github.com/charmbracelet/mods)
- [Task](https://taskfile.dev)

## Next Steps

1. ✅ Interactive menu working
2. ✅ AI assistant integrated
3. ✅ CI/CD compatibility
4. 🔜 Try `task menu` and explore!
5. 🔜 Configure Mods for AI features: `mods --settings`

---

**Pro Tip**: Bookmark `task menu` as your go-to command for all cluster operations!
