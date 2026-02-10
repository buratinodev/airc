# airc - AI-Powered Shell Assistant

A bash/zsh shell function that wraps LLM (via `llm` CLI) to provide intelligent command suggestions with safety checks and context awareness.

## Purpose

**airc** transforms your shell into an intelligent assistant that:
- **Understands natural language**: Type what you want to do, not the exact command syntax
- **Learns from context**: Automatically considers your current directory, git status, and recent commands
- **Protects you from mistakes**: Requires explicit confirmation for risky operations with color-coded warnings
- **Explains its reasoning**: Can explain why it suggested a command and what it does
- **Fixes errors automatically**: Detects failed commands and suggests corrections

Perfect for:
- Learning new commands and tools
- Working with unfamiliar systems
- Preventing destructive mistakes
- Speeding up common tasks
- Understanding what went wrong when commands fail

## Features

- **Smart Command Suggestions**: Ask in natural language, get shell commands
- **Context-Aware**: Automatically captures shell history, current directory, and git status
- **Safety First**: 
  - Requires explicit "YES" confirmation for risky operations (sudo, rm, dd, shred, kubectl delete, etc.)
  - Standard Y/n confirmation for safe commands
  - Color-coded warnings (red for risky, green for safe, yellow for aborted)
  - Detects complex destructive patterns (e.g., `find ... -exec rm`, `shred`, etc.)
- **Memory**: Remembers last suggestion for quick redo/explain
- **Auto-Fix**: Detects failed commands and suggests fixes
- **Colorized Output**: Preserves colors in ls, grep, diff, and tree commands
- **Agent Mode**: Autonomous multi-step task execution with tool use, checkpoints, and safety controls
- **Dual Modes**:
  - **sysadmin** (default): Concise, practical suggestions
  - **deep**: Step-by-step reasoning with edge case analysis

## Installation

### Automatic Installation

1. Clone or download this repository:
   ```bash
   git clone https://github.com/buratinodev/airc.git
   cd airc
   ```

2. Run the installer:
   ```bash
   ./airc.sh --install
   ```

   This will:
   - Copy `airc.sh` to `~/.airc`
   - Detect your shell (bash or zsh)
   - Add the loader to your `~/.bashrc` or `~/.zshrc`
   - Display instructions for activating

3. Load airc in your current shell:
   ```bash
   source ~/.zshrc  # or source ~/.bashrc for bash users
   ```

   Or simply open a new terminal window.

### Manual Installation

If you prefer to install manually or need to customize the installation:

1. Copy the script to your home directory:
   ```bash
   cp airc.sh ~/.airc
   ```

2. Add to your shell configuration file (`~/.bashrc` or `~/.zshrc`):
   ```bash
   # Load AI shell helpers
   if [[ -f "$HOME/.airc" ]]; then
     source "$HOME/.airc"
   fi
   ```

3. Reload your shell configuration:
   ```bash
   source ~/.zshrc  # or source ~/.bashrc
   ```

### Prerequisites

You need the `llm` CLI tool with a configured model:

1. Install `llm`:
   ```bash
   pip install llm
   ```

2. Install the Ollama plugin and pull the model:
   ```bash
   llm install llm-ollama
   ollama pull qwen2.5-coder:32b
   ```

   Or modify the script to use a different model by changing the `AI_MODEL` variable at the top of the script.

## Usage

### Basic Command Suggestions

Simply describe what you want to do in natural language:

```bash
ai list all files
# Suggests: ls -la
# Prompt: Execute this command? [Y/n]:

ai find large files over 100MB
# Suggests: find . -type f -size +100M
# Prompt: Execute this command? [Y/n]:
```

### Conversational Queries

For questions and greetings, airc responds directly without suggesting a command:

```bash
ai how are you?
# I'm here and ready to help! How can I assist you today?

ai what is a symlink?
# A symlink (symbolic link) is a file that points to another file or directory...
```

> **Note**: You can use special characters like `?` and `*` without quoting - airc handles them automatically in zsh.

### Risky Command Handling

Destructive commands require typing "YES" (not just Y):

```bash
ai delete all .tmp files
# Suggests: find . -name "*.tmp" -type f -exec rm {} +
# ⚠️  Risky command detected.
# Type YES to execute (Ctrl+C to abort):

ai remove old docker containers
# Suggests: docker container prune
# ⚠️  Risky command detected.
# Type YES to execute (Ctrl+C to abort):
```

**Risky commands include**:
- `sudo` - privilege escalation
- `rm` - file deletion (including all variants)
- `dd`, `mkfs` - disk operations
- `shred` - secure deletion
- `find ... -exec rm/shred` - bulk deletion
- `kubectl delete` - Kubernetes resource deletion
- `terraform apply/destroy` - infrastructure changes
- `gcloud delete` - cloud resource deletion

### Explanation Mode

Get a detailed explanation of the last suggested command:

```bash
ai explain
# Provides detailed explanation of why the command was suggested,
# what it does, and any potential risks
```

### Agent Mode

For complex, multi-step tasks, use agent mode. The agent autonomously plans and executes a sequence of actions to achieve your goal:

```bash
ai --agent set up a new git repo with .gitignore for Node.js
# ╔══════════════════════════════════════════════════════════╗
# ║  🤖 Agent Mode                                         ║
# ║  Goal: set up a new git repo with .gitignore for Node.js║
# ║  Max steps: 15 │ Ctrl+C to abort                       ║
# ╚══════════════════════════════════════════════════════════╝
#
#   ⚡ Run  step 1/15  [██░░░░░░░░] 6%
#   $ git init
#   ┌──────────────────────────────────────────────────────
#   │ Initialized empty Git repository in ...
#   └──────────────────────────────────────── ✓ exit 0 ──
#   ...
#   ✅ Done! Completed in 3 step(s)
```

**Safe mode** — requires confirmation before each action:

```bash
ai --agent-safe reorganize the project structure
# Each step will prompt: Allow? [Y/n/skip]:
# - Y: execute the action
# - n: abort the agent entirely
# - s/skip: skip this step and continue
```

**Continuation** — when the agent reaches the max steps limit, it asks if you want to keep going:

```
  ⚠️  Reached max steps (15) without completing goal.
  Continue for another 15 steps? [Y/n]:
```

The step counter resets and the agent continues where it left off.

**Resume from checkpoint** — if an agent run is interrupted or paused:

```bash
ai --agent --resume
# Picks up from the last saved checkpoint
```

#### Agent Tools

The agent has access to these built-in tools:

| Tool | Description |
|------|-------------|
| `COMMAND: <cmd>` | Execute any shell command |
| `TOOL:read_file(<path>)` | Read a file's contents |
| `TOOL:write_file(<path>, <content>)` | Write content to a file |
| `TOOL:search(<pattern>, <dir>)` | Search for text in files |
| `TOOL:web_fetch(<url>)` | Fetch a URL's content |
| `TOOL:list_dir(<path>)` | List directory contents |

#### Agent Safety

- Risky commands (rm, sudo, etc.) always require confirmation, even in auto mode
- `rm -rf` is blocked entirely
- Use `--agent-safe` to approve every action individually
- Checkpoints are saved after each step so you can resume if interrupted

### Auto-Fix Mode

Just run `ai` (no arguments) after a command fails:

```bash
$ kubectl get pod
error: the server doesn't have a resource type "pod"

$ ai
# AI analyzes the error and suggests:
# "The resource type should be 'pods' (plural). Try: kubectl get pods"
```

### Special Commands

**Redo last suggestion**:
```bash
ai redo
```

**Explain last suggestion**:
```bash
ai explain
```

**Deep thinking mode**:
```bash
ai --deep migrate database from postgres to mysql
```

## Safety Features

- **Strict confirmation** (must type "YES") for risky operations:
  - `sudo` - privilege escalation
  - `rm` - all file deletion commands (including `-rf`, `-r`, etc.)
  - `dd`, `mkfs` - disk operations
  - `shred` - secure deletion
  - `find` with `-exec rm` or `-exec shred` - bulk deletion
  - `mv` to deleted/trash directories
  - `kubectl delete` - Kubernetes deletions
  - `terraform apply/destroy` - infrastructure changes
  - `gcloud delete` - cloud resource deletion
- **Standard confirmation** (Y/n) for all other commands
- **Color-coded warnings**: Red for risky, green for safe, yellow for aborted
- **Preserved command output**: Colors maintained for ls, grep, diff, tree
- **Context awareness**: Considers your location, git state, and recent history

### Aborting Commands

- **Standard commands**: Press `n` and Enter, or just Enter to accept
- **Risky commands**: Type anything except "YES" to abort
- **Anytime**: Press `Ctrl+C` to abort immediately

## How It Works

1. Captures context (shell history, pwd, git status, last exit code)
2. Sends your prompt + context to the LLM
3. Gets back a suggested command
4. Presents it for review
5. Confirms before execution (stricter for risky commands)
6. Executes and saves output

## File Structure

```
/tmp/ai/
├── last_command.txt    # Last suggested command
├── last_prompt.txt     # Original user intent
├── last_persona.txt    # Persona used (sysadmin/deep)
├── last_output.txt     # Output from last execution
├── last_context/
│   ├── history.txt     # Last 15 shell commands
│   ├── pwd.txt         # Current directory
│   ├── git.txt         # Git status
│   └── exit.txt        # Last exit code
└── agent/              # Agent mode state
    └── checkpoints/
        ├── step_001.json   # Per-step metadata
        ├── step_001.out    # Step output
        ├── step_002.json
        ├── step_002.out
        └── agent_log.txt   # Cumulative log
```

## Customization

### Change the LLM Model
Edit the `AI_MODEL` variable at the top of the script:
```bash
AI_MODEL="qwen2.5-coder:32b"
```

### Agent Settings

Adjust the maximum steps per batch before the agent asks to continue:
```bash
AI_AGENT_MAX_STEPS=15
```

Configure which tools the agent can use:
```bash
AI_AGENT_TOOLS="command,read_file,write_file,search,web_fetch"
```

### Adjust Safety Rules
Modify the risky command detection regex in the `_ai_confirm_and_run` function to add or remove patterns.

### Customize Colors
Change the color definitions at the top of the script:
```bash
COLOR_RED="\033[1;31m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_CYAN="\033[1;36m"
COLOR_RESET="\033[0m"
```

Set them to empty strings to disable colors:
```bash
COLOR_RED=""
COLOR_GREEN=""
# ... etc
```

### Add Custom Personas
Add new persona modes by extending the persona flag logic around line 52.

## Requirements

- bash or zsh shell
- `llm` CLI tool with `llm-ollama` plugin
- An LLM model (default: qwen2.5-coder:32b via Ollama)
- Basic Unix tools: `grep`, `tee`, `mkdir`, `cat`

## License

MIT

## Contributing

Feel free to submit issues or pull requests!
