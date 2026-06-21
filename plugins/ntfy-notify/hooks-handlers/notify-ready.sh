#!/usr/bin/env bash
set -euo pipefail

# Notify the human via ntfy when Claude Code's TOP-LEVEL agent wants them — and
# stay quiet during sub-agent / teammate orchestration churn.
#
# Decision model:
#   ASK  (always notify, even mid-orchestration): a Notification that is an
#        explicit request for the human — permission prompt or elicitation.
#   REST (notify once it's a genuine resting point): a Stop, or an idle prompt.
#        - a Stop while background work is running = parked waiting for the team,
#          NOT your turn → suppress (the eventual idle prompt covers real rest).
#        - de-dup: a real rest emits Stop(bg=0) now AND idle ~60s later; collapse
#          them into one push (per session; never affects ASK events).
#   Sub-agent contexts are never notified.
#
# Config:
#   CLAUDE_NTFY_TOPIC      (required) ntfy topic
#   CLAUDE_NTFY_SERVER     (optional) ntfy server, default https://ntfy.sh
#   CLAUDE_NTFY_EVENT_LOG  (optional) path for a metadata-only audit line per
#                          event (no payload content) — useful for discovering
#                          new notification tokens. Unset = no logging.

TOPIC="${CLAUDE_NTFY_TOPIC:-}"
SERVER="${CLAUDE_NTFY_SERVER:-https://ntfy.sh}"
[[ -z "$TOPIC" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

payload="$(cat || true)"
j() { jq -r "$1" <<<"$payload" 2>/dev/null || echo ""; }

event="$(j '.hook_event_name // "Stop"')"
cwd="$(j '.cwd // ""')"
session_id="$(j '.session_id // "nosession"')"
agent_id="$(j '.agent_id // ""')"
agent_type="$(j '.agent_type // ""')"
notif_type="$(j '.notification_type // ""')"
running="$(jq -r '[.background_tasks[]? | select(.status=="running")] | length' <<<"$payload" 2>/dev/null || echo 0)"
running="${running:-0}"

# Optional metadata-only audit (no prompt/tool content; safe to leave on).
if [[ -n "${CLAUDE_NTFY_EVENT_LOG:-}" ]]; then
  printf '%s\t%s\t%s\trunning=%s\n' "$(date '+%F %T')" "$event" "${notif_type:-_}" "$running" \
    >> "$CLAUDE_NTFY_EVENT_LOG" 2>/dev/null || true
fi

# 1. Never notify for sub-agent / teammate contexts (defense in depth).
if [[ "$event" == "SubagentStop" \
   || ( -n "$agent_id"   && "$agent_id"   != "null" ) \
   || ( -n "$agent_type" && "$agent_type" != "null" ) ]]; then
  exit 0
fi

# 2. Classify into ASK / REST / drop.
kind=""
case "$event" in
  Stop) kind="rest" ;;
  Notification)
    case "$notif_type" in
      permission_prompt|elicitation_dialog) kind="ask"  ;;   # explicit human ask
      idle_prompt)                          kind="rest" ;;
      *)                                    exit 0      ;;   # auth_success, *_complete, unknown
    esac ;;
  *) exit 0 ;;
esac

# 3. REST gating + de-dup. ASK events bypass this entirely (always notify).
if [[ "$kind" == "rest" ]]; then
  # Parked mid-orchestration → not your turn.
  [[ "$event" == "Stop" && "$running" -gt 0 ]] && exit 0
  # Collapse the Stop(bg=0)+idle pair (and idle doubles) into one push, per session.
  statefile="${TMPDIR:-/tmp}/claude-ntfy-rest.$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9._-' '_')"
  now="$(date +%s)"; last="$(cat "$statefile" 2>/dev/null || echo 0)"
  [[ "$last" =~ ^[0-9]+$ ]] && (( now - last < 90 )) && exit 0
  printf '%s' "$now" > "$statefile" 2>/dev/null || true
fi

# 4. Build + send.
msg="$(jq -r '.last_assistant_message // .message // "Claude Code is ready for input."' <<<"$payload" 2>/dev/null | head -c 500)"
[[ -z "${msg// }" || "$msg" == "null" ]] && msg="Claude Code is ready for input."

label="$event"; [[ "$kind" == "ask" && -n "$notif_type" ]] && label="$notif_type"
title="Claude Code: ${label}"
body="$msg"
if [[ -n "$cwd" && "$cwd" != "null" ]]; then
  body="${body}

${cwd}"
  title="${title} · $(basename "$cwd")"
fi

curl -fsS -H "Title: ${title}" -H "Tags: robot,computer" -d "$body" "${SERVER%/}/${TOPIC}" >/dev/null || true
