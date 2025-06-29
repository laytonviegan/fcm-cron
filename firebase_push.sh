#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID}"
DB_NODE="/latest/env"                   # one-row “current reading”
DB_URL="https://${PROJECT_ID}.firebasedatabase.app${DB_NODE}.json"
FCM_URL="https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send"

TOKEN=$(gcloud auth application-default print-access-token)

# ── 1. Read the current record ────────────────────────────────────────────────
env_json=$(curl -s -H "Authorization: Bearer ${TOKEN}" "${DB_URL}")
temp=$(jq -r '.temp // empty' <<<"$env_json")
hum=$(jq -r '.hum  // empty' <<<"$env_json")
updated=$(jq -r '.updatedAt // 0' <<<"$env_json")
notified=$(jq -r '.lastNotifiedAt // 0' <<<"$env_json")

[[ -z $temp || -z $hum || $updated -le $notified ]] && {
  echo "No fresh reading – exiting."; exit 0; }

# ── 2. Push the FCM message ──────────────────────────────────────────────────
json=$(jq -n --arg t "$temp" --arg h "$hum" '
  { message:
      { topic: "all_android",
        data:
          { title: "Weather update",
            body:  ("Temp " + $t + "°, Hum " + $h + "%"),
            temp:  $t, hum: $h },
        android: { priority: "high" }}}')

curl -s -X POST "$FCM_URL" \
     -H "Authorization: Bearer ${TOKEN}" \
     -H "Content-Type: application/json" \
     -d "$json" | jq .

# ── 3. Mark as notified ──────────────────────────────────────────────────────
curl -s -X PATCH "${DB_URL}?print=silent" \
     -H "Authorization: Bearer ${TOKEN}" \
     -H "Content-Type: application/json" \
     -d "{\"lastNotifiedAt\":${updated}}"

echo "✅ Sent push for reading @${updated}"

