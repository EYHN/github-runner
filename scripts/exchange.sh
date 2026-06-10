#!/usr/bin/env bash
# Thin bootstrap: prove identity via GitHub OIDC, fetch the credential bundle and
# the dynamic script payload from the github-claw platform, then hand off.
# This is the ONLY logic in this public repo; everything else is downloaded.

set -euo pipefail
set +x

: "${PLATFORM_URL:?PLATFORM_URL repo variable not set}"
: "${SESSION_ID:?}"
: "${OIDC_AUDIENCE:?}"
: "${CLAW_TMP:?}"

log() { echo ">>> $*"; }

# ---- 1. request a GitHub Actions OIDC token for our audience ----
log "Requesting OIDC token..."
OIDC_TOKEN="$(curl -fsS \
  -H "Authorization: Bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN}" \
  "${ACTIONS_ID_TOKEN_REQUEST_URL}&audience=${OIDC_AUDIENCE}" | jq -r '.value')"
echo "::add-mask::${OIDC_TOKEN}"
[[ -n "$OIDC_TOKEN" && "$OIDC_TOKEN" != "null" ]] || { echo "no OIDC token" >&2; exit 1; }

# ---- 2. exchange for the credential bundle ----
log "Exchanging credentials..."
CLAW_BUNDLE="${CLAW_TMP}/bundle.json"
http_code="$(curl -fsS -o "$CLAW_BUNDLE" -w '%{http_code}' \
  -X POST "${PLATFORM_URL}/api/runner/exchange" \
  -H "Content-Type: application/json" \
  -d "$(jq -n --arg s "$SESSION_ID" --arg t "$OIDC_TOKEN" '{session_id:$s, oidc_token:$t}')" \
  || echo "000")"
if [[ "$http_code" != "200" ]]; then
  echo "exchange failed (HTTP $http_code)" >&2
  # best-effort: tell the platform so it can fail the Lark card
  curl -fsS -X POST "${PLATFORM_URL}/api/runner/failed?session_id=${SESSION_ID}" >/dev/null 2>&1 || true
  exit 1
fi
chmod 600 "$CLAW_BUNDLE"

# Mask every secret field and export the session token.
SESSION_TOKEN="$(jq -r '.session_token' "$CLAW_BUNDLE")"; echo "::add-mask::${SESSION_TOKEN}"
jq -r '.bore.secret // empty' "$CLAW_BUNDLE" | while read -r v; do echo "::add-mask::$v"; done
export SESSION_TOKEN
export PLATFORM_URL CLAW_BUNDLE CLAW_TMP
export ENV_KIND="$(jq -r '.env // "macos"' "$CLAW_BUNDLE")"

# ---- 3. fetch the dynamic payload (scripts) ----
log "Fetching payload (${ENV_KIND})..."
PAYLOAD="${CLAW_TMP}/payload.json"
curl -fsS "${PLATFORM_URL}/api/runner/payload?env=${ENV_KIND}" \
  -H "Authorization: Bearer ${SESSION_TOKEN}" -o "$PAYLOAD"

CLAW_DIR="${CLAW_TMP}/payload"
mkdir -p "$CLAW_DIR"
# Write each file from the manifest with its mode.
jq -c '.files[]' "$PAYLOAD" | while read -r f; do
  path="$(echo "$f" | jq -r '.path')"
  mode="$(echo "$f" | jq -r '.mode')"
  dest="${CLAW_DIR}/${path}"
  mkdir -p "$(dirname "$dest")"
  echo "$f" | jq -r '.content_base64' | base64 -d > "$dest"
  chmod "$mode" "$dest"
done
ENTRY="$(jq -r '.entrypoint' "$PAYLOAD")"
export CLAW_DIR

# ---- 4. hand off to the platform-provided bootstrap ----
log "Handoff to ${ENTRY}..."
exec "${CLAW_DIR}/${ENTRY}"
