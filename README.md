# airc - AI-Powered Shell Assistant

A bash/zsh shell function that wraps LLM (via `llm` CLI) to provide intelligent command suggestions with safety checks and context awareness.

## Features

- **Smart Command Suggestions**: Ask in natural language, get shell commands
- **Context-Aware**: Automatically captures shell history, current directory, and git status
- **Safety First**: 
  - Blocks `rm -rf` commands
  - Requires explicit confirmation for risky operations (sudo, rm, dd, kubectl delete, etc.)
  - Different confirmation levels based on risk
- **Memory**: Remembers last suggestion for quick redo/explain
- **Auto-Fix**: Detects failed commands and suggests fixes
- **Dual Modes**:
  - **sysadmin** (default): Concise, practical suggestions
  - **deep**: Step-by-step reasoning with edge case analysis

## Installation

1. Install the `llm` CLI tool and configure it with your model:
   ```bash
   pip install llm
   ```

2. Pull the qwen2.5-coder model (or modify to use your preferred model):
   ```bash
   llm install llm-ollama
   ollama pull qwen2.5-coder:14b
   ```

3. Source the script in your `.bashrc` or `.zshrc`:
   ```bash
   echo "source /path/to/.airc" >> ~/.bashrc  # or ~/.zshrc
   source ~/.bashrc  # or source ~/.zshrc
   ```

## Usage

### Basic Command Suggestions
```bash
ai list all files
ai find large files over 100MB
ai compress all logs in /var/log
```

### Explanation Mode
Prefix with question words to get explanations without commands:
```bash
ai how does docker networking work
ai what is the difference between TCP and UDP
ai explain kubernetes pods
```

### Auto-Fix Failed Commands
Just run `ai` after a command fails:
```bash
$ kubectl get pod
# command fails
$ ai
# AI explains the error and suggests a fix
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
