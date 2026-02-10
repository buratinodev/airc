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
- **Dual Modes**:
  - **sysadmin** (default): Concise, practical suggestions
  - **deep**: Step-by-step reasoning with edge case analysis

## Installation
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

ai compress all logs in /var/log
# Suggests: tar -czf logs_backup.tar.gz /var/log/*.log
# Prompt: Execute this command? [Y/n]:

ai show git branches sorted by last commit
# Suggests: git branch --sort=-committerdate
# Prompt: Execute this command? [Y/n]:
```

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
# Re-displays and re-executes the last suggested command
```

**Explain last suggestion**:
```bash
ai explain
# Provides detailed explanation of why the command was suggested,
# what it does, and any potential risks
```

**Deep thinking mode**:
```bash
ai --deep migrate database from postgres to mysql
# Uses more thorough analysis, considers edge cases and failure modes
```

### Aborting Commands

- **Standard commands**: Press `n` and Enter, or just Enter to accept
- **Risky commands**: Type anything except "YES" to abort
- **Anytime**: Press `Ctrl+C` to abort immediately

### Color Coding

The wrapper uses colors to help you quickly identify information:
- **Cyan**: Headings (e.g., "Suggested command:")
- **Yellow/Bright Yellow**: Suggested commands and abort messages
- **Green**: Safe command prompts
- **Red**: Risky command warnings and errorsI explains the error and suggests a fix
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

## How It Works

1. Captures context (shell history, pwd, git status, last exit code)
2. Sends your prompt + context to the LLM
3. Gets back a suggested command
4. Presents it for review
5. Confirms before execution (stricter for risky commands)
6. Executes and saves output

## Safety Features

- **Hard block** on `rm -rf`
- **Strict confirmation** (must type "YES") for:
  - sudo commands
  - rm operations
  - dd, mkfs
  - kubectl delete
  - terraform apply/destroy
  - gcloud delete
- **Standard confirmation** (Y/n) for all other commands

## File Structure

```
/tmp/ai/
├── last_command.txt    # Last suggested command
├── last_prompt.txt     # Original user intent
├── last_persona.txt    # Persona used (sysadmin/deep)
├── last_output.txt     # Output from last execution
└── last_context/
    ├── history.txt     # Last 15 shell commands
    ├── pwd.txt         # Current directory
    ├── git.txt         # Git status
    └── exit.txt        # Last exit code
```

## Customization

### Change the LLM Model
Edit the `llm -m qwen2.5-coder:14b` calls in the script to use your preferred model.

### Adjust Safety Rules
Modify the regex patterns in the script:
- Hard blocks: Line ~119
- Risky command detection: Line ~140

### Add Custom Personas
Add new persona modes by extending the persona flag logic around line 52.

## Requirements

- bash or zsh shell
- `llm` CLI tool
- An LLM model (default: qwen2.5-coder:14b via Ollama)
- Basic Unix tools: `grep`, `tee`, `mkdir`, `cat`

## License

MIT

## Contributing

Feel free to submit issues or pull requests!
