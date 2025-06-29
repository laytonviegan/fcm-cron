#!/usr/bin/env bash
set -euo pipefail

echo "DEBUG PROJECT_ID='${PROJECT_ID:-<empty>}'"
echo "DEBUG RTDB_URL ='${RTDB_URL:-<empty>}'"

# -----------------------------------------------------------------------------
DB_NODE="/latest/env"
DB_URL="${RTDB_URL}${DB_NODE}.json"
FCM_URL="https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send"

TOKEN=$(gcloud auth application-default print-access-token)

# ── 1. Read current reading --------------------------------------------------
env_json=$(curl -s -H "Authorization: Bearer ${TOKEN}" "${DB_URL}")
temp=$(jq -r '.temp // empty'         <<<"$env_json")
hum=$(jq  -r '.hum  // empty'         <<<"$env_json")
updated=$(jq -r '.updatedAt // 0'     <<<"$env_json")
notified=$(jq -r '.lastNotifiedAt // 0'<<<"$env_json")

[[ -z $temp || -z $hum || $updated -le $notified ]] && {
  echo "No fresh reading – exiting."
  exit 0
}

# ── 2. Build & send FCM message ---------------------------------------------
json=$(jq -n --arg t "$temp" --arg h "$hum" '
  { message:
      { topic: "all_android",
        notification: {                          # ensures banner even if app is killed
          title: "Weather update",
          body:  ("Temp " + $t + "°, Hum " + $h + "%")
        },
        data:     { temp: $t, hum: $h },
        android:  { priority: "high" } } }')

response=$(curl -s -w "\n%{http_code}" -X POST "$FCM_URL" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$json")
body=$(head -n -1 <<<"$response")
code=$(tail -n1 <<<"$response")
echo "DEBUG FCM code=$code body=$body"

# ── 3. Mark this reading as notified ----------------------------------------
curl -s -X PATCH "${DB_URL}?print=silent" \
     -H "Authorization: Bearer ${TOKEN}" \
     -H "Content-Type: application/json" \
     -d "{\"lastNotifiedAt\":${updated}}"

echo "✅ Sent push for reading @${updated}"
