#!/usr/bin/env bash
set -euo pipefail

# Send an ntfy push ONLY when Claude Code's top-level agent is genuinely waiting
# for the human — i.e. its turn ended (or it's blocked on permission/idle input)
# AND it has no live background work of its own.
#
# Config:
#   CLAUDE_NTFY_TOPIC   (required) ntfy topic to publish to
#   CLAUDE_NTFY_SERVER  (optional) ntfy server, default https://ntfy.sh

TOPIC="${CLAUDE_NTFY_TOPIC:-}"
SERVER="${CLAUDE_NTFY_SERVER:-https://ntfy.sh}"

[[ -z "$TOPIC" ]] && exit 0                       # not configured → silent no-op
command -v jq >/dev/null 2>&1 || exit 0           # can't parse safely → skip

payload="$(cat || true)"
event="$(jq -r '.hook_event_name // "Claude Code"' <<<"$payload" 2>/dev/null || echo "Claude Code")"
cwd="$(jq -r '.cwd // ""'                          <<<"$payload" 2>/dev/null || echo "")"

# 1. Suppress subagent contexts (defense in depth).
#    SubagentStop is the subagent's own stop event; agent_id/agent_type are set
#    in Task-subagent payloads. The top-level/lead agent has none of these.
agent_id="$(jq -r '.agent_id // ""'     <<<"$payload" 2>/dev/null || echo "")"
agent_type="$(jq -r '.agent_type // ""' <<<"$payload" 2>/dev/null || echo "")"
if [[ "$event" == "SubagentStop" \
   || ( -n "$agent_id"   && "$agent_id"   != "null" ) \
   || ( -n "$agent_type" && "$agent_type" != "null" ) ]]; then
  exit 0
fi

# 2. THE FIX for agent-teams spam: on a top-level Stop, suppress if the lead
#    still has live background work (teammates / background tasks "running").
#    Such a Stop means "paused mid-orchestration", NOT "waiting for you" — the
#    lead's own Stop fires every time a teammate reports back. When that work
#    finishes the agent is re-invoked, and the eventual idle Stop (with no
#    running tasks) is the one that notifies. Notification events (permission /
#    idle prompt) are always genuine "waiting for you" and are NOT gated here.
if [[ "$event" == "Stop" ]]; then
  running="$(jq -r '[.background_tasks[]? | select(.status=="running")] | length' <<<"$payload" 2>/dev/null || echo 0)"
  [[ "${running:-0}" -gt 0 ]] && exit 0
fi

# 3. Build + send the notification.
msg="$(jq -r '.last_assistant_message // .message // .transcript_path // "Claude Code is ready for input."' <<<"$payload" 2>/dev/null | head -c 500)"
[[ -z "${msg// }" || "$msg" == "null" ]] && msg="Claude Code is ready for input."

body="$msg"
title="Claude Code: ${event}"
if [[ -n "$cwd" && "$cwd" != "null" ]]; then
  body="${body}

${cwd}"
  title="${title} · $(basename "$cwd")"      # which session, since you run several
fi

curl -fsS \
  -H "Title: ${title}" \
  -H "Tags: robot,computer" \
  -d "$body" \
  "${SERVER%/}/${TOPIC}" >/dev/null || true
