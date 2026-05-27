#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/agent-runtime-smoke.sh [--codex] [--claude] [--kimi-openclaw] [--hermes-kimi] [--pi]

Options:
  --all              Run Codex, Claude Code, OpenClaw Kimi, Hermes Kimi, and pi routes.
  --codex            Run codex exec in a fixture Paper Codex workspace.
  --claude           Run claude --print in a fixture Paper Codex workspace.
  --kimi-openclaw    Run openclaw agent --local --json with OPENCLAW_MODEL.
  --hermes-kimi      Run hermes chat through the Kimi provider.
  --pi               Run pi print mode in the fixture workspace.
  --workspace PATH   Reuse an existing workspace instead of creating a temporary one.
  --keep-workspace   Do not remove a temporary workspace after the run.
  --write-test       Reserved for explicit future app-state write tests; default is read-only.
  -h, --help         Show this help.
USAGE
}

run_codex=0
run_claude=0
run_kimi_openclaw=0
run_hermes_kimi=0
run_pi=0
keep_workspace=0
write_test=0
workspace=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --all)
      run_codex=1
      run_claude=1
      run_kimi_openclaw=1
      run_hermes_kimi=1
      run_pi=1
      ;;
    --codex)
      run_codex=1
      ;;
    --claude)
      run_claude=1
      ;;
    --kimi-openclaw)
      run_kimi_openclaw=1
      ;;
    --hermes-kimi)
      run_hermes_kimi=1
      ;;
    --pi)
      run_pi=1
      ;;
    --workspace)
      shift
      if [ "$#" -eq 0 ]; then
        echo "--workspace requires a path" >&2
        exit 2
      fi
      workspace="$1"
      ;;
    --keep-workspace)
      keep_workspace=1
      ;;
    --write-test)
      write_test=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$run_codex$run_claude$run_kimi_openclaw$run_hermes_kimi$run_pi" = "00000" ]; then
  usage >&2
  exit 2
fi

if [ "$write_test" -eq 1 ]; then
  echo "--write-test is reserved; this smoke script currently performs read-only workspace checks." >&2
  exit 2
fi

require_executable() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing executable: $1" >&2
    exit 1
  fi
}

json_value() {
  ruby -rjson -e 'j=JSON.parse(File.read(ARGV[0])); print j[ARGV[1]].to_s' "$1" "$2"
}

detect_mcp_metadata() {
  local candidates=()
  if [ "${PAPER_CODEX_MCP_METADATA:-}" != "" ]; then
    candidates+=("$PAPER_CODEX_MCP_METADATA")
  fi
  if [ "${PAPER_CODEX_SUPPORT_ROOT:-}" != "" ]; then
    candidates+=("$PAPER_CODEX_SUPPORT_ROOT/mcp/server.json")
  fi
  candidates+=("$HOME/Library/Application Support/PaperCodex/mcp/server.json")

  local candidate
  for candidate in "${candidates[@]}"; do
    if [ -f "$candidate" ]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

created_workspace=0
if [ "$workspace" = "" ]; then
  workspace=$(mktemp -d "${TMPDIR:-/tmp}/paper-codex-agent-smoke.XXXXXX")
  created_workspace=1
else
  mkdir -p "$workspace"
fi

cleanup() {
  if [ "$created_workspace" -eq 1 ] && [ "$keep_workspace" -eq 0 ]; then
    rm -rf "$workspace"
  else
    echo "workspace: $workspace"
  fi
}
trap cleanup EXIT

mcp_endpoint=""
mcp_health=""
mcp_token=""
mcp_seen=false
if metadata_path=$(detect_mcp_metadata); then
  mcp_endpoint=$(json_value "$metadata_path" url)
  mcp_health=$(json_value "$metadata_path" healthURL)
  mcp_token=$(json_value "$metadata_path" token)
  if [ "$mcp_health" != "" ] && curl -fsS "$mcp_health" >/dev/null 2>&1; then
    mcp_seen=true
  fi
fi

mkdir -p "$workspace/papers/smoke-paper" "$workspace/turns" "$workspace/agent-sessions/pi"

cat >"$workspace/session.json" <<'JSON'
{
  "id": "agent-runtime-smoke-session",
  "title": "Agent Runtime Smoke Session",
  "paper_ids": ["smoke-paper"],
  "default_runtime_id": "smoke",
  "workspace_materialization_mode": "copy_pdf"
}
JSON

cat >"$workspace/prompt_contract.md" <<'MARKDOWN'
# Paper Codex Prompt Contract

Use Paper Codex citation markers for grounded paper claims:

[[cite:paper:{paper_id}:p{page}:b{block_index}]]
[[cite:paper:{paper_id}:p{page}:a{anchor_suffix}]]
MARKDOWN

cat >"$workspace/agent_instructions.md" <<'MARKDOWN'
# Agent Instructions

Read workspace_manifest.json and prompt_contract.md before answering.
Use workspace files for source reading and generated artifacts.
Use MCP tools for app state changes.
Do not mutate the Paper Codex library during this smoke test.
MARKDOWN

cat >"$workspace/papers/smoke-paper/metadata.json" <<'JSON'
{
  "paper_id": "smoke-paper",
  "title": "Paper Codex Runtime Smoke Paper"
}
JSON

cat >"$workspace/papers/smoke-paper/full_text.txt" <<'TEXT'
[[cite:paper:smoke-paper:p1:b0]] Paper Codex runtime smoke tests verify workspace and prompt-contract visibility.
TEXT

cat >"$workspace/papers/smoke-paper/spans.jsonl" <<'JSONL'
{"id":"paper:smoke-paper:p1:b0","paper_id":"smoke-paper","page":1,"text":"Paper Codex runtime smoke tests verify workspace and prompt-contract visibility."}
JSONL

cat >"$workspace/papers/smoke-paper/pages.jsonl" <<'JSONL'
{"paper_id":"smoke-paper","page":1,"text":"Paper Codex runtime smoke tests verify workspace and prompt-contract visibility.","confidence":1.0}
JSONL

cat >"$workspace/papers/smoke-paper/anchors.jsonl" <<'JSONL'
JSONL

mcp_config_path=""
if [ "$mcp_endpoint" != "" ]; then
  mcp_config_path="$workspace/mcp.json"
  ruby -rjson -e 'path, url, token = ARGV; File.write(path, JSON.pretty_generate({"mcpServers" => {"paper-codex" => {"url" => url, "headers" => {"Authorization" => "Bearer #{token}"}}}}))' "$mcp_config_path" "$mcp_endpoint" "$mcp_token"
fi

ruby -rjson -e '
workspace = ARGV[0]
mcp_config = ARGV[1]
manifest = {
  "session_id" => "agent-runtime-smoke-session",
  "workspace_path" => workspace,
  "materialization_mode" => "copy_pdf",
  "mcp_config_path" => mcp_config.empty? ? nil : mcp_config,
  "prompt_contract_path" => File.join(workspace, "prompt_contract.md"),
  "agent_instructions_path" => File.join(workspace, "agent_instructions.md"),
  "papers" => [{
    "paper_id" => "smoke-paper",
    "title" => "Paper Codex Runtime Smoke Paper",
    "original_pdf_path" => File.join(workspace, "papers/smoke-paper/original.pdf"),
    "full_text_path" => File.join(workspace, "papers/smoke-paper/full_text.txt"),
    "pages_jsonl_path" => File.join(workspace, "papers/smoke-paper/pages.jsonl"),
    "spans_jsonl_path" => File.join(workspace, "papers/smoke-paper/spans.jsonl"),
    "anchors_jsonl_path" => File.join(workspace, "papers/smoke-paper/anchors.jsonl"),
    "metadata_json_path" => File.join(workspace, "papers/smoke-paper/metadata.json")
  }]
}
File.write(File.join(workspace, "workspace_manifest.json"), JSON.pretty_generate(manifest))
' "$workspace" "$mcp_config_path"

make_prompt() {
  local runtime="$1"
  cat <<PROMPT
You are running a Paper Codex local runtime smoke test for ${runtime}.

Working directory: ${workspace}
Read workspace_manifest.json, prompt_contract.md, agent_instructions.md, and papers/smoke-paper/full_text.txt.

Return strict JSON only with exactly these keys:
{
  "runtime": "${runtime}",
  "workspace_seen": true,
  "citation_contract_seen": true,
  "mcp_endpoint_seen": ${mcp_seen}
}

Set workspace_seen true only if workspace_manifest.json is visible.
Set citation_contract_seen true only if the prompt contract contains [[cite:paper:{paper_id}:p{page}:b{block_index}]].
Set mcp_endpoint_seen according to whether mcp.json contains a Paper Codex endpoint.
Do not modify Paper Codex app state.
PROMPT
}

verify_output() {
  local runtime="$1"
  local output_file="$2"
  local output
  output=$(cat "$output_file")
  local normalized_output
  normalized_output=$(mktemp "${TMPDIR:-/tmp}/paper-codex-agent-smoke-output.XXXXXX")
  sed 's/\\"/"/g' "$output_file" >"$normalized_output"
  if ! grep -Eiq '"runtime"[[:space:]]*:[[:space:]]*"[^"]*'"$runtime"'[^"]*"' "$normalized_output"; then
    echo "Smoke output for $runtime did not contain runtime JSON:" >&2
    echo "$output" >&2
    rm -f "$normalized_output"
    exit 1
  fi
  if ! grep -Eiq '"workspace_seen"[[:space:]]*:[[:space:]]*true' "$normalized_output"; then
    echo "Smoke output for $runtime did not confirm workspace visibility:" >&2
    echo "$output" >&2
    rm -f "$normalized_output"
    exit 1
  fi
  if ! grep -Eiq '"citation_contract_seen"[[:space:]]*:[[:space:]]*true' "$normalized_output"; then
    echo "Smoke output for $runtime did not confirm citation contract visibility:" >&2
    echo "$output" >&2
    rm -f "$normalized_output"
    exit 1
  fi
  if [ "$mcp_seen" = true ] && ! grep -Eiq '"mcp_endpoint_seen"[[:space:]]*:[[:space:]]*true' "$normalized_output"; then
    echo "Smoke output for $runtime did not confirm MCP endpoint visibility:" >&2
    echo "$output" >&2
    rm -f "$normalized_output"
    exit 1
  fi
  rm -f "$normalized_output"
}

run_and_verify() {
  local runtime="$1"
  local output_file="$2"
  shift 2
  echo "==> $runtime"
  (
    cd "$workspace"
    "$@"
  ) | tee "$output_file"
  verify_output "$runtime" "$output_file"
  echo "ok: $runtime"
}

if [ "$run_codex" -eq 1 ]; then
  require_executable codex
  last_message="$workspace/turns/codex-last-message.json"
  prompt=$(make_prompt "codex")
  run_and_verify "codex" "$workspace/turns/codex-output.log" \
    codex exec --skip-git-repo-check --json -C "$workspace" --output-last-message "$last_message" "$prompt"
  if [ -s "$last_message" ]; then
    verify_output "codex" "$last_message"
  fi
fi

if [ "$run_claude" -eq 1 ]; then
  require_executable claude
  prompt=$(make_prompt "claude-code")
  claude_args=(--print --output-format stream-json --verbose --system-prompt "Use Paper Codex workspace files and return strict JSON only." "--add-dir=$workspace")
  if [ "$mcp_config_path" != "" ]; then
    claude_args+=("--mcp-config=$mcp_config_path")
  fi
  claude_args+=("$prompt")
  run_and_verify "claude-code" "$workspace/turns/claude-output.log" claude "${claude_args[@]}"
fi

if [ "$run_kimi_openclaw" -eq 1 ]; then
  require_executable openclaw
  prompt=$(make_prompt "openclaw-kimi")
  output_file="$workspace/turns/openclaw-kimi-output.log"
  echo "==> openclaw-kimi"
  (
    cd "$workspace"
    OPENCLAW_MODEL="${OPENCLAW_MODEL:-kimi-coding/k2p5}" openclaw agent --local --json --session-id "papercodex-smoke-$(date +%s)" --message "$prompt"
  ) | tee "$output_file"
  verify_output "openclaw-kimi" "$output_file"
  echo "ok: openclaw-kimi"
fi

if [ "$run_hermes_kimi" -eq 1 ]; then
  require_executable hermes
  prompt=$(make_prompt "hermes-kimi")
  hermes_args=(chat --query "$prompt" --provider "${HERMES_KIMI_PROVIDER:-kimi}" -Q --ignore-rules --max-turns 8 --source papercodex)
  if [ "${HERMES_KIMI_MODEL:-}" != "" ]; then
    hermes_args+=(--model "$HERMES_KIMI_MODEL")
  fi
  run_and_verify "hermes-kimi" "$workspace/turns/hermes-kimi-output.log" hermes "${hermes_args[@]}"
fi

if [ "$run_pi" -eq 1 ]; then
  require_executable pi
  prompt=$(make_prompt "pi")
  run_and_verify "pi" "$workspace/turns/pi-output.log" \
    pi -p --mode json --session-dir "$workspace/agent-sessions/pi" --system-prompt "Use Paper Codex workspace files and return strict JSON only." --append-system-prompt "$workspace/agent_instructions.md" "$prompt"
fi
