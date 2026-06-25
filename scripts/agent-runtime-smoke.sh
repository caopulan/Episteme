#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/agent-runtime-smoke.sh [--codex] [--claude] [--kimi-cli] [--kimi-acp] [--gemini-acp] [--kimi-openclaw] [--hermes-kimi] [--pi]

Options:
  --all              Run Codex, Claude Code, Kimi CLI, Kimi ACP, Gemini ACP, OpenClaw Kimi, Hermes Kimi, and pi routes.
  --codex            Run codex exec in a fixture Episteme workspace.
  --claude           Run claude --print in a fixture Episteme workspace.
  --kimi-cli         Run kimi -p with stream-json output in a fixture Episteme workspace.
  --kimi-acp         Run kimi acp through a fixture Episteme ACP client.
  --gemini-acp       Run gemini --experimental-acp through a fixture Episteme ACP client.
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
run_kimi_cli=0
run_kimi_acp=0
run_gemini_acp=0
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
      run_kimi_cli=1
      run_kimi_acp=1
      run_gemini_acp=1
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
    --kimi-cli)
      run_kimi_cli=1
      ;;
    --kimi-acp)
      run_kimi_acp=1
      ;;
    --gemini-acp)
      run_gemini_acp=1
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

if [ "$run_codex$run_claude$run_kimi_cli$run_kimi_acp$run_gemini_acp$run_kimi_openclaw$run_hermes_kimi$run_pi" = "00000000" ]; then
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
  if [ "${EPISTEME_MCP_METADATA:-}" != "" ]; then
    candidates+=("$EPISTEME_MCP_METADATA")
  fi
  if [ "${PAPER_CODEX_MCP_METADATA:-}" != "" ]; then
    candidates+=("$PAPER_CODEX_MCP_METADATA")
  fi
  if [ "${EPISTEME_SUPPORT_ROOT:-}" != "" ]; then
    candidates+=("$EPISTEME_SUPPORT_ROOT/mcp/server.json")
  fi
  if [ "${PAPER_CODEX_SUPPORT_ROOT:-}" != "" ]; then
    candidates+=("$PAPER_CODEX_SUPPORT_ROOT/mcp/server.json")
  fi
  candidates+=("$HOME/Library/Application Support/Episteme/mcp/server.json")
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
# Episteme Prompt Contract

Use Episteme citation markers for grounded paper claims:

[[cite:paper:{paper_id}:p{page}:b{block_index}]]
[[cite:paper:{paper_id}:p{page}:a{anchor_suffix}]]
MARKDOWN

cat >"$workspace/agent_instructions.md" <<'MARKDOWN'
# Agent Instructions

Read workspace_manifest.json and prompt_contract.md before answering.
Use workspace files for source reading and generated artifacts.
Use MCP tools for app state changes.
Do not mutate the Episteme library during this smoke test.
MARKDOWN

cat >"$workspace/papers/smoke-paper/metadata.json" <<'JSON'
{
  "paper_id": "smoke-paper",
  "title": "Episteme Runtime Smoke Paper"
}
JSON

cat >"$workspace/papers/smoke-paper/full_text.txt" <<'TEXT'
[[cite:paper:smoke-paper:p1:b0]] Episteme runtime smoke tests verify workspace and prompt-contract visibility.
TEXT

cat >"$workspace/papers/smoke-paper/spans.jsonl" <<'JSONL'
{"id":"paper:smoke-paper:p1:b0","paper_id":"smoke-paper","page":1,"text":"Episteme runtime smoke tests verify workspace and prompt-contract visibility."}
JSONL

cat >"$workspace/papers/smoke-paper/pages.jsonl" <<'JSONL'
{"paper_id":"smoke-paper","page":1,"text":"Episteme runtime smoke tests verify workspace and prompt-contract visibility.","confidence":1.0}
JSONL

cat >"$workspace/papers/smoke-paper/anchors.jsonl" <<'JSONL'
JSONL

mcp_config_path=""
if [ "$mcp_endpoint" != "" ]; then
  mcp_config_path="$workspace/mcp.json"
  ruby -rjson -e 'path, url, token = ARGV; File.write(path, JSON.pretty_generate({"mcpServers" => {"paper-codex" => {"type" => "http", "url" => url, "headers" => {"Authorization" => "Bearer #{token}"}}}}))' "$mcp_config_path" "$mcp_endpoint" "$mcp_token"
  mkdir -p "$workspace/.kimi-code"
  cp "$mcp_config_path" "$workspace/.kimi-code/mcp.json"
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
    "title" => "Episteme Runtime Smoke Paper",
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
You are running an Episteme local runtime smoke test for ${runtime}.

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
Set mcp_endpoint_seen according to whether mcp.json contains an Episteme endpoint.
Do not modify Episteme app state.
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

run_acp_and_verify() {
  local runtime="$1"
  local output_file="$2"
  shift 2
  local prompt
  prompt=$(make_prompt "$runtime")
  echo "==> $runtime"
  ruby -rjson -ropen3 -rthread -rfileutils -e '
workspace = ARGV.shift
prompt = ARGV.shift
output_file = ARGV.shift
cmd = ARGV
raise "missing ACP command" if cmd.empty?

def inside_workspace(path, workspace)
  expanded = File.expand_path(path, workspace)
  root = File.expand_path(workspace)
  expanded == root || expanded.start_with?(root + File::SEPARATOR)
end

def resolve_path(raw, workspace)
  raise "path must be a string" unless raw.is_a?(String) && !raw.empty?
  path = raw.start_with?("/") ? File.expand_path(raw) : File.expand_path(raw, workspace)
  raise "path outside workspace: #{path}" unless inside_workspace(path, workspace)
  path
end

stdin, stdout, stderr, wait_thr = Open3.popen3(*cmd, chdir: workspace)
queue = Queue.new
stderr_tail = +""
final_text = +""
session_id = nil
request_id = 0

stdout_thread = Thread.new do
  stdout.each_line do |line|
    next if line.strip.empty?
    begin
      queue << JSON.parse(line)
    rescue JSON::ParserError => e
      queue << { "__reader_error" => "#{e}: #{line[0, 500]}" }
    end
  end
  queue << { "__eof" => true }
end

stderr_thread = Thread.new do
  stderr.each_line do |line|
    stderr_tail << line
    stderr_tail = stderr_tail[-4000, 4000] || stderr_tail
  end
end

send_json = lambda do |payload|
  stdin.write(JSON.generate(payload))
  stdin.write("\n")
  stdin.flush
end

handle_agent_request = lambda do |message|
  method = message["method"].to_s
  id = message["id"]
  params = message["params"] || {}
  begin
    result =
      case method
      when "fs/read_text_file"
        path = resolve_path(params["path"], workspace)
        content = File.read(path, encoding: "UTF-8")
        if params.key?("line") || params.key?("limit")
          lines = content.lines
          start = [(params["line"] || 1).to_i - 1, 0].max
          limit = params["limit"]&.to_i
          content = limit ? lines[start, limit].join : lines[start..]&.join.to_s
        end
        { "content" => content }
      when "fs/write_text_file"
        path = resolve_path(params["path"], workspace)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, params.fetch("content").to_s, encoding: "UTF-8")
        {}
      when "session/request_permission"
        options = params["options"].is_a?(Array) ? params["options"] : []
        selected = options.find { |option| option["kind"].to_s.start_with?("allow") } || options.first
        selected ? { "outcome" => { "outcome" => "selected", "optionId" => selected["optionId"] } } : { "outcome" => { "outcome" => "cancelled" } }
      else
        raise "unsupported ACP client method: #{method}"
      end
    send_json.call({ "jsonrpc" => "2.0", "id" => id, "result" => result })
  rescue => e
    send_json.call({ "jsonrpc" => "2.0", "id" => id, "error" => { "code" => -32603, "message" => e.message } })
  end
end

request = lambda do |method, params, timeout|
  request_id += 1
  id = request_id
  send_json.call({ "jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params })
  deadline = Time.now + timeout
  loop do
    raise "ACP #{method} timed out; stderr tail: #{stderr_tail}" if Time.now >= deadline
    begin
      message = queue.pop(true)
    rescue ThreadError
      sleep 0.05
      raise "ACP subprocess exited; stderr tail: #{stderr_tail}" unless wait_thr.alive?
      next
    end
    raise message["__reader_error"] if message["__reader_error"]
    raise "ACP subprocess closed stdout; stderr tail: #{stderr_tail}" if message["__eof"]
    if message["method"] && message.key?("id")
      handle_agent_request.call(message)
      next
    end
    if message["method"] == "session/update"
      update = message.dig("params", "update") || {}
      if update["sessionUpdate"] == "agent_message_chunk"
        content = update["content"] || {}
        final_text << content["text"].to_s if content["type"] == "text"
      end
      next
    end
    next unless message["id"].to_s == id.to_s
    raise "ACP #{method} failed: #{message["error"].inspect}; stderr tail: #{stderr_tail}" if message["error"]
    return message["result"] || {}
  end
end

begin
  initialize = request.call(
    "initialize",
    {
      "protocolVersion" => 1,
      "clientCapabilities" => { "fs" => { "readTextFile" => true, "writeTextFile" => true }, "terminal" => false },
      "clientInfo" => { "name" => "episteme-smoke", "title" => "Episteme Smoke", "version" => "0" }
    },
    20
  )
  raise "ACP protocol mismatch: #{initialize["protocolVersion"].inspect}" unless initialize["protocolVersion"].to_i == 1
  session = request.call("session/new", { "cwd" => workspace, "mcpServers" => [] }, 60)
  session_id = session.fetch("sessionId")
  result = request.call(
    "session/prompt",
    { "sessionId" => session_id, "prompt" => [{ "type" => "text", "text" => prompt }] },
    Integer(ENV.fetch("ACP_SMOKE_TIMEOUT_SECONDS", "180"))
  )
  raise "ACP stopped with #{result["stopReason"].inspect}" unless result["stopReason"] == "end_turn"
  File.write(output_file, final_text, encoding: "UTF-8")
ensure
  begin
    request.call("session/close", { "sessionId" => session_id }, 5) if session_id
  rescue
  end
  stdin.close unless stdin.closed?
  Process.kill("TERM", wait_thr.pid) if wait_thr.alive?
  stdout_thread.kill
  stderr_thread.kill
end
' "$workspace" "$prompt" "$output_file" "$@"
  cat "$output_file"
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
  claude_args=(--print --output-format stream-json --verbose --system-prompt "Use Episteme workspace files and return strict JSON only." "--add-dir=$workspace")
  if [ "$mcp_config_path" != "" ]; then
    claude_args+=("--mcp-config=$mcp_config_path")
  fi
  claude_args+=("$prompt")
  run_and_verify "claude-code" "$workspace/turns/claude-output.log" claude "${claude_args[@]}"
fi

if [ "$run_kimi_cli" -eq 1 ]; then
  require_executable kimi
  prompt=$(make_prompt "kimi-cli")
  if [ "${KIMI_CLI_MODEL:-}" != "" ]; then
    run_and_verify "kimi-cli" "$workspace/turns/kimi-cli-output.log" \
      kimi -m "$KIMI_CLI_MODEL" -p "$prompt" --output-format stream-json
  else
    run_and_verify "kimi-cli" "$workspace/turns/kimi-cli-output.log" \
      kimi -p "$prompt" --output-format stream-json
  fi
fi

if [ "$run_kimi_acp" -eq 1 ]; then
  require_executable kimi
  run_acp_and_verify "kimi-acp" "$workspace/turns/kimi-acp-output.log" kimi acp
fi

if [ "$run_gemini_acp" -eq 1 ]; then
  require_executable gemini
  run_acp_and_verify "gemini-acp" "$workspace/turns/gemini-acp-output.log" gemini --experimental-acp
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
    pi -p --mode json --session-dir "$workspace/agent-sessions/pi" --system-prompt "Use Episteme workspace files and return strict JSON only." --append-system-prompt "$workspace/agent_instructions.md" "$prompt"
fi
