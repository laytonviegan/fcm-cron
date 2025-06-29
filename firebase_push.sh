#!/usr/bin/env bash
set -euo pipefail

###############################################################################
# CONFIG                                                                      #
###############################################################################
SKIP_DUPLICATE=true        # ⇦ set to false if you want to send every 5 min
TOPIC="all_android"        # FCM topic
###############################################################################

echo "DEBUG PROJECT_ID='${PROJECT_ID:-<empty>}'"
echo "DEBUG RTDB_URL ='${RTDB_URL:-<empty>}'"

DB_NODE="/latest/env"
DB_URL="${RTDB_URL}${DB_NODE}.json"
FCM_URL="https://fcm.googleapis.com/v1/projects/${PROJECT_ID}/messages:send"

TOKEN=$(gcloud auth application-default print-access-token)

###############################################################################
# 1. Read current reading from Realtime DB                                     #
###############################################################################
env_json=$(curl -s -H "Authorization: Bearer ${TOKEN}" "${DB_URL}")

# Force everything to *strings* so the banner never shows blanks
temp=$(jq -r '.temp | tostring // ""'         <<<"$env_json")
hum=$( jq -r '.hum  | tostring // ""'         <<<"$env_json")
updated=$(jq -r '.updatedAt     // 0'         <<<"$env_json")
notified=$(jq -r '.lastNotifiedAt // 0'       <<<"$env_json")

# ---------------------------------------------------------------------------
#if $SKIP_DUPLICATE && [[ -z $temp || -z $hum || $updated -le $notified ]]; then
#  echo "No fresh reading – exiting."
#  exit 0
#fi
# ---------------------------------------------------------------------------

###############################################################################
# 2. Build & send FCM message (banner + data)                                  #
###############################################################################
json=$(jq -n --arg t "$temp" --arg h "$hum" --arg topic "$TOPIC" '
  { message:
      { topic: $topic,
        notification: { title: "Weather update",
                        body:  ("Temp " + $t + "°, Hum " + $h + "%") },
        data: { temp: $t, hum: $h },
        android: { priority: "high" } } }')

response=$(curl -s -w "\n%{http_code}" -X POST "$FCM_URL" \
            -H "Authorization: Bearer ${TOKEN}" \
            -H "Content-Type: application/json" \
            -d "$json")
body=$(head -n -1 <<<"$response")
code=$(tail -n1 <<<"$response")
echo "DEBUG FCM code=$code"
echo "DEBUG FCM body=$body"

###############################################################################
# 3. Mark this reading as notified                                             #
###############################################################################
curl -s -X PATCH "${DB_URL}?print=silent" \
     -H "Authorization: Bearer ${TOKEN}" \
     -H "Content-Type: application/json" \
     -d "{\"lastNotifiedAt\":${updated}}"

echo "✅ Sent push for reading @${updated}"
