#!/usr/bin/env bash
# Checks that your Supabase project accepts the synthetic participant emails and that sign-up works
# without email confirmation. It CREATES ONE TEST USER ("probe-xxxxxx") in your project; delete it
# afterwards in Dashboard -> Authentication -> Users. Uses only the publishable key from ios/Config.local.xcconfig.
# Usage: scripts/probe-auth.sh [domain]     (default: PARTICIPANT_EMAIL_DOMAIN from the xcconfig)
set -euo pipefail
cd "$(dirname "$0")/.."
cfg=ios/Config.local.xcconfig
get() { grep -E "^$1 *=" "$cfg" | head -1 | sed -E 's/^[^=]*= *//; s#:/\$\(\)/#://#'; }
url=$(get SUPABASE_URL); key=$(get SUPABASE_PUBLISHABLE_KEY); domain=${1:-$(get PARTICIPANT_EMAIL_DOMAIN)}
suffix=$(printf '%06x' $(( (RANDOM * 32768 + RANDOM) % 16777216 )))   # no pipe from urandom: SIGPIPE + pipefail would exit silently
email="probe-$suffix@$domain"; pass="probe-pass-$RANDOM"
echo "project: $url"; echo "trying:  $email"
body=$(curl -sS -w '\n%{http_code}' -X POST "$url/auth/v1/signup" -H "apikey: $key" -H 'content-type: application/json' \
  -d "{\"email\":\"$email\",\"password\":\"$pass\"}")
code=${body##*$'\n'}; json=${body%$'\n'*}
echo "signup HTTP $code"
case "$code" in
  200) if echo "$json" | grep -q '"access_token"'; then echo "OK: sign-up returned a session (email confirmation is off)."
       else echo "PROBLEM: user created but no session. Turn OFF 'Confirm email' (Authentication -> Providers -> Email)."; fi ;;
  4*)  echo "PROBLEM: $json"; echo "If this says the email is invalid, try another domain: scripts/probe-auth.sh yourdomain.org" ;;
  *)   echo "Unexpected: $json" ;;
esac
echo "Remember to delete $email in Authentication -> Users."
