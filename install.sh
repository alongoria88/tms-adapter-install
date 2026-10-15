#!/usr/bin/env bash
# Deploy the TMS adapter from its private GitHub repo with one command:
#
#   curl -fsSL https://raw.githubusercontent.com/alongoria88/tms-adapter-install/main/install.sh | bash -s aws
#                                                                                     (or gcp / azure)
# 1. Signs you in to GitHub in your browser (you enter a short code on github.com/login/device).
#    Only GitHub users with access to the private repo get through.
# 2. Downloads the private repo into ~/tms-adapter, or updates it if it's already there
#    (your saved settings and deployment records in that folder are kept).
# 3. Runs ./deploy.sh <cloud>, which deploys, tests and prints the connection details.
#
# The GitHub token is read-only, limited to the private repo, kept in memory for this run
# only, and expires within 8 hours. Set GITHUB_TOKEN to skip the browser sign-in (CI).
# Needs git, curl and python3: every cloud's browser shell has them.

set -euo pipefail

REPO="alongoria88/happy-robot-fde-challenge"
REF="${TMS_ADAPTER_REF:-main}"            # branch or tag to deploy
DIR="${TMS_ADAPTER_DIR:-$HOME/tms-adapter}"
# The "TMS Adapter Installer" GitHub App. A client ID is public by design, not a secret.
CLIENT_ID="${TMS_ADAPTER_CLIENT_ID:-REPLACE_WITH_CLIENT_ID}"

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n    → %s\n' "$1" "$2" >&2; exit 1; }
json() { python3 -c 'import json,sys; print(json.load(sys.stdin).get(sys.argv[1], ""))' "$1"; }

# Everything runs inside main(), called on the last line, so a half-downloaded script
# never runs.
main() {
  local cloud="${1:-}"
  case "$cloud" in
    aws|gcp|azure) shift ;;
    *) fail "which cloud?" "curl -fsSL <this script's URL> | bash -s aws   (or gcp / azure)" ;;
  esac
  for tool in git curl python3; do
    command -v "$tool" >/dev/null || fail "$tool is not installed" "run this from your cloud's browser shell, which has it"
  done
  # The script itself arrives on stdin, so the deploy's questions must read from the terminal.
  [[ -r /dev/tty ]] || fail "no terminal to ask questions on" "run this in an interactive shell"

  echo "TMS adapter: deploy to $cloud"
  local token="${GITHUB_TOKEN:-}"
  [[ -n "$token" ]] || token="$(github_sign_in)" || exit 1

  # A user without access, or an app not installed on the repo, both look like 404 here.
  local status
  status="$(curl -sS -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $token" \
            "https://api.github.com/repos/$REPO")"
  [[ "$status" == 200 ]] || fail "this GitHub user cannot read $REPO (HTTP $status)" \
    "ask us to add your GitHub user to the repo, then run the same command again"
  ok "GitHub access to $REPO"

  # The token goes in a header for this one git command only; it is never written to disk.
  local auth
  auth="AUTHORIZATION: basic $(printf 'x-access-token:%s' "$token" | base64 | tr -d '\n')"
  if [[ -d "$DIR/.git" ]]; then
    git -C "$DIR" -c http.extraHeader="$auth" fetch -q --depth 1 origin "$REF" \
      || fail "could not download the latest version" "check your internet access and run again"
    # Settings, Terraform state and handover files are gitignored, so this keeps them.
    git -C "$DIR" checkout -q -f FETCH_HEAD
    ok "updated $DIR to the latest $REF"
  else
    git -c http.extraHeader="$auth" clone -q --depth 1 --branch "$REF" \
      "https://github.com/$REPO.git" "$DIR" \
      || fail "could not download $REPO" "check your internet access and run again"
    ok "downloaded to $DIR"
  fi
  echo

  cd "$DIR"
  exec ./deploy.sh "$cloud" "$@" </dev/tty
}

# GitHub's device sign-in: show a code, the user approves it in their browser, we get a token.
github_sign_in() {
  [[ "$CLIENT_ID" != REPLACE_* ]] || fail "installer not configured (no GitHub App client ID)" "contact us"
  local start device_code user_code url interval
  start="$(curl -fsS -X POST -H 'Accept: application/json' \
            -d "client_id=$CLIENT_ID" https://github.com/login/device/code)" \
    || fail "could not reach GitHub" "check internet access to github.com"
  device_code="$(json device_code <<<"$start")"
  user_code="$(json user_code <<<"$start")"
  url="$(json verification_uri <<<"$start")"
  interval="$(json interval <<<"$start")"
  [[ -n "$device_code" ]] || fail "GitHub refused the sign-in request: $start" "contact us"

  {
    echo
    echo "  Sign in to GitHub to download the adapter:"
    printf '    1. Open  \033[1m%s\033[0m\n' "$url"
    printf '    2. Enter \033[1m%s\033[0m and click Authorize\n' "$user_code"
    printf '  Waiting'
  } >&2

  local reply error token
  while true; do
    sleep "${interval:-5}"
    reply="$(curl -fsS -X POST -H 'Accept: application/json' \
              -d "client_id=$CLIENT_ID" -d "device_code=$device_code" \
              -d grant_type=urn:ietf:params:oauth:grant-type:device_code \
              https://github.com/login/oauth/access_token)" || reply='{}'
    token="$(json access_token <<<"$reply")"
    if [[ -n "$token" ]]; then echo >&2; echo "$token"; return; fi
    error="$(json error <<<"$reply")"
    case "$error" in
      authorization_pending|"") printf '.' >&2 ;;
      slow_down) interval=$(( ${interval:-5} + 5 )) ;;
      expired_token) echo >&2; fail "the code expired before it was approved" "run the same command again" ;;
      access_denied) echo >&2; fail "sign-in was cancelled on GitHub" "run the same command again and click Authorize" ;;
      *) echo >&2; fail "GitHub sign-in failed: $error" "run the same command again" ;;
    esac
  done
}

main "$@"
