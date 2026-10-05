#!/bin/zsh
# One-time: grant "Hyperday Personal" access to YOUR Tesla account (the OAuth consent),
# then save the tokens to .tesla-keys/tokens.json and list your cars as a test.
# Needed before the virtual-key link (tesla.com/_ak/...) will work.
set -e
cd "$(dirname "$0")/.."
ENV=.tesla-keys/client.env
ID=$(sed -n 's/^TESLA_CLIENT_ID=//p' $ENV | tr -d '\r')
SECRET=$(sed -n 's/^TESLA_CLIENT_SECRET=//p' $ENV | tr -d '\r')
REDIRECT=https://prabhusub.github.io/hyperday/callback
AUD=https://fleet-api.prd.na.vn.cloud.tesla.com
STATE=$(openssl rand -hex 8)
SCOPES="openid offline_access vehicle_device_data vehicle_location vehicle_cmds vehicle_charging_cmds"
URL=$(python3 -c 'import sys,urllib.parse as u; print("https://auth.tesla.com/oauth2/v3/authorize?"+u.urlencode({"response_type":"code","client_id":sys.argv[1],"redirect_uri":sys.argv[2],"scope":sys.argv[3],"state":sys.argv[4],"locale":"en-US","prompt_missing_scopes":"true"}))' "$ID" "$REDIRECT" "$SCOPES" "$STATE")
echo "1) Your browser is opening Tesla's sign-in. Sign in and tap Allow."
echo "2) You'll land on a 'Returning to Hyperday…' page (Safari may say it can't open the address — that's fine)."
echo "3) Copy the FULL address from the address bar and paste it here."
open "$URL"
echo
read "BACK?Paste the address: "
CODE=$(python3 -c 'import sys,urllib.parse as u; q=u.parse_qs(u.urlparse(sys.argv[1]).query); print(q.get("code",[""])[0]); sys.exit(0 if q.get("state",[""])[0]==sys.argv[2] else 3)' "$BACK" "$STATE") || { echo "That address doesn't match this sign-in (state mismatch). Run again."; exit 1; }
[[ -z $CODE ]] && { echo "No code in that address."; exit 1; }
curl -s -X POST https://fleet-auth.prd.vn.cloud.tesla.com/oauth2/v3/token \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode grant_type=authorization_code \
  --data-urlencode client_id="$ID" --data-urlencode client_secret="$SECRET" \
  --data-urlencode code="$CODE" --data-urlencode audience=$AUD \
  --data-urlencode redirect_uri=$REDIRECT > .tesla-keys/tokens.json
chmod 600 .tesla-keys/tokens.json
ACCESS=$(python3 -c 'import json; d=json.load(open(".tesla-keys/tokens.json")); print(d.get("access_token",""))')
[[ -z $ACCESS ]] && { echo "Token exchange failed:"; python3 -c 'import json; d=json.load(open(".tesla-keys/tokens.json")); print({k:v for k,v in d.items() if "token" not in k})'; exit 1; }
echo "Signed in. Access granted. Your cars (no wake-up, one data call):"
curl -s $AUD/api/1/vehicles -H "Authorization: Bearer $ACCESS" | python3 -c 'import sys,json; d=json.load(sys.stdin); [print(" -", v.get("display_name"), "·", v.get("state")) for v in d.get("response",[])] or print(d)'
echo "Now open https://tesla.com/_ak/prabhusub.github.io on your iPhone again."
