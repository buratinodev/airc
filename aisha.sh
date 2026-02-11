#!/usr/bin/env bash

# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  aisha — AI-Powered Shell Assistant                                       ║
# ║  https://github.com/buratinodev/aisha                                     ║
# ╚════════════════════════════════════════════════════════════════════════════╝
#
# Table of contents:
#   1. Configuration          — colors, models, OS detection
#   2. Installer              — `./aisha.sh --install`
#   3. Shared helpers         — prompts, risk detection, context capture
#   4. Confirmation & exec    — confirm-and-run with risk gating
#   5. Agent tools            — read_file, write_file, search, etc.
#   6. Agent internals        — dispatcher, checkpoints, history, display
#   7. Agent command executor — step execution with safety checks
#   8. Agent loop             — _ai_agent() main loop
#   9. Main entry point       — _ai() dispatcher + ai() alias
#  10. Zsh integration        — nonomatch, ZLE apostrophe widget


# ============================================================================
# 1. CONFIGURATION
# ============================================================================

# ---- Colors ----
COLOR_RED="\033[1;31m"
COLOR_GREEN="\033[1;32m"
COLOR_YELLOW="\033[1;33m"
COLOR_CYAN="\033[1;36m"
COLOR_DIM="\033[2m"
COLOR_BOLD="\033[1m"
COLOR_WHITE="\033[1;37m"
COLOR_RESET="\033[0m"

# ---- Models ----
AI_MODEL_TASK="qwen3-coder:30b"       # Fast model for command suggestions & agent steps
AI_MODEL_THINKING="qwen3:32b"         # Reasoning model for deep analysis & explanations

# ---- Agent ----
AI_AGENT_MAX_STEPS=15
AI_AGENT_TOOLS="command,read_file,write_file,search,web_fetch"

# ---- OS detection (e.g. "Darwin/arm64 macOS 15.3") ----
AI_OS="$(uname -s)/$(uname -m)"
[[ -f /etc/os-release ]] && AI_OS="$AI_OS $(. /etc/os-release && echo "$NAME $VERSION_ID")"
[[ "$(uname -s)" == "Darwin" ]] && AI_OS="$AI_OS macOS $(sw_vers -productVersion 2>/dev/null)"


# ============================================================================
# 2. INSTALLER  (run as: ./aisha.sh --install)
# ============================================================================

if [[ "$1" == "--install" ]]; then
  user_shell=$(basename "$SHELL")

  if [[ "$user_shell" == "bash" ]]; then
    rc_file="$HOME/.bashrc"
  elif [[ "$user_shell" == "zsh" ]]; then
    rc_file="$HOME/.zshrc"
  else
    echo -e "${COLOR_RED}Error: Unsupported shell '$user_shell'. Only bash and zsh are supported.${COLOR_RESET}"
    exit 1
  fi

  script_path="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  cp "$script_path" "$HOME/.aisha"
  echo -e "${COLOR_GREEN}✓ Copied aisha.sh to ~/.aisha${COLOR_RESET}"

  if grep -q "Load AI shell helpers" "$rc_file" 2>/dev/null; then
    echo -e "${COLOR_YELLOW}⚠ aisha is already configured in $rc_file${COLOR_RESET}"
  else
    echo "" >> "$rc_file"
    echo "# Load AI shell helpers" >> "$rc_file"
    echo 'if [[ -f "$HOME/.aisha" ]]; then' >> "$rc_file"
    echo '  source "$HOME/.aisha"' >> "$rc_file"
    echo 'fi' >> "$rc_file"
    echo -e "${COLOR_GREEN}✓ Added aisha loader to $rc_file${COLOR_RESET}"
  fi

  echo ""
  echo -e "${COLOR_CYAN}Installation complete!${COLOR_RESET}"
  echo -e "Run: ${COLOR_YELLOW}source $rc_file${COLOR_RESET} to load aisha in your current shell"
  echo -e "Or open a new terminal window."
  exit 0
fi


# ============================================================================
# 3. SHARED HELPERS
# ============================================================================

# Regex used to detect risky commands (shared by _ai_confirm_and_run and agent)
_AI_RISKY_RE='(^|\s)(sudo|rm|dd|mkfs|shred|find.*(rm|shred)|mv.*deleted|kubectl delete|terraform (apply|destroy)|gcloud delete)(\s|$)'

# Build a system prompt for the given persona.
_ai_system_prompt() {
  local persona="$1"
  if [[ "$persona" == "deep" ]]; then
    echo "You are a senior systems engineer. The user's OS is: $AI_OS
Think step-by-step, consider edge cases, tradeoffs, and failure modes.
Prefer correctness over speed."
  else
    echo "You are an expert Unix/Linux sysadmin. The user's OS is: $AI_OS
Be concise, practical, and production-safe."
  fi
}

# Select the LLM model for a persona.
_ai_model_for() {
  [[ "$1" == "deep" ]] && echo "$AI_MODEL_THINKING" || echo "$AI_MODEL_TASK"
}

# Capture shell context (history, pwd, git status, exit code) into $ctxdir.
# Sets $last_exit as a side effect.
_ai_capture_context() {
  local ctxdir="$1"
  fc -l -15 > "$ctxdir/history.txt" 2>/dev/null
  pwd > "$ctxdir/pwd.txt"
  git status --short 2>/dev/null > "$ctxdir/git.txt"
  last_exit=$?
  echo "Last exit code: $last_exit" > "$ctxdir/exit.txt"
}

# Strip <think>…</think> blocks, markdown code fences, blank lines, then
# return only the first meaningful line, trimmed.
_ai_strip_response() {
  local raw="$1"
  raw=$(echo "$raw" | sed '/<think>/,/<\/think>/d' | sed 's/^```[a-z]*//g' | sed 's/```$//g' | sed '/^$/d' | head -1)
  raw="${raw#"${raw%%[![:space:]]*}"}"   # trim leading
  raw="${raw%"${raw##*[![:space:]]}"}"   # trim trailing
  echo "$raw"
}


# ============================================================================
# 4. CONFIRMATION & EXECUTION
# ============================================================================

# Confirm a command with the user, then execute it.
# Risky commands require typing "YES"; safe commands accept Y/n.
_ai_confirm_and_run() {
  local cmd="$1"

  if echo "$cmd" | grep -Eq "$_AI_RISKY_RE"; then
    echo -e "${COLOR_RED}⚠️  Risky command detected.${COLOR_RESET}"
    echo -n "Type YES to execute (Ctrl+C to abort): "
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
      echo -e "${COLOR_YELLOW}Aborted.${COLOR_RESET}"
      return 0
    fi
  else
    echo -n -e "${COLOR_GREEN}Execute this command? [Y/n]:${COLOR_RESET} "
    read -r confirm
    confirm=${confirm:-Y}
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo -e "${COLOR_YELLOW}Aborted.${COLOR_RESET}"
      return 0
    fi
  fi

  # Force color output for common commands
  if echo "$cmd" | grep -qE '^(ls|grep|diff|tree)'; then
    export CLICOLOR_FORCE=1
  fi

  eval "$cmd" 2>&1 | tee "/tmp/ai/last_output.txt"
  local exit_code
  if [[ -n "$ZSH_VERSION" ]]; then
    exit_code=${pipestatus[1]}
  else
    exit_code=${PIPESTATUS[0]}
  fi

  unset CLICOLOR_FORCE
  return $exit_code
}


# ============================================================================
# 5. AGENT TOOLS
# ============================================================================

# Each tool takes simple positional arguments and writes to stdout.

_ai_tool_read_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "ERROR: File not found: $file"
    return 1
  fi
  cat "$file"
}

_ai_tool_write_file() {
  local file="$1"; shift
  local content="$*"
  mkdir -p "$(dirname "$file")"
  echo "$content" > "$file"
  echo "OK: Wrote $(wc -c < "$file") bytes to $file"
}

_ai_tool_search() {
  local pattern="$1"
  local dir="${2:-.}"
  grep -rn "$pattern" "$dir" --include='*' 2>/dev/null | head -30
}

_ai_tool_web_fetch() {
  local url="$1"
  if command -v curl &>/dev/null; then
    curl -sL "$url" | head -200
  else
    echo "ERROR: curl not available"
    return 1
  fi
}

_ai_tool_list_dir() {
  local dir="${1:-.}"
  ls -la "$dir" 2>/dev/null
}


# ============================================================================
# 6. AGENT INTERNALS  (dispatcher, checkpoints, history, display)
# ============================================================================

# ---- Tool dispatcher ----
# Parses TOOL:<name>(<args>) and routes to the matching _ai_tool_* function.
_ai_agent_dispatch_tool() {
  local tool_call="$1"
  local stripped="${tool_call#TOOL:}"
  local tool_name tool_args

  tool_name=$(echo "$stripped" | sed 's/(.*//')
  tool_args=$(echo "$stripped" | sed 's/^[a-z_]*(\(.*\))$/\1/')

  if [[ -z "$tool_name" || -z "$tool_args" ]]; then
    echo "ERROR: Invalid tool call format: $tool_call"
    return 1
  fi

  case "$tool_name" in
    read_file)  _ai_tool_read_file "$tool_args" ;;
    write_file)
      local file="${tool_args%%,*}"
      local content="${tool_args#*,}"
      content="${content#"${content%%[![:space:]]*}"}"
      _ai_tool_write_file "$file" "$content"
      ;;
    search)
      local pattern="${tool_args%%,*}"
      local dir="${tool_args#*,}"
      [[ "$dir" == "$tool_args" ]] && dir="."
      dir="${dir#"${dir%%[![:space:]]*}"}"
      _ai_tool_search "$pattern" "$dir"
      ;;
    web_fetch)  _ai_tool_web_fetch "$tool_args" ;;
    list_dir)   _ai_tool_list_dir "$tool_args" ;;
    command)    eval "$tool_args" 2>&1 ;;
    *)
      echo "ERROR: Unknown tool: $tool_name"
      return 1
      ;;
  esac
}

# ---- Checkpoint: save ----
_ai_agent_save_checkpoint() {
  local agentdir="$1" step="$2" cmd="$3" output="$4" step_status="$5"
  local cpdir="$agentdir/checkpoints"
  mkdir -p "$cpdir"

  cat > "$cpdir/step_${step}.json" <<EOF
{
  "step": $step,
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "pwd": "$(pwd)",
  "action": $(echo "$cmd" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read().strip()))' 2>/dev/null || echo "\"$cmd\""),
  "status": "$step_status",
  "output_file": "step_${step}_output.txt"
}
EOF
  echo "$output" > "$cpdir/step_${step}_output.txt"
  echo "[$step] ($step_status) $cmd" >> "$agentdir/agent_log.txt"
}

# ---- Checkpoint: load (returns highest completed step number) ----
_ai_agent_load_checkpoint() {
  local cpdir="$1/checkpoints"
  if [[ ! -d "$cpdir" ]]; then echo "0"; return; fi

  local last_step=0
  for f in "$cpdir"/step_*.json; do
    [[ -f "$f" ]] || continue
    local n; n=$(basename "$f" | sed 's/step_//;s/\.json//')
    [[ "$n" -gt "$last_step" ]] && last_step="$n"
  done
  echo "$last_step"
}

# ---- History: build rolling context (last N steps, 5 lines of output each) ----
_ai_agent_get_history() {
  local agentdir="$1" max_history="${2:-5}"
  local cpdir="$agentdir/checkpoints"

  if [[ ! -d "$cpdir" ]]; then echo ""; return; fi

  local all_files total
  all_files=$(ls "$cpdir"/step_*.json 2>/dev/null | sort -V)
  total=$(echo "$all_files" | grep -c .)

  if [[ $total -gt $max_history ]]; then
    local skipped=$((total - max_history))
    echo "(Steps 1-$skipped omitted for brevity)"
  fi

  echo "$all_files" | tail -n "$max_history" | while IFS= read -r _f; do
    [[ -z "$_f" ]] && continue
    local _sn _act _ss _out
    _sn=$(basename "$_f" | sed 's/step_//;s/\.json//')
    _act=$(grep '"action"' "$_f" | sed 's/.*"action": *"//;s/",*//')
    _ss=$(grep '"status"' "$_f" | sed 's/.*"status": *"//;s/".*//')
    _out=""
    [[ -f "$cpdir/step_${_sn}_output.txt" ]] && _out=$(head -5 "$cpdir/step_${_sn}_output.txt")
    echo "--- Step $_sn ($_ss) ---"
    echo "Action: $_act"
    echo "Output: $_out"
    echo
  done
}

# ---- Display: session header ----
_ai_agent_header() {
  local mode="$1" goal="$2" max_steps="$3"
  local mode_label="auto"
  [[ "$mode" == "safe" ]] && mode_label="safe 🔒"
  echo
  echo -e "${COLOR_CYAN}╔══════════════════════════════════════════════════════════╗${COLOR_RESET}"
  echo -e "${COLOR_CYAN}║${COLOR_RESET}  ${COLOR_WHITE}🤖 Agent Mode${COLOR_RESET} ${COLOR_DIM}($mode_label)${COLOR_RESET}"
  echo -e "${COLOR_CYAN}║${COLOR_RESET}  ${COLOR_BOLD}$goal${COLOR_RESET}"
  echo -e "${COLOR_CYAN}║${COLOR_RESET}  ${COLOR_DIM}Max steps: $max_steps │ Ctrl+C to abort${COLOR_RESET}"
  echo -e "${COLOR_CYAN}╚══════════════════════════════════════════════════════════╝${COLOR_RESET}"
  echo
}

# ---- Display: step header with progress bar ----
_ai_agent_step_header() {
  local iteration="$1" max_steps="$2" label="$3" action="$4"
  local pct=$((iteration * 100 / max_steps))
  local filled=$((pct / 5)) empty=$((20 - filled))
  local bar=""
  for ((i=0; i<filled; i++)); do bar+="█"; done
  for ((i=0; i<empty; i++)); do bar+="░"; done

  echo -e "${COLOR_DIM}──────────────────────────────────────────────────────────${COLOR_RESET}"
  echo -e "${COLOR_CYAN}  $label${COLOR_RESET} ${COLOR_DIM}step $iteration/$max_steps${COLOR_RESET}  ${COLOR_DIM}[$bar]${COLOR_RESET} ${COLOR_DIM}${pct}%${COLOR_RESET}"
  echo -e "  ${COLOR_YELLOW}❯ $action${COLOR_RESET}"
}

# ---- Display: command output with box drawing ----
_ai_agent_show_output() {
  local output="$1" exit_code="$2"
  local line_count
  line_count=$(echo "$output" | wc -l | tr -d ' ')

  if [[ -n "$output" ]]; then
    echo -e "${COLOR_DIM}  ┌─ output ──────────────────────────────────────────────${COLOR_RESET}"
    echo "$output" | head -10 | sed 's/^/  │ /'
    [[ "$line_count" -gt 10 ]] && echo -e "  │ ${COLOR_DIM}... ($((line_count - 10)) more lines)${COLOR_RESET}"
    echo -e "${COLOR_DIM}  └──────────────────────────────────────────────────────${COLOR_RESET}"
  fi

  if [[ "$exit_code" -ne 0 ]]; then
    echo -e "  ${COLOR_RED}✗ exit code $exit_code${COLOR_RESET}"
  else
    echo -e "  ${COLOR_GREEN}✓ ok${COLOR_RESET}"
  fi
  echo
}


# ============================================================================
# 7. AGENT COMMAND EXECUTOR
# ============================================================================

# Execute one agent step with safety gating.
# Returns: 0=executed, 1=aborted, 2=skipped
_ai_agent_exec_cmd() {
  local cmd="$1" mode="$2" agentdir="$3" iteration="$4"

  # Risky commands always require confirmation, regardless of mode
  local is_risky=false
  echo "$cmd" | grep -Eq "$_AI_RISKY_RE" && is_risky=true

  if $is_risky; then
    echo -e "  ${COLOR_RED}⚠️  Risky command — requires explicit approval${COLOR_RESET}"
    echo -n -e "  ${COLOR_RED}Type YES to execute, or 'skip' to skip:${COLOR_RESET} "
    read -r confirm
    if [[ "$confirm" == "skip" ]]; then
      _ai_agent_save_checkpoint "$agentdir" "$iteration" "$cmd" "SKIPPED by user (risky)" "skipped"
      echo -e "  ${COLOR_YELLOW}⏭  Skipped${COLOR_RESET}"
      echo
      return 2
    elif [[ "$confirm" != "YES" ]]; then
      _ai_agent_save_checkpoint "$agentdir" "$iteration" "$cmd" "ABORTED by user (risky)" "aborted"
      return 1
    fi
  elif [[ "$mode" == "safe" ]]; then
    echo -n -e "  ${COLOR_GREEN}Execute? [Y/n/skip]:${COLOR_RESET} "
    read -r confirm
    confirm=${confirm:-Y}
    if [[ "$confirm" =~ ^[Ss] ]]; then
      _ai_agent_save_checkpoint "$agentdir" "$iteration" "$cmd" "SKIPPED by user" "skipped"
      echo -e "  ${COLOR_YELLOW}⏭  Skipped${COLOR_RESET}"
      echo
      return 2
    elif [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      _ai_agent_save_checkpoint "$agentdir" "$iteration" "$cmd" "ABORTED by user" "aborted"
      return 1
    fi
  fi

  # Execute
  local cmd_output cmd_exit step_status
  cmd_output=$(eval "$cmd" 2>&1)
  cmd_exit=$?

  _ai_agent_show_output "$cmd_output" "$cmd_exit"

  step_status="ok"
  [[ $cmd_exit -ne 0 ]] && step_status="error"
  _ai_agent_save_checkpoint "$agentdir" "$iteration" "$cmd" "$cmd_output" "$step_status"
  return 0
}


# ============================================================================
# 8. AGENT LOOP
# ============================================================================

_ai_agent() {
  local mode="$1"  # "auto" or "safe"
  shift
  local goal="$*"

  local agentdir="/tmp/ai/agent"
  local max_steps="${AI_AGENT_MAX_STEPS:-15}"

  # ---- Resume or fresh start ----
  local resume=false
  if [[ "$goal" == "--resume" ]]; then
    resume=true
    if [[ ! -f "$agentdir/goal.txt" ]]; then
      echo -e "${COLOR_RED}No agent session to resume.${COLOR_RESET}"
      return 1
    fi
    goal=$(cat "$agentdir/goal.txt")
    mode=$(cat "$agentdir/mode.txt" 2>/dev/null || echo "auto")
    echo -e "${COLOR_CYAN}🔄 Resuming agent session...${COLOR_RESET}"
  else
    rm -rf "$agentdir"
    mkdir -p "$agentdir/checkpoints"
    echo "$goal" > "$agentdir/goal.txt"
    echo "$mode" > "$agentdir/mode.txt"
  fi

  local start_step=0
  if $resume; then
    start_step=$(_ai_agent_load_checkpoint "$agentdir")
    echo -e "  ${COLOR_DIM}Picking up from step $start_step${COLOR_RESET}"
  fi

  _ai_agent_header "$mode" "$goal" "$max_steps"

  # Capture initial context
  local ctxdir="/tmp/ai/last_context"
  fc -l -15 > "$ctxdir/history.txt" 2>/dev/null
  pwd > "$ctxdir/pwd.txt"
  git status --short 2>/dev/null > "$ctxdir/git.txt"

  # ---- Step loop ----
  local iteration=$start_step total_steps=0
  local _resp="" cmd="" exec_result=0 confirm=""

  while true; do
  while [[ $iteration -lt $max_steps ]]; do
    ((iteration++))
    ((total_steps++))

    # Build rolling history (last 5 steps)
    _ai_agent_get_history "$agentdir" 5 > "$agentdir/history_context.txt"

    echo -ne "${COLOR_DIM}  ⏳ Thinking...${COLOR_RESET}\r"

    # ---- Ask LLM for next action ----
    _resp=$(llm -m "$AI_MODEL_TASK" \
      -f "$ctxdir/pwd.txt" \
      -f "$ctxdir/git.txt" \
      -f "$agentdir/goal.txt" \
      -f "$agentdir/history_context.txt" \
      "You are an autonomous shell agent working toward a goal.
The user's OS is: $AI_OS

The goal is in the attached goal.txt.

STEP: $iteration of $max_steps (total: $total_steps)

The attached history_context.txt contains your previous steps.

AVAILABLE TOOLS:
- COMMAND: <shell command>         — Execute a shell command
- TOOL:read_file(<path>)           — Read a file's contents
- TOOL:write_file(<path>, <content>) — Write content to a file
- TOOL:search(<pattern>, <dir>)    — Search for text in files
- TOOL:web_fetch(<url>)            — Fetch a URL's content
- TOOL:list_dir(<path>)            — List directory contents

RESPONSE FORMAT — reply with EXACTLY ONE of:
1. COMMAND: <shell command to execute>
2. TOOL:<tool_name>(<args>)
3. DONE: <summary of what was accomplished>
4. FAILED: <explanation of why the goal cannot be achieved>

Rules:
- One action per step, observe output before deciding next
- Never use rm -rf
- Prefer safe, reversible operations
- If stuck after 3 retries, mark as FAILED")

    echo -ne "\033[2K\r"   # clear thinking indicator

    _resp=$(_ai_strip_response "$_resp")

    # ---- Handle: DONE ----
    if [[ "$_resp" == DONE:* ]]; then
      local summary="${_resp#DONE:}"
      summary="${summary#"${summary%%[![:space:]]*}"}"
      _ai_agent_save_checkpoint "$agentdir" "$iteration" "DONE" "$summary" "done"
      echo -e "${COLOR_DIM}──────────────────────────────────────────────────────────${COLOR_RESET}"
      echo
      echo -e "  ${COLOR_GREEN}✅ Done!${COLOR_RESET} ${COLOR_DIM}Completed in $total_steps step(s)${COLOR_RESET}"
      echo -e "  ${COLOR_WHITE}$summary${COLOR_RESET}"
      echo
      echo -e "  ${COLOR_DIM}📋 Log: $agentdir/agent_log.txt${COLOR_RESET}"
      echo
      return 0

    # ---- Handle: FAILED ----
    elif [[ "$_resp" == FAILED:* ]]; then
      local reason="${_resp#FAILED:}"
      reason="${reason#"${reason%%[![:space:]]*}"}"
      _ai_agent_save_checkpoint "$agentdir" "$iteration" "FAILED" "$reason" "failed"
      echo -e "${COLOR_DIM}──────────────────────────────────────────────────────────${COLOR_RESET}"
      echo
      echo -e "  ${COLOR_RED}❌ Failed at step $iteration${COLOR_RESET}"
      echo -e "  ${COLOR_YELLOW}$reason${COLOR_RESET}"
      echo
      echo -e "  ${COLOR_DIM}💡 Resume with:${COLOR_RESET} ${COLOR_CYAN}ai --agent --resume${COLOR_RESET}"
      echo
      return 1

    # ---- Handle: TOOL call ----
    elif [[ "$_resp" == TOOL:* ]]; then
      _ai_agent_step_header "$iteration" "$max_steps" "🔧 Tool" "$_resp"

      if [[ "$mode" == "safe" ]]; then
        echo -n -e "  ${COLOR_GREEN}Allow? [Y/n/skip]:${COLOR_RESET} "
        read -r confirm
        confirm=${confirm:-Y}
        if [[ "$confirm" =~ ^[Ss] ]]; then
          _ai_agent_save_checkpoint "$agentdir" "$iteration" "$_resp" "SKIPPED by user" "skipped"
          echo -e "  ${COLOR_YELLOW}⏭  Skipped${COLOR_RESET}"
          echo
          continue
        elif [[ ! "$confirm" =~ ^[Yy]$ ]]; then
          _ai_agent_save_checkpoint "$agentdir" "$iteration" "$_resp" "ABORTED by user" "aborted"
          echo
          echo -e "  ${COLOR_YELLOW}Agent paused.${COLOR_RESET} ${COLOR_DIM}Resume with:${COLOR_RESET} ${COLOR_CYAN}ai --agent --resume${COLOR_RESET}"
          echo
          return 1
        fi
      fi

      local tool_output tool_exit step_status
      tool_output=$(_ai_agent_dispatch_tool "$_resp" 2>&1)
      tool_exit=$?
      _ai_agent_show_output "$tool_output" "$tool_exit"
      step_status="ok"
      [[ $tool_exit -ne 0 ]] && step_status="error"
      _ai_agent_save_checkpoint "$agentdir" "$iteration" "$_resp" "$tool_output" "$step_status"

    # ---- Handle: COMMAND (or bare command without prefix) ----
    else
      [[ "$_resp" == COMMAND:* ]] && _resp="${_resp#COMMAND:}"
      cmd="${_resp#"${_resp%%[![:space:]]*}"}"

      _ai_agent_step_header "$iteration" "$max_steps" "⚡ Run" "$cmd"

      _ai_agent_exec_cmd "$cmd" "$mode" "$agentdir" "$iteration"
      exec_result=$?
      if [[ $exec_result -eq 1 ]]; then
        echo
        echo -e "  ${COLOR_YELLOW}Agent paused.${COLOR_RESET} ${COLOR_DIM}Resume with:${COLOR_RESET} ${COLOR_CYAN}ai --agent --resume${COLOR_RESET}"
        echo
        return 1
      elif [[ $exec_result -eq 2 ]]; then
        continue
      fi
    fi
  done

    # ---- Max steps reached — offer continuation ----
    echo -e "${COLOR_DIM}──────────────────────────────────────────────────────────${COLOR_RESET}"
    echo
    echo -e "  ${COLOR_YELLOW}⚠️  Reached max steps ($max_steps) without completing goal.${COLOR_RESET}"
    echo -n -e "  ${COLOR_GREEN}Continue for another $max_steps steps? [Y/n]:${COLOR_RESET} "
    read -r confirm
    confirm=${confirm:-Y}
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      iteration=0
      echo
      echo -e "  ${COLOR_CYAN}↻ Continuing...${COLOR_RESET} ${COLOR_DIM}(total steps so far: $total_steps)${COLOR_RESET}"
      echo
    else
      echo
      echo -e "  ${COLOR_DIM}Stopped after $total_steps total step(s).${COLOR_RESET}"
      echo -e "  ${COLOR_DIM}💡 Resume with:${COLOR_RESET} ${COLOR_CYAN}ai --agent --resume${COLOR_RESET}"
      echo
      return 1
    fi
  done
}


# ============================================================================
# 9. MAIN ENTRY POINT
# ============================================================================

_ai() {
  local tmpdir="/tmp/ai"
  local ctxdir="$tmpdir/last_context"
  mkdir -p "$tmpdir" "$ctxdir"

  # ---- Subcommand: redo ----
  if [[ "$1" == "redo" ]]; then
    if [[ ! -f "$tmpdir/last_command.txt" ]]; then
      echo -e "${COLOR_RED}No previous AI suggestion to redo.${COLOR_RESET}"
      return 1
    fi
    local cmd; cmd=$(cat "$tmpdir/last_command.txt")
    echo -e "${COLOR_CYAN}Redoing last suggested command:${COLOR_RESET}"
    echo -e "  ${COLOR_YELLOW}$cmd${COLOR_RESET}"
    echo
    _ai_confirm_and_run "$cmd"
    return $?
  fi

  # ---- Subcommand: explain ----
  if [[ "$1" == "explain" ]]; then
    if [[ ! -f "$tmpdir/last_command.txt" ]]; then
      echo -e "${COLOR_RED}No previous AI suggestion to explain.${COLOR_RESET}"
      return 1
    fi
    llm -m "$AI_MODEL_THINKING" \
      -f "$ctxdir/history.txt" \
      -f "$ctxdir/pwd.txt" \
      -f "$ctxdir/git.txt" \
      -f "$ctxdir/exit.txt" \
      -f "$tmpdir/last_command.txt" \
      -f "$tmpdir/last_prompt.txt" \
      "You are an expert sysadmin. The user's OS is: $AI_OS
Explain why the command in last_command.txt was suggested, what it does, and any risks.
The original user intent is in last_prompt.txt."
    return
  fi

  # ---- Flag: --deep ----
  local persona="sysadmin"
  if [[ "$1" == "--deep" ]]; then
    persona="deep"
    shift
  fi

  # ---- Delegate to agent mode ----
  if [[ "$1" == "--agent" ]]; then
    shift; _ai_agent "auto" "$@"; return $?
  fi
  if [[ "$1" == "--agent-safe" ]]; then
    shift; _ai_agent "safe" "$@"; return $?
  fi

  # ---- Build prompt ----
  local prompt="$*"
  [[ -n "$prompt" ]] && echo "$prompt" > "$tmpdir/last_prompt.txt"

  # ---- Capture context ----
  local last_exit
  _ai_capture_context "$ctxdir"

  # ---- Auto-fix: empty prompt + previous command failed ----
  if [[ "$last_exit" -ne 0 && -z "$prompt" ]]; then
    llm -m "$AI_MODEL_THINKING" \
      -f "$ctxdir/history.txt" \
      -f "$ctxdir/pwd.txt" \
      -f "$ctxdir/git.txt" \
      -f "$ctxdir/exit.txt" \
      "$(_ai_system_prompt deep)

The user's last command failed.
Explain why it failed and suggest a fix.
Do not execute commands."
    return
  fi

  # ---- Interactive fallback (e.g. if apostrophes broke argument parsing) ----
  if [[ -z "$prompt" ]]; then
    echo -n -e "${COLOR_CYAN}Ask: ${COLOR_RESET}"
    read -r prompt
    [[ -z "$prompt" ]] && return 0
  fi

  # Auto-select deep persona for explanation queries
  if [[ "$prompt" =~ ^(how|why|what|explain|help)(\s|$) ]]; then
    persona="deep"
  fi

  local model; model=$(_ai_model_for "$persona")
  local system_prompt; system_prompt=$(_ai_system_prompt "$persona")

  # ---- Explanation mode (how/why/what/explain/help) ----
  if [[ "$prompt" =~ ^(how|why|what|explain|help)(\s|$) ]]; then
    llm -m "$model" \
      -f "$ctxdir/history.txt" \
      -f "$ctxdir/pwd.txt" \
      -f "$ctxdir/git.txt" \
      -f "$tmpdir/last_prompt.txt" \
      "$system_prompt

Explain and suggest, but do NOT give commands to execute.
The user's question is in the attached last_prompt.txt."
    return
  fi

  # ---- Command suggestion mode ----
  local response
  response=$(llm -m "$model" \
    -f "$ctxdir/history.txt" \
    -f "$ctxdir/pwd.txt" \
    -f "$ctxdir/git.txt" \
    -f "$tmpdir/last_prompt.txt" \
    "$system_prompt

The user's request is in the attached last_prompt.txt.

Rules:
- If the request is a shell/system task, output ONLY the command (no explanation)
- If the request is conversational (greetings like 'hello', 'what's up', 'how are you', jokes, chit-chat, or questions about concepts), prefix your response with 'ANSWER:' followed by a brief, friendly answer — do NOT treat these as system tasks
- Never use rm -rf
- Avoid destructive commands")

  response=$(_ai_strip_response "$response")

  if [[ -z "$response" ]]; then
    echo
    echo -e "${COLOR_YELLOW}No response available.${COLOR_RESET}"
    return 0
  fi

  # ---- Informational answer (not a command) ----
  if [[ "$response" == ANSWER:* ]]; then
    local answer="${response#ANSWER:}"
    answer="${answer#"${answer%%[![:space:]]*}"}"
    echo
    echo -e "${COLOR_CYAN}$answer${COLOR_RESET}"
    return 0
  fi

  # ---- Command suggestion — confirm and run ----
  echo "$response" > "$tmpdir/last_command.txt"
  echo "$persona" > "$tmpdir/last_persona.txt"

  echo
  echo -e "${COLOR_CYAN}Suggested command:${COLOR_RESET}"
  echo -e "  ${COLOR_YELLOW}$response${COLOR_RESET}"
  echo

  _ai_confirm_and_run "$response"
}

# Public alias
ai() { _ai "$@"; }


# ============================================================================
# 10. ZSH INTEGRATION
# ============================================================================

if [[ -n "$ZSH_VERSION" ]]; then
  # Pass unmatched globs (?, *) literally instead of erroring
  setopt nonomatch

  # ZLE widget: transparently replace ' with Unicode ʼ (U+02BC) in ai commands.
  # Visually identical, avoids shell quote-parsing issues. History stays clean.
  _ai_accept_line() {
    if [[ "$BUFFER" =~ ^ai[[:space:]] && "$BUFFER" == *"'"* ]]; then
      BUFFER="${BUFFER//\'/ʼ}"
      CURSOR=${#BUFFER}
    fi
    zle .accept-line
  }
  zle -N accept-line _ai_accept_line
fi
