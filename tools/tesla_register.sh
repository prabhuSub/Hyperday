#!/bin/zsh
# One-time: tell Tesla that prabhusub.github.io is Hyperday's domain (partner account registration).
# Reads your Client ID / Secret from .tesla-keys/client.env (never committed). Prints only Tesla's reply.
set -e
cd "$(dirname "$0")/.."
ENV=.tesla-keys/client.env
if [[ ! -f $ENV ]]; then
  echo "Create $ENV with two lines:"; echo "  TESLA_CLIENT_ID=..."; echo "  TESLA_CLIENT_SECRET=..."; exit 1
fi
source $ENV
AUD=https://fleet-api.prd.na.vn.cloud.tesla.com   # North America
TOKEN=$(curl -s -X POST https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode grant_type=client_credentials \
  --data-urlencode client_id="$TESLA_CLIENT_ID" \
  --data-urlencode client_secret="$TESLA_CLIENT_SECRET" \
  --data-urlencode 'scope=openid vehicle_device_data vehicle_location vehicle_cmds vehicle_charging_cmds' \
  --data-urlencode audience=$AUD | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("access_token") or ("ERROR " + json.dumps(d)))')
[[ $TOKEN == ERROR* ]] && { echo "Sign-in failed: $TOKEN"; exit 1; }
echo "Registering prabhusub.github.io with Tesla…"
curl -s -X POST $AUD/api/1/partner_accounts -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"domain":"prabhusub.github.io"}'
echo
