#!/usr/bin/env bash
set -euo pipefail

GHL_API_BASE="${GHL_API_BASE:-https://services.leadconnectorhq.com}"
GHL_API_VERSION="${GHL_API_VERSION:-2021-07-28}"
GHL_API_TOKEN="${GHL_API_TOKEN:-}"
GHL_ACCESS_TOKEN="${GHL_ACCESS_TOKEN:-}"
GHL_LOCATION_ID="${GHL_LOCATION_ID:-}"
GHL_TIMEOUT_SECONDS="${GHL_TIMEOUT_SECONDS:-30}"
GHL_CLIENT_ID="${GHL_CLIENT_ID:-}"
GHL_CLIENT_SECRET="${GHL_CLIENT_SECRET:-}"
GHL_REFRESH_TOKEN="${GHL_REFRESH_TOKEN:-}"
GHL_OAUTH_USER_TYPE="${GHL_OAUTH_USER_TYPE:-Company}"
GHL_OAUTH_REDIRECT_URI="${GHL_OAUTH_REDIRECT_URI:-}"
GHL_OAUTH_SCOPE="${GHL_OAUTH_SCOPE:-}"
GHL_OAUTH_AUTHORIZE_URL="${GHL_OAUTH_AUTHORIZE_URL:-https://marketplace.leadconnectorhq.com/oauth/chooselocation}"
GHL_OAUTH_TOKEN_URL="${GHL_OAUTH_TOKEN_URL:-https://services.leadconnectorhq.com/oauth/token}"

fail() {
  echo "ghlctl: $*" >&2
  exit 1
}

need_bin() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required binary: $1"
}

usage() {
  cat <<'EOF'
Usage:
  ghlctl.sh auth-check [--location <id>] [--live] [--dry-run]
  ghlctl.sh oauth-authorize-url --client-id <id> --redirect-uri <uri> [--user-type Company|Location] [--scope "<space separated scopes>"] [--state <text>] [--auth-url <url>]
  ghlctl.sh oauth-exchange --client-id <id> --client-secret <secret> --code <auth_code> --redirect-uri <uri> [--user-type Company|Location] [--env-file <abs_path>] [--show-tokens] [--dry-run]
  ghlctl.sh oauth-refresh --client-id <id> --client-secret <secret> [--refresh-token <token>] [--user-type Company|Location] [--env-file <abs_path>] [--show-tokens] [--dry-run]
  ghlctl.sh request --method <METHOD> --path </path> [--query "k=v&..."] [--data '<json>'] [--dry-run]
  ghlctl.sh get-location --location <id> [--dry-run]
  ghlctl.sh get-contact --id <id> [--dry-run]
  ghlctl.sh search-contacts [--location <id>] [--query <text> | --data '<json>'] [--page <n>] [--page-limit <n>] [--dry-run]
  ghlctl.sh create-contact --location <id> [--first-name <v>] [--last-name <v>] [--email <v>] [--phone <v>] [--tags a,b] [--dry-run]
  ghlctl.sh update-contact --id <id> [--first-name <v>] [--last-name <v>] [--email <v>] [--phone <v>] [--tags a,b] [--company-name <v>] [--country <v>] [--dry-run]
  ghlctl.sh list-contact-notes --contact-id <id> [--dry-run]
  ghlctl.sh get-contact-note --contact-id <id> --note-id <id> [--dry-run]
  ghlctl.sh create-contact-note --contact-id <id> --body <text> [--dry-run]
  ghlctl.sh update-contact-note --contact-id <id> --note-id <id> --body <text> [--dry-run]
  ghlctl.sh delete-contact-note --contact-id <id> --note-id <id> [--dry-run]
  ghlctl.sh list-contact-tasks --contact-id <id> [--dry-run]
  ghlctl.sh get-contact-task --contact-id <id> --task-id <id> [--dry-run]
  ghlctl.sh create-contact-task --contact-id <id> --title <text> [--due-date <iso>] [--assigned-to <id>] [--completed true|false] [--dry-run]
  ghlctl.sh update-contact-task --contact-id <id> --task-id <id> [--title <text>] [--due-date <iso>] [--assigned-to <id>] [--completed true|false] [--dry-run]
  ghlctl.sh complete-contact-task --contact-id <id> --task-id <id> --completed true|false [--dry-run]
  ghlctl.sh delete-contact-task --contact-id <id> --task-id <id> [--dry-run]
  ghlctl.sh add-contact-to-workflow --contact-id <id> --workflow-id <id> [--dry-run]
  ghlctl.sh remove-contact-from-workflow --contact-id <id> --workflow-id <id> [--dry-run]
  ghlctl.sh list-forms [--location <id>] [--dry-run]
  ghlctl.sh list-surveys [--location <id>] [--dry-run]
  ghlctl.sh list-custom-fields [--location <id>] [--dry-run]
  ghlctl.sh list-pipelines [--location <id>] [--dry-run]
  ghlctl.sh list-calendars [--location <id>] [--dry-run]
  ghlctl.sh list-users [--location <id>] [--dry-run]
  ghlctl.sh get-calendar-slots --calendar-id <id> --start <ms|iso-date> --end <ms|iso-date> [--timezone <iana>] [--dry-run]
  ghlctl.sh search-conversations [--location <id>] --query <text> [--dry-run]
  ghlctl.sh list-conversation-messages --conversation-id <id> [--dry-run]
  ghlctl.sh upload-conversation-attachments [--contact-id <id> | --conversation-id <id>] --file <path> [--file <path> ...] [--dry-run]
  ghlctl.sh send-message --type <SMS|Email|WhatsApp|GMB|IG|FB|Custom> [--contact-id <id> | --conversation-id <id>] --message <text> [--subject <text>] [--html <text>] [--email-from <text>] [--attachments '<json-array>'] [--dry-run]
  ghlctl.sh upsert-contact --location <id> [--first-name <v>] [--last-name <v>] [--email <v>] [--phone <v>] [--tags a,b] [--company-name <v>] [--country <v>] [--dry-run]
  ghlctl.sh create-opportunity --location <id> --contact-id <id> --pipeline-id <id> --stage-id <id> --name <value> [--status <open|won|lost|abandoned>] [--value <number>] [--assigned-to <id>] [--source <value>] [--dry-run]
  ghlctl.sh upsert-opportunity --location <id> [--id <id>] --contact-id <id> --pipeline-id <id> --stage-id <id> --name <value> [--status <open|won|lost|abandoned>] [--value <number>] [--assigned-to <id>] [--source <value>] [--dry-run]
  ghlctl.sh list-workflows [--location <id>] [--dry-run]
  ghlctl.sh list-opportunities [--location <id>] [--limit <n>] [--pipeline-id <id>] [--status open|won|lost|abandoned|all] [--dry-run]
  ghlctl.sh get-opportunity --id <id> [--dry-run]

Environment:
  GHL_API_TOKEN          Preferred bearer token for live API calls
  GHL_ACCESS_TOKEN       Optional bearer token alias (used if GHL_API_TOKEN is empty)
  GHL_LOCATION_ID        Optional default location id
  GHL_API_BASE           Default: https://services.leadconnectorhq.com
  GHL_API_VERSION        Default: 2021-07-28
  GHL_TIMEOUT_SECONDS    Default: 30
  GHL_CLIENT_ID          Optional default OAuth client id
  GHL_CLIENT_SECRET      Optional default OAuth client secret
  GHL_REFRESH_TOKEN      Optional default OAuth refresh token
  GHL_OAUTH_USER_TYPE    Optional default user_type (Company|Location), default Company
  GHL_OAUTH_REDIRECT_URI Optional default OAuth redirect URI
  GHL_OAUTH_SCOPE        Optional default OAuth scopes for authorize URL
  GHL_OAUTH_AUTHORIZE_URL Optional OAuth authorize URL (default marketplace LeadConnector endpoint)
  GHL_OAUTH_TOKEN_URL    Optional OAuth token URL (default services LeadConnector endpoint)

Notes:
  - Use --dry-run to print exact curl command without network calls.
  - Authorization uses: Authorization: Bearer <token>
  - Version header uses: Version: <date>
  - OAuth token exchange follows GoHighLevel Authorization Code flow.
EOF
}

resolve_api_token() {
  if [[ -n "$GHL_API_TOKEN" ]]; then
    printf '%s' "$GHL_API_TOKEN"
    return 0
  fi

  if [[ -n "$GHL_ACCESS_TOKEN" ]]; then
    printf '%s' "$GHL_ACCESS_TOKEN"
    return 0
  fi

  return 1
}

token_or_placeholder() {
  # Never emit live tokens in dry-run output.
  printf '%s' '${GHL_API_TOKEN}'
}

emit_curl() {
  local method="$1"
  local url="$2"
  local data="${3:-}"

  local token
  token="$(token_or_placeholder)"

  local response_file
  local http_code
  local -a cmd
  cmd=(
    curl
    -sS
    --max-time
    "$GHL_TIMEOUT_SECONDS"
    -X
    "$method"
    "$url"
    -H
    "Authorization: Bearer $token"
    -H
    "Version: $GHL_API_VERSION"
    -H
    "Accept: application/json"
  )

  if [[ -n "$data" ]]; then
    cmd+=(-H "Content-Type: application/json" --data "$data")
  fi

  printf '%q ' "${cmd[@]}"
  printf '\n'
}

emit_multipart_curl() {
  local url="$1"
  shift

  local token
  token="$(token_or_placeholder)"

  local -a cmd
  cmd=(
    curl
    -sS
    --max-time
    "$GHL_TIMEOUT_SECONDS"
    -X
    POST
    "$url"
    -H
    "Authorization: Bearer $token"
    -H
    "Version: $GHL_API_VERSION"
    -H
    "Accept: application/json"
  )

  while [[ $# -gt 0 ]]; do
    cmd+=(-F "$1")
    shift
  done

  printf '%q ' "${cmd[@]}"
  printf '\n'
}

call_api() {
  local method="$1"
  local path="$2"
  local query="${3:-}"
  local data="${4:-}"
  local dry_run="${5:-0}"

  local url="${GHL_API_BASE}${path}"
  if [[ -n "$query" ]]; then
    if [[ "$query" == \?* ]]; then
      url="${url}${query}"
    else
      url="${url}?${query}"
    fi
  fi

  if [[ "$dry_run" == "1" ]]; then
    emit_curl "$method" "$url" "$data"
    return 0
  fi

  local bearer_token=""
  if ! bearer_token="$(resolve_api_token)"; then
    fail "missing bearer token: set GHL_API_TOKEN (or GHL_ACCESS_TOKEN)"
  fi

  local -a cmd
  cmd=(
    curl
    -sS
    --max-time
    "$GHL_TIMEOUT_SECONDS"
    -X
    "$method"
    "$url"
    -H
    "Authorization: Bearer $bearer_token"
    -H
    "Version: $GHL_API_VERSION"
    -H
    "Accept: application/json"
  )

  if [[ -n "$data" ]]; then
    cmd+=(-H "Content-Type: application/json" --data "$data")
  fi

  response_file="$(mktemp)"
  http_code="$("${cmd[@]}" -o "$response_file" -w "%{http_code}")"

  if [[ ! "$http_code" =~ ^[0-9]{3}$ ]]; then
    rm -f "$response_file"
    fail "unexpected HTTP status code from API: $http_code"
  fi

  if (( http_code >= 400 )); then
    echo "ghlctl: API request failed: http=$http_code method=$method path=$path" >&2
    cat "$response_file" >&2
    rm -f "$response_file"
    return 11
  fi

  cat "$response_file"
  rm -f "$response_file"
}

call_multipart_api() {
  local path="$1"
  shift

  local url="${GHL_API_BASE}${path}"

  if [[ "${1:-}" == "--dry-run-sentinel" ]]; then
    shift
    emit_multipart_curl "$url" "$@"
    return 0
  fi

  local bearer_token=""
  if ! bearer_token="$(resolve_api_token)"; then
    fail "missing bearer token: set GHL_API_TOKEN (or GHL_ACCESS_TOKEN)"
  fi

  local response_file
  local http_code
  local -a cmd
  cmd=(
    curl
    -sS
    --max-time
    "$GHL_TIMEOUT_SECONDS"
    -X
    POST
    "$url"
    -H
    "Authorization: Bearer $bearer_token"
    -H
    "Version: $GHL_API_VERSION"
    -H
    "Accept: application/json"
  )

  while [[ $# -gt 0 ]]; do
    cmd+=(-F "$1")
    shift
  done

  response_file="$(mktemp)"
  http_code="$("${cmd[@]}" -o "$response_file" -w "%{http_code}")"

  if [[ ! "$http_code" =~ ^[0-9]{3}$ ]]; then
    rm -f "$response_file"
    fail "unexpected HTTP status code from API: $http_code"
  fi

  if (( http_code >= 400 )); then
    echo "ghlctl: API request failed: http=$http_code method=POST path=$path" >&2
    cat "$response_file" >&2
    rm -f "$response_file"
    return 11
  fi

  cat "$response_file"
  rm -f "$response_file"
}

url_encode() {
  need_bin jq
  local value="$1"
  jq -nr --arg value "$value" '$value|@uri'
}

datetime_to_epoch_ms() {
  local raw="$1"
  local timezone="${2:-UTC}"

  if [[ "$raw" =~ ^[0-9]{13}$ ]]; then
    printf '%s' "$raw"
    return 0
  fi

  if [[ "$raw" =~ ^[0-9]{10}$ ]]; then
    printf '%s000' "$raw"
    return 0
  fi

  command -v python3 >/dev/null 2>&1 || fail "python3 is required to convert date values"

  python3 - "$raw" "$timezone" <<'PY'
from datetime import datetime
from zoneinfo import ZoneInfo
import sys

raw = sys.argv[1]
timezone = sys.argv[2]

try:
    dt = datetime.fromisoformat(raw)
except ValueError:
    for fmt in ("%Y-%m-%d", "%Y-%m-%d %H:%M", "%Y-%m-%d %H:%M:%S"):
        try:
            dt = datetime.strptime(raw, fmt)
            break
        except ValueError:
            dt = None
    if dt is None:
        raise

if dt.tzinfo is None:
    dt = dt.replace(tzinfo=ZoneInfo(timezone))

print(int(dt.timestamp() * 1000))
PY
}

normalize_user_type() {
  local raw="${1:-}"
  case "$raw" in
    Company|company|COMPANY|Agency|agency|AGENCY)
      printf '%s' "Company"
      ;;
    Location|location|LOCATION|Subaccount|subaccount|SUBACCOUNT|Sub-Account|sub-account|SubAccount)
      printf '%s' "Location"
      ;;
    *)
      fail "invalid --user-type: $raw (expected Company or Location)"
      ;;
  esac
}

normalize_bool() {
  local raw="${1:-}"
  local lowered
  lowered="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$lowered" in
    true|1|yes|y)
      printf '%s' "true"
      ;;
    false|0|no|n)
      printf '%s' "false"
      ;;
    *)
      fail "invalid boolean value: $raw (expected true or false)"
      ;;
  esac
}

emit_oauth_curl() {
  local grant_type="$1"
  local token_url="$2"
  local client_id="$3"
  local user_type="$4"
  local redirect_uri="${5:-}"

  local -a cmd
  cmd=(
    curl
    -sS
    --max-time
    "$GHL_TIMEOUT_SECONDS"
    -X
    POST
    "$token_url"
    -H
    "Accept: application/json"
    -H
    "Content-Type: application/x-www-form-urlencoded"
    --data-urlencode
    "client_id=$client_id"
    --data-urlencode
    "client_secret=\${GHL_CLIENT_SECRET}"
    --data-urlencode
    "grant_type=$grant_type"
    --data-urlencode
    "user_type=$user_type"
  )

  if [[ "$grant_type" == "authorization_code" ]]; then
    cmd+=(
      --data-urlencode
      "code=\${GHL_AUTH_CODE}"
      --data-urlencode
      "redirect_uri=$redirect_uri"
    )
  else
    cmd+=(
      --data-urlencode
      "refresh_token=\${GHL_REFRESH_TOKEN}"
    )
  fi

  printf '%q ' "${cmd[@]}"
  printf '\n'
}

oauth_token_call() {
  local grant_type="$1"
  local client_id="$2"
  local client_secret="$3"
  local user_type="$4"
  local code="${5:-}"
  local redirect_uri="${6:-}"
  local refresh_token="${7:-}"
  local dry_run="${8:-0}"

  local token_url="$GHL_OAUTH_TOKEN_URL"
  [[ -n "$token_url" ]] || fail "GHL_OAUTH_TOKEN_URL is required"

  if [[ "$dry_run" == "1" ]]; then
    emit_oauth_curl "$grant_type" "$token_url" "$client_id" "$user_type" "$redirect_uri"
    return 0
  fi

  local response_file
  local http_code
  local -a cmd
  cmd=(
    curl
    -sS
    --max-time
    "$GHL_TIMEOUT_SECONDS"
    -X
    POST
    "$token_url"
    -H
    "Accept: application/json"
    -H
    "Content-Type: application/x-www-form-urlencoded"
    --data-urlencode
    "client_id=$client_id"
    --data-urlencode
    "client_secret=$client_secret"
    --data-urlencode
    "grant_type=$grant_type"
    --data-urlencode
    "user_type=$user_type"
  )

  if [[ "$grant_type" == "authorization_code" ]]; then
    cmd+=(
      --data-urlencode
      "code=$code"
      --data-urlencode
      "redirect_uri=$redirect_uri"
    )
  elif [[ "$grant_type" == "refresh_token" ]]; then
    cmd+=(
      --data-urlencode
      "refresh_token=$refresh_token"
    )
  else
    fail "unsupported grant_type: $grant_type"
  fi

  response_file="$(mktemp)"
  http_code="$("${cmd[@]}" -o "$response_file" -w "%{http_code}")"

  if [[ ! "$http_code" =~ ^[0-9]{3}$ ]]; then
    rm -f "$response_file"
    fail "unexpected HTTP status code from OAuth endpoint: $http_code"
  fi

  if (( http_code >= 400 )); then
    echo "ghlctl: OAuth request failed: http=$http_code grant_type=$grant_type" >&2
    cat "$response_file" >&2
    rm -f "$response_file"
    return 12
  fi

  cat "$response_file"
  rm -f "$response_file"
}

ensure_env_file() {
  local env_file="$1"
  [[ "$env_file" == /* ]] || fail "--env-file must be an absolute path: $env_file"
  local env_dir
  env_dir="$(dirname "$env_file")"
  [[ -d "$env_dir" ]] || fail "env directory does not exist: $env_dir"
  if [[ ! -f "$env_file" ]]; then
    (umask 077; : > "$env_file")
  fi
}

upsert_env_key() {
  local env_file="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp)"
  awk -v k="$key" -v v="$value" '
    BEGIN { found = 0 }
    {
      if ($0 ~ "^[[:space:]]*" k "=") {
        print k "=" v
        found = 1
      } else {
        print
      }
    }
    END {
      if (found == 0) {
        print k "=" v
      }
    }
  ' "$env_file" > "$tmp"
  mv "$tmp" "$env_file"
}

persist_oauth_env() {
  local env_file="$1"
  local response_json="$2"
  local client_id="$3"
  local client_secret="$4"
  local user_type="$5"
  [[ -n "$env_file" ]] || return 0

  need_bin jq
  ensure_env_file "$env_file"

  local access_token
  local refresh_token
  access_token="$(jq -r '.access_token // empty' <<<"$response_json")"
  refresh_token="$(jq -r '.refresh_token // empty' <<<"$response_json")"
  [[ -n "$access_token" ]] || fail "OAuth response missing access_token; cannot persist to env"

  upsert_env_key "$env_file" "GHL_API_TOKEN" "$access_token"
  upsert_env_key "$env_file" "GHL_ACCESS_TOKEN" "$access_token"

  if [[ -n "$refresh_token" ]]; then
    upsert_env_key "$env_file" "GHL_REFRESH_TOKEN" "$refresh_token"
  fi
  if [[ -n "$client_id" ]]; then
    upsert_env_key "$env_file" "GHL_CLIENT_ID" "$client_id"
  fi
  if [[ -n "$client_secret" ]]; then
    upsert_env_key "$env_file" "GHL_CLIENT_SECRET" "$client_secret"
  fi

  upsert_env_key "$env_file" "GHL_OAUTH_USER_TYPE" "$user_type"
  upsert_env_key "$env_file" "GHL_OAUTH_TOKEN_URL" "$GHL_OAUTH_TOKEN_URL"
}

validate_oauth_response() {
  local response_json="$1"
  need_bin jq
  local access_token
  access_token="$(jq -r '.access_token // empty' <<<"$response_json")"
  [[ -n "$access_token" ]] || fail "OAuth response did not include access_token"
}

print_oauth_summary() {
  local response_json="$1"
  local grant_type="$2"
  local env_file="${3:-}"
  need_bin jq

  local token_type
  local expires_in
  local company_id
  local location_id

  token_type="$(jq -r '.token_type // "unknown"' <<<"$response_json")"
  expires_in="$(jq -r '.expires_in // "unknown"' <<<"$response_json")"
  company_id="$(jq -r '.companyId // empty' <<<"$response_json")"
  location_id="$(jq -r '.locationId // empty' <<<"$response_json")"

  echo "grant_type=$grant_type"
  echo "token_type=$token_type"
  echo "expires_in=$expires_in"
  echo "access_token=set"
  if jq -e '(.refresh_token // "") | length > 0' >/dev/null <<<"$response_json"; then
    echo "refresh_token=set"
  else
    echo "refresh_token=missing"
  fi
  if [[ -n "$company_id" ]]; then
    echo "company_id=$company_id"
  fi
  if [[ -n "$location_id" ]]; then
    echo "location_id=$location_id"
  fi
  if [[ -n "$env_file" ]]; then
    echo "env_file_updated=$env_file"
  fi
}

resolve_location() {
  local given="${1:-}"
  if [[ -n "$given" ]]; then
    printf '%s' "$given"
    return 0
  fi
  if [[ -n "$GHL_LOCATION_ID" ]]; then
    printf '%s' "$GHL_LOCATION_ID"
    return 0
  fi
  fail "missing --location and GHL_LOCATION_ID is not set"
}

pretty_print() {
  need_bin jq
  jq .
}

render_output() {
  local dry_run="${1:-0}"
  if [[ "$dry_run" == "1" ]]; then
    cat
  else
    pretty_print
  fi
}

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
  usage
  exit 1
fi
shift || true

case "$cmd" in
  -h|--help|help)
    usage
    ;;

  auth-check)
    dry_run=0
    live=0
    location=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --live)
          live=1; shift ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for auth-check: $1" ;;
      esac
    done

    if [[ "$live" == "1" ]]; then
      location="$(resolve_location "$location")"
      call_api GET "/locations/${location}" "" "" "$dry_run" | render_output "$dry_run"
    else
      echo "api_base=$GHL_API_BASE"
      echo "api_version=$GHL_API_VERSION"
      if resolve_api_token >/dev/null 2>&1; then
        echo "api_token=set"
      else
        echo "api_token=missing"
      fi
      if [[ -n "$GHL_CLIENT_ID" ]]; then
        echo "oauth_client_id=set"
      else
        echo "oauth_client_id=missing"
      fi
      if [[ -n "$GHL_CLIENT_SECRET" ]]; then
        echo "oauth_client_secret=set"
      else
        echo "oauth_client_secret=missing"
      fi
      if [[ -n "$GHL_REFRESH_TOKEN" ]]; then
        echo "oauth_refresh_token=set"
      else
        echo "oauth_refresh_token=missing"
      fi
      echo "oauth_user_type=$(normalize_user_type "$GHL_OAUTH_USER_TYPE")"
      if [[ -n "$location" || -n "$GHL_LOCATION_ID" ]]; then
        echo "location_id=$(resolve_location "$location")"
      else
        echo "location_id=missing"
      fi
      if [[ "$dry_run" == "1" ]]; then
        location="${location:-${GHL_LOCATION_ID:-<location_id>}}"
        emit_curl GET "${GHL_API_BASE}/locations/${location}" ""
      fi
    fi
    ;;

  oauth-authorize-url)
    client_id="${GHL_CLIENT_ID:-}"
    redirect_uri="${GHL_OAUTH_REDIRECT_URI:-}"
    user_type="${GHL_OAUTH_USER_TYPE:-Company}"
    scope="${GHL_OAUTH_SCOPE:-}"
    state=""
    auth_url="${GHL_OAUTH_AUTHORIZE_URL}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --client-id)
          client_id="${2:-}"; shift 2 ;;
        --redirect-uri)
          redirect_uri="${2:-}"; shift 2 ;;
        --user-type)
          user_type="${2:-}"; shift 2 ;;
        --scope)
          scope="${2:-}"; shift 2 ;;
        --state)
          state="${2:-}"; shift 2 ;;
        --auth-url)
          auth_url="${2:-}"; shift 2 ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for oauth-authorize-url: $1" ;;
      esac
    done

    [[ -n "$client_id" ]] || fail "--client-id is required (or set GHL_CLIENT_ID)"
    [[ -n "$redirect_uri" ]] || fail "--redirect-uri is required (or set GHL_OAUTH_REDIRECT_URI)"
    [[ -n "$auth_url" ]] || fail "--auth-url must not be empty"
    user_type="$(normalize_user_type "$user_type")"

    local_join="?"
    if [[ "$auth_url" == *\?* ]]; then
      local_join="&"
    fi

    url="${auth_url}${local_join}response_type=code"
    url="${url}&redirect_uri=$(url_encode "$redirect_uri")"
    url="${url}&client_id=$(url_encode "$client_id")"
    url="${url}&user_type=$(url_encode "$user_type")"
    if [[ -n "$scope" ]]; then
      url="${url}&scope=$(url_encode "$scope")"
    fi
    if [[ -n "$state" ]]; then
      url="${url}&state=$(url_encode "$state")"
    fi
    echo "$url"
    ;;

  oauth-exchange)
    need_bin jq
    dry_run=0
    show_tokens=0
    client_id="${GHL_CLIENT_ID:-}"
    client_secret="${GHL_CLIENT_SECRET:-}"
    code=""
    redirect_uri="${GHL_OAUTH_REDIRECT_URI:-}"
    user_type="${GHL_OAUTH_USER_TYPE:-Company}"
    env_file=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --client-id)
          client_id="${2:-}"; shift 2 ;;
        --client-secret)
          client_secret="${2:-}"; shift 2 ;;
        --code)
          code="${2:-}"; shift 2 ;;
        --redirect-uri)
          redirect_uri="${2:-}"; shift 2 ;;
        --user-type)
          user_type="${2:-}"; shift 2 ;;
        --env-file)
          env_file="${2:-}"; shift 2 ;;
        --show-tokens)
          show_tokens=1; shift ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for oauth-exchange: $1" ;;
      esac
    done

    [[ -n "$client_id" ]] || fail "--client-id is required (or set GHL_CLIENT_ID)"
    [[ -n "$client_secret" ]] || fail "--client-secret is required (or set GHL_CLIENT_SECRET)"
    [[ -n "$code" ]] || fail "--code is required"
    [[ -n "$redirect_uri" ]] || fail "--redirect-uri is required (or set GHL_OAUTH_REDIRECT_URI)"
    user_type="$(normalize_user_type "$user_type")"

    response_json="$(
      oauth_token_call authorization_code "$client_id" "$client_secret" "$user_type" "$code" "$redirect_uri" "" "$dry_run"
    )"

    if [[ "$dry_run" == "1" ]]; then
      echo "$response_json"
      exit 0
    fi

    validate_oauth_response "$response_json"
    persist_oauth_env "$env_file" "$response_json" "$client_id" "$client_secret" "$user_type"
    if [[ "$show_tokens" == "1" ]]; then
      echo "$response_json" | jq .
    else
      print_oauth_summary "$response_json" "authorization_code" "$env_file"
    fi
    ;;

  oauth-refresh)
    need_bin jq
    dry_run=0
    show_tokens=0
    client_id="${GHL_CLIENT_ID:-}"
    client_secret="${GHL_CLIENT_SECRET:-}"
    refresh_token="${GHL_REFRESH_TOKEN:-}"
    user_type="${GHL_OAUTH_USER_TYPE:-Company}"
    env_file=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --client-id)
          client_id="${2:-}"; shift 2 ;;
        --client-secret)
          client_secret="${2:-}"; shift 2 ;;
        --refresh-token)
          refresh_token="${2:-}"; shift 2 ;;
        --user-type)
          user_type="${2:-}"; shift 2 ;;
        --env-file)
          env_file="${2:-}"; shift 2 ;;
        --show-tokens)
          show_tokens=1; shift ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for oauth-refresh: $1" ;;
      esac
    done

    [[ -n "$client_id" ]] || fail "--client-id is required (or set GHL_CLIENT_ID)"
    [[ -n "$client_secret" ]] || fail "--client-secret is required (or set GHL_CLIENT_SECRET)"
    [[ -n "$refresh_token" ]] || fail "--refresh-token is required (or set GHL_REFRESH_TOKEN)"
    user_type="$(normalize_user_type "$user_type")"

    response_json="$(
      oauth_token_call refresh_token "$client_id" "$client_secret" "$user_type" "" "" "$refresh_token" "$dry_run"
    )"

    if [[ "$dry_run" == "1" ]]; then
      echo "$response_json"
      exit 0
    fi

    validate_oauth_response "$response_json"
    persist_oauth_env "$env_file" "$response_json" "$client_id" "$client_secret" "$user_type"
    if [[ "$show_tokens" == "1" ]]; then
      echo "$response_json" | jq .
    else
      print_oauth_summary "$response_json" "refresh_token" "$env_file"
    fi
    ;;

  request)
    dry_run=0
    method=""
    path=""
    query=""
    data=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --method)
          method="${2:-}"; shift 2 ;;
        --path)
          path="${2:-}"; shift 2 ;;
        --query)
          query="${2:-}"; shift 2 ;;
        --data)
          data="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for request: $1" ;;
      esac
    done

    [[ -n "$method" ]] || fail "--method is required"
    [[ -n "$path" ]] || fail "--path is required"
    [[ "$path" == /* ]] || fail "--path must start with '/'"
    method="$(echo "$method" | tr '[:lower:]' '[:upper:]')"

    call_api "$method" "$path" "$query" "$data" "$dry_run" | render_output "$dry_run"
    ;;

  get-location)
    dry_run=0
    location=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for get-location: $1" ;;
      esac
    done
    location="$(resolve_location "$location")"
    call_api GET "/locations/${location}" "" "" "$dry_run" | render_output "$dry_run"
    ;;

  get-contact)
    dry_run=0
    contact_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --id)
          contact_id="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for get-contact: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--id is required"
    call_api GET "/contacts/${contact_id}" "" "" "$dry_run" | render_output "$dry_run"
    ;;

  search-contacts)
    need_bin jq
    dry_run=0
    location=""
    query_text=""
    data=""
    page="1"
    page_limit="20"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --query)
          query_text="${2:-}"; shift 2 ;;
        --data)
          data="${2:-}"; shift 2 ;;
        --page)
          page="${2:-}"; shift 2 ;;
        --page-limit)
          page_limit="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for search-contacts: $1" ;;
      esac
    done

    location="$(resolve_location "$location")"
    [[ "$page" =~ ^[0-9]+$ ]] || fail "--page must be an integer"
    [[ "$page_limit" =~ ^[0-9]+$ ]] || fail "--page-limit must be an integer"

    if [[ -n "$query_text" && -n "$data" ]]; then
      fail "search-contacts accepts either --query or --data, not both"
    fi

    if [[ -n "$data" ]]; then
      payload="$(
        jq -cn \
          --argjson input "$data" \
          --arg locationId "$location" \
          --argjson page "$page" \
          --argjson pageLimit "$page_limit" \
          '$input
          + (if ($input.locationId // "") == "" then {locationId: $locationId} else {} end)
          + (if ($input.page // empty) == empty then {page: $page} else {} end)
          + (if ($input.pageLimit // empty) == empty then {pageLimit: $pageLimit} else {} end)'
      )"
      call_api POST "/contacts/search" "" "$payload" "$dry_run" | render_output "$dry_run"
    else
      [[ -n "$query_text" ]] || fail "search-contacts requires --query or --data"
      payload="$(
        jq -cn \
          --arg locationId "$location" \
          --arg query "$query_text" \
          --argjson page "$page" \
          --argjson pageLimit "$page_limit" \
          '{
            locationId: $locationId,
            page: $page,
            pageLimit: $pageLimit,
            query: $query
          }'
      )"
      call_api POST "/contacts/search" "" "$payload" "$dry_run" | render_output "$dry_run"
    fi
    ;;

  create-contact)
    need_bin jq
    dry_run=0
    location=""
    first_name=""
    last_name=""
    email=""
    phone=""
    tags=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --first-name)
          first_name="${2:-}"; shift 2 ;;
        --last-name)
          last_name="${2:-}"; shift 2 ;;
        --email)
          email="${2:-}"; shift 2 ;;
        --phone)
          phone="${2:-}"; shift 2 ;;
        --tags)
          tags="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for create-contact: $1" ;;
      esac
    done

    location="$(resolve_location "$location")"
    if [[ -z "$email" && -z "$phone" ]]; then
      fail "create-contact requires at least --email or --phone"
    fi

    payload="$(
      jq -cn \
        --arg locationId "$location" \
        --arg firstName "$first_name" \
        --arg lastName "$last_name" \
        --arg email "$email" \
        --arg phone "$phone" \
        --arg tags "$tags" \
        '{
          locationId: $locationId
        }
        + (if $firstName != "" then {firstName: $firstName} else {} end)
        + (if $lastName != "" then {lastName: $lastName} else {} end)
        + (if $email != "" then {email: $email} else {} end)
        + (if $phone != "" then {phone: $phone} else {} end)
        + (
            if $tags != ""
            then {tags: ($tags | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))}
            else {}
            end
          )'
    )"

    call_api POST "/contacts/" "" "$payload" "$dry_run" | render_output "$dry_run"
    ;;

  update-contact)
    need_bin jq
    dry_run=0
    contact_id=""
    first_name=""
    last_name=""
    email=""
    phone=""
    tags=""
    company_name=""
    country=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --id)
          contact_id="${2:-}"; shift 2 ;;
        --first-name)
          first_name="${2:-}"; shift 2 ;;
        --last-name)
          last_name="${2:-}"; shift 2 ;;
        --email)
          email="${2:-}"; shift 2 ;;
        --phone)
          phone="${2:-}"; shift 2 ;;
        --tags)
          tags="${2:-}"; shift 2 ;;
        --company-name)
          company_name="${2:-}"; shift 2 ;;
        --country)
          country="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for update-contact: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--id is required"
    if [[ -z "$first_name" && -z "$last_name" && -z "$email" && -z "$phone" && -z "$tags" && -z "$company_name" && -z "$country" ]]; then
      fail "update-contact requires at least one field to change"
    fi

    payload="$(
      jq -cn \
        --arg firstName "$first_name" \
        --arg lastName "$last_name" \
        --arg email "$email" \
        --arg phone "$phone" \
        --arg tags "$tags" \
        --arg companyName "$company_name" \
        --arg country "$country" \
        '(if $firstName != "" then {firstName: $firstName} else {} end)
        + (if $lastName != "" then {lastName: $lastName} else {} end)
        + (if $email != "" then {email: $email} else {} end)
        + (if $phone != "" then {phone: $phone} else {} end)
        + (if $companyName != "" then {companyName: $companyName} else {} end)
        + (if $country != "" then {country: $country} else {} end)
        + (
            if $tags != ""
            then {tags: ($tags | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))}
            else {}
            end
          )'
    )"

    call_api PUT "/contacts/${contact_id}" "" "$payload" "$dry_run" | render_output "$dry_run"
    ;;

  upsert-contact)
    need_bin jq
    dry_run=0
    location=""
    first_name=""
    last_name=""
    email=""
    phone=""
    tags=""
    company_name=""
    country=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --first-name)
          first_name="${2:-}"; shift 2 ;;
        --last-name)
          last_name="${2:-}"; shift 2 ;;
        --email)
          email="${2:-}"; shift 2 ;;
        --phone)
          phone="${2:-}"; shift 2 ;;
        --tags)
          tags="${2:-}"; shift 2 ;;
        --company-name)
          company_name="${2:-}"; shift 2 ;;
        --country)
          country="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for upsert-contact: $1" ;;
      esac
    done

    location="$(resolve_location "$location")"
    if [[ -z "$email" && -z "$phone" ]]; then
      fail "upsert-contact requires at least --email or --phone"
    fi

    payload="$(
      jq -cn \
        --arg locationId "$location" \
        --arg firstName "$first_name" \
        --arg lastName "$last_name" \
        --arg email "$email" \
        --arg phone "$phone" \
        --arg tags "$tags" \
        --arg companyName "$company_name" \
        --arg country "$country" \
        '{
          locationId: $locationId
        }
        + (if $firstName != "" then {firstName: $firstName} else {} end)
        + (if $lastName != "" then {lastName: $lastName} else {} end)
        + (if $email != "" then {email: $email} else {} end)
        + (if $phone != "" then {phone: $phone} else {} end)
        + (if $companyName != "" then {companyName: $companyName} else {} end)
        + (if $country != "" then {country: $country} else {} end)
        + (
            if $tags != ""
            then {tags: ($tags | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))}
            else {}
            end
          )'
    )"

    call_api POST "/contacts/upsert" "" "$payload" "$dry_run" | render_output "$dry_run"
    ;;

  list-contact-notes)
    dry_run=0
    contact_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for list-contact-notes: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    call_api GET "/contacts/${contact_id}/notes" "" "" "$dry_run" | render_output "$dry_run"
    ;;

  get-contact-note)
    dry_run=0
    contact_id=""
    note_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --note-id)
          note_id="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for get-contact-note: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    [[ -n "$note_id" ]] || fail "--note-id is required"
    call_api GET "/contacts/${contact_id}/notes/${note_id}" "" "" "$dry_run" | render_output "$dry_run"
    ;;

  create-contact-note)
    need_bin jq
    dry_run=0
    contact_id=""
    body=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --body)
          body="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for create-contact-note: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    [[ -n "$body" ]] || fail "--body is required"

    payload="$(jq -cn --arg body "$body" '{body: $body}')"
    call_api POST "/contacts/${contact_id}/notes" "" "$payload" "$dry_run" | render_output "$dry_run"
    ;;

  update-contact-note)
    need_bin jq
    dry_run=0
    contact_id=""
    note_id=""
    body=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --note-id)
          note_id="${2:-}"; shift 2 ;;
        --body)
          body="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for update-contact-note: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    [[ -n "$note_id" ]] || fail "--note-id is required"
    [[ -n "$body" ]] || fail "--body is required"

    payload="$(jq -cn --arg body "$body" '{body: $body}')"
    call_api PUT "/contacts/${contact_id}/notes/${note_id}" "" "$payload" "$dry_run" | render_output "$dry_run"
    ;;

  delete-contact-note)
    dry_run=0
    contact_id=""
    note_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --note-id)
          note_id="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for delete-contact-note: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    [[ -n "$note_id" ]] || fail "--note-id is required"
    call_api DELETE "/contacts/${contact_id}/notes/${note_id}" "" "" "$dry_run" | render_output "$dry_run"
    ;;

  list-contact-tasks)
    dry_run=0
    contact_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for list-contact-tasks: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    call_api GET "/contacts/${contact_id}/tasks" "" "" "$dry_run" | render_output "$dry_run"
    ;;

  get-contact-task)
    dry_run=0
    contact_id=""
    task_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --task-id)
          task_id="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for get-contact-task: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    [[ -n "$task_id" ]] || fail "--task-id is required"
    call_api GET "/contacts/${contact_id}/tasks/${task_id}" "" "" "$dry_run" | render_output "$dry_run"
    ;;

  create-contact-task)
    need_bin jq
    dry_run=0
    contact_id=""
    title=""
    due_date=""
    assigned_to=""
    completed=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --title)
          title="${2:-}"; shift 2 ;;
        --due-date)
          due_date="${2:-}"; shift 2 ;;
        --assigned-to)
          assigned_to="${2:-}"; shift 2 ;;
        --completed)
          completed="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for create-contact-task: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    [[ -n "$title" ]] || fail "--title is required"
    if [[ -n "$completed" ]]; then
      completed="$(normalize_bool "$completed")"
    fi

    payload="$(
      jq -cn \
        --arg title "$title" \
        --arg dueDate "$due_date" \
        --arg assignedTo "$assigned_to" \
        --arg completed "$completed" \
        '{title: $title}
        + (if $dueDate != "" then {dueDate: $dueDate} else {} end)
        + (if $assignedTo != "" then {assignedTo: $assignedTo} else {} end)
        + (if $completed != "" then {completed: ($completed == "true")} else {} end)'
    )"

    call_api POST "/contacts/${contact_id}/tasks" "" "$payload" "$dry_run" | render_output "$dry_run"
    ;;

  update-contact-task)
    need_bin jq
    dry_run=0
    contact_id=""
    task_id=""
    title=""
    due_date=""
    assigned_to=""
    completed=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --task-id)
          task_id="${2:-}"; shift 2 ;;
        --title)
          title="${2:-}"; shift 2 ;;
        --due-date)
          due_date="${2:-}"; shift 2 ;;
        --assigned-to)
          assigned_to="${2:-}"; shift 2 ;;
        --completed)
          completed="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for update-contact-task: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    [[ -n "$task_id" ]] || fail "--task-id is required"
    if [[ -n "$completed" ]]; then
      completed="$(normalize_bool "$completed")"
    fi
    if [[ -z "$title" && -z "$due_date" && -z "$assigned_to" && -z "$completed" ]]; then
      fail "update-contact-task requires at least one field to change"
    fi

    payload="$(
      jq -cn \
        --arg title "$title" \
        --arg dueDate "$due_date" \
        --arg assignedTo "$assigned_to" \
        --arg completed "$completed" \
        '(if $title != "" then {title: $title} else {} end)
        + (if $dueDate != "" then {dueDate: $dueDate} else {} end)
        + (if $assignedTo != "" then {assignedTo: $assignedTo} else {} end)
        + (if $completed != "" then {completed: ($completed == "true")} else {} end)'
    )"

    call_api PUT "/contacts/${contact_id}/tasks/${task_id}" "" "$payload" "$dry_run" | render_output "$dry_run"
    ;;

  complete-contact-task)
    need_bin jq
    dry_run=0
    contact_id=""
    task_id=""
    completed=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --task-id)
          task_id="${2:-}"; shift 2 ;;
        --completed)
          completed="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for complete-contact-task: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    [[ -n "$task_id" ]] || fail "--task-id is required"
    [[ -n "$completed" ]] || fail "--completed is required"
    completed="$(normalize_bool "$completed")"

    payload="$(jq -cn --arg completed "$completed" '{completed: ($completed == "true")}')"
    call_api PUT "/contacts/${contact_id}/tasks/${task_id}/completed" "" "$payload" "$dry_run" | render_output "$dry_run"
    ;;

  delete-contact-task)
    dry_run=0
    contact_id=""
    task_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --task-id)
          task_id="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for delete-contact-task: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    [[ -n "$task_id" ]] || fail "--task-id is required"
    call_api DELETE "/contacts/${contact_id}/tasks/${task_id}" "" "" "$dry_run" | render_output "$dry_run"
    ;;

  add-contact-to-workflow)
    dry_run=0
    contact_id=""
    workflow_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --workflow-id)
          workflow_id="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for add-contact-to-workflow: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    [[ -n "$workflow_id" ]] || fail "--workflow-id is required"
    call_api POST "/contacts/${contact_id}/workflow/${workflow_id}" "" "" "$dry_run" | render_output "$dry_run"
    ;;

  remove-contact-from-workflow)
    dry_run=0
    contact_id=""
    workflow_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --workflow-id)
          workflow_id="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for remove-contact-from-workflow: $1" ;;
      esac
    done

    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    [[ -n "$workflow_id" ]] || fail "--workflow-id is required"
    call_api DELETE "/contacts/${contact_id}/workflow/${workflow_id}" "" "" "$dry_run" | render_output "$dry_run"
    ;;

  list-forms)
    dry_run=0
    location=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for list-forms: $1" ;;
      esac
    done

    location="$(resolve_location "$location")"
    call_api GET "/forms/" "locationId=${location}" "" "$dry_run" | render_output "$dry_run"
    ;;

  list-surveys)
    dry_run=0
    location=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for list-surveys: $1" ;;
      esac
    done

    location="$(resolve_location "$location")"
    call_api GET "/surveys/" "locationId=${location}" "" "$dry_run" | render_output "$dry_run"
    ;;

  list-custom-fields)
    dry_run=0
    location=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for list-custom-fields: $1" ;;
      esac
    done

    location="$(resolve_location "$location")"
    call_api GET "/locations/${location}/customFields" "" "" "$dry_run" | render_output "$dry_run"
    ;;

  list-pipelines)
    dry_run=0
    location=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for list-pipelines: $1" ;;
      esac
    done

    location="$(resolve_location "$location")"
    call_api GET "/opportunities/pipelines" "locationId=${location}" "" "$dry_run" | render_output "$dry_run"
    ;;

  list-calendars)
    dry_run=0
    location=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for list-calendars: $1" ;;
      esac
    done

    location="$(resolve_location "$location")"
    call_api GET "/calendars/" "locationId=${location}" "" "$dry_run" | render_output "$dry_run"
    ;;

  list-users)
    dry_run=0
    location=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for list-users: $1" ;;
      esac
    done

    location="$(resolve_location "$location")"
    call_api GET "/users/" "locationId=${location}" "" "$dry_run" | render_output "$dry_run"
    ;;

  get-calendar-slots)
    dry_run=0
    calendar_id=""
    start_raw=""
    end_raw=""
    timezone="${TZ:-UTC}"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --calendar-id)
          calendar_id="${2:-}"; shift 2 ;;
        --start)
          start_raw="${2:-}"; shift 2 ;;
        --end)
          end_raw="${2:-}"; shift 2 ;;
        --timezone)
          timezone="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for get-calendar-slots: $1" ;;
      esac
    done

    [[ -n "$calendar_id" ]] || fail "--calendar-id is required"
    [[ -n "$start_raw" ]] || fail "--start is required"
    [[ -n "$end_raw" ]] || fail "--end is required"

    start_ms="$(datetime_to_epoch_ms "$start_raw" "$timezone")"
    end_ms="$(datetime_to_epoch_ms "$end_raw" "$timezone")"
    call_api GET "/calendars/${calendar_id}/free-slots" "startDate=${start_ms}&endDate=${end_ms}&timezone=$(url_encode "$timezone")" "" "$dry_run" | render_output "$dry_run"
    ;;

  search-conversations)
    dry_run=0
    location=""
    query_text=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --query)
          query_text="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for search-conversations: $1" ;;
      esac
    done

    location="$(resolve_location "$location")"
    [[ -n "$query_text" ]] || fail "--query is required"
    encoded_query="$(url_encode "$query_text")"
    call_api GET "/conversations/search" "locationId=${location}&query=${encoded_query}" "" "$dry_run" | render_output "$dry_run"
    ;;

  list-conversation-messages)
    dry_run=0
    conversation_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --conversation-id)
          conversation_id="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for list-conversation-messages: $1" ;;
      esac
    done

    [[ -n "$conversation_id" ]] || fail "--conversation-id is required"
    call_api GET "/conversations/${conversation_id}/messages" "" "" "$dry_run" | render_output "$dry_run"
    ;;

  upload-conversation-attachments)
    dry_run=0
    contact_id=""
    conversation_id=""
    files=()
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --conversation-id)
          conversation_id="${2:-}"; shift 2 ;;
        --file)
          files+=("${2:-}"); shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for upload-conversation-attachments: $1" ;;
      esac
    done

    if [[ -z "$contact_id" && -z "$conversation_id" ]]; then
      fail "upload-conversation-attachments requires --contact-id or --conversation-id"
    fi
    if [[ -n "$contact_id" && -n "$conversation_id" ]]; then
      fail "upload-conversation-attachments accepts either --contact-id or --conversation-id, not both"
    fi
    ((${#files[@]} > 0)) || fail "upload-conversation-attachments requires at least one --file"
    ((${#files[@]} <= 5)) || fail "upload-conversation-attachments supports at most 5 files per request"

    form_fields=()
    if [[ -n "$contact_id" ]]; then
      form_fields+=("contactId=${contact_id}")
    fi
    if [[ -n "$conversation_id" ]]; then
      form_fields+=("conversationId=${conversation_id}")
    fi

    for file_path in "${files[@]}"; do
      [[ -f "$file_path" ]] || fail "file does not exist: $file_path"
      form_fields+=("attachments=@${file_path}")
    done

    if [[ "$dry_run" == "1" ]]; then
      call_multipart_api "/conversations/messages/upload" --dry-run-sentinel "${form_fields[@]}"
    else
      call_multipart_api "/conversations/messages/upload" "${form_fields[@]}" | render_output 0
    fi
    ;;

  send-message)
    need_bin jq
    dry_run=0
    message_type=""
    contact_id=""
    conversation_id=""
    message=""
    subject=""
    html=""
    email_from=""
    attachments=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --type)
          message_type="${2:-}"; shift 2 ;;
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --conversation-id)
          conversation_id="${2:-}"; shift 2 ;;
        --message)
          message="${2:-}"; shift 2 ;;
        --subject)
          subject="${2:-}"; shift 2 ;;
        --html)
          html="${2:-}"; shift 2 ;;
        --email-from)
          email_from="${2:-}"; shift 2 ;;
        --attachments)
          attachments="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for send-message: $1" ;;
      esac
    done

    [[ -n "$message_type" ]] || fail "--type is required"
    [[ -n "$message" ]] || fail "--message is required"
    if [[ -z "$contact_id" && -z "$conversation_id" ]]; then
      fail "send-message requires --contact-id or --conversation-id"
    fi
    if [[ -n "$contact_id" && -n "$conversation_id" ]]; then
      fail "send-message accepts either --contact-id or --conversation-id, not both"
    fi

    payload="$(
      jq -cn \
        --arg type "$message_type" \
        --arg contactId "$contact_id" \
        --arg conversationId "$conversation_id" \
        --arg message "$message" \
        --arg subject "$subject" \
        --arg html "$html" \
        --arg emailFrom "$email_from" \
        --arg attachments "$attachments" \
        '{
          type: $type,
          message: $message
        }
        + (if $contactId != "" then {contactId: $contactId} else {} end)
        + (if $conversationId != "" then {conversationId: $conversationId} else {} end)
        + (if $subject != "" then {subject: $subject} else {} end)
        + (if $html != "" then {html: $html} else {} end)
        + (if $emailFrom != "" then {emailFrom: $emailFrom} else {} end)
        + (if $attachments != "" then {attachments: ($attachments | fromjson)} else {} end)'
    )"

    call_api POST "/conversations/messages" "" "$payload" "$dry_run" | render_output "$dry_run"
    ;;

  create-opportunity)
    need_bin jq
    dry_run=0
    location=""
    contact_id=""
    pipeline_id=""
    stage_id=""
    name=""
    status="open"
    monetary_value=""
    assigned_to=""
    source=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --pipeline-id)
          pipeline_id="${2:-}"; shift 2 ;;
        --stage-id)
          stage_id="${2:-}"; shift 2 ;;
        --name)
          name="${2:-}"; shift 2 ;;
        --status)
          status="${2:-}"; shift 2 ;;
        --value)
          monetary_value="${2:-}"; shift 2 ;;
        --assigned-to)
          assigned_to="${2:-}"; shift 2 ;;
        --source)
          source="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for create-opportunity: $1" ;;
      esac
    done

    location="$(resolve_location "$location")"
    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    [[ -n "$pipeline_id" ]] || fail "--pipeline-id is required"
    [[ -n "$stage_id" ]] || fail "--stage-id is required"
    [[ -n "$name" ]] || fail "--name is required"

    case "$status" in
      open|won|lost|abandoned)
        ;;
      *)
        fail "--status must be one of: open|won|lost|abandoned"
        ;;
    esac

    if [[ -n "$monetary_value" && ! "$monetary_value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
      fail "--value must be numeric"
    fi

    payload="$(
      jq -cn \
        --arg locationId "$location" \
        --arg contactId "$contact_id" \
        --arg pipelineId "$pipeline_id" \
        --arg pipelineStageId "$stage_id" \
        --arg name "$name" \
        --arg status "$status" \
        --arg assignedTo "$assigned_to" \
        --arg source "$source" \
        --arg monetaryValue "$monetary_value" \
        '{
          locationId: $locationId,
          contactId: $contactId,
          pipelineId: $pipelineId,
          pipelineStageId: $pipelineStageId,
          name: $name,
          status: $status
        }
        + (if $assignedTo != "" then {assignedTo: $assignedTo} else {} end)
        + (if $source != "" then {source: $source} else {} end)
        + (if $monetaryValue != "" then {monetaryValue: ($monetaryValue | tonumber)} else {} end)'
    )"

    call_api POST "/opportunities/" "" "$payload" "$dry_run" | render_output "$dry_run"
    ;;

  upsert-opportunity)
    need_bin jq
    dry_run=0
    location=""
    opportunity_id=""
    contact_id=""
    pipeline_id=""
    stage_id=""
    name=""
    status="open"
    monetary_value=""
    assigned_to=""
    source=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --id)
          opportunity_id="${2:-}"; shift 2 ;;
        --contact-id)
          contact_id="${2:-}"; shift 2 ;;
        --pipeline-id)
          pipeline_id="${2:-}"; shift 2 ;;
        --stage-id)
          stage_id="${2:-}"; shift 2 ;;
        --name)
          name="${2:-}"; shift 2 ;;
        --status)
          status="${2:-}"; shift 2 ;;
        --value)
          monetary_value="${2:-}"; shift 2 ;;
        --assigned-to)
          assigned_to="${2:-}"; shift 2 ;;
        --source)
          source="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for upsert-opportunity: $1" ;;
      esac
    done

    location="$(resolve_location "$location")"
    [[ -n "$contact_id" ]] || fail "--contact-id is required"
    [[ -n "$pipeline_id" ]] || fail "--pipeline-id is required"
    [[ -n "$stage_id" ]] || fail "--stage-id is required"
    [[ -n "$name" ]] || fail "--name is required"

    case "$status" in
      open|won|lost|abandoned)
        ;;
      *)
        fail "--status must be one of: open|won|lost|abandoned"
        ;;
    esac

    if [[ -n "$monetary_value" && ! "$monetary_value" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
      fail "--value must be numeric"
    fi

    payload="$(
      jq -cn \
        --arg locationId "$location" \
        --arg id "$opportunity_id" \
        --arg contactId "$contact_id" \
        --arg pipelineId "$pipeline_id" \
        --arg pipelineStageId "$stage_id" \
        --arg name "$name" \
        --arg status "$status" \
        --arg assignedTo "$assigned_to" \
        --arg source "$source" \
        --arg monetaryValue "$monetary_value" \
        '{
          locationId: $locationId,
          contactId: $contactId,
          pipelineId: $pipelineId,
          pipelineStageId: $pipelineStageId,
          name: $name,
          status: $status
        }
        + (if $id != "" then {id: $id} else {} end)
        + (if $assignedTo != "" then {assignedTo: $assignedTo} else {} end)
        + (if $source != "" then {source: $source} else {} end)
        + (if $monetaryValue != "" then {monetaryValue: ($monetaryValue | tonumber)} else {} end)'
    )"

    call_api POST "/opportunities/upsert" "" "$payload" "$dry_run" | render_output "$dry_run"
    ;;

  list-workflows)
    dry_run=0
    location=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for list-workflows: $1" ;;
      esac
    done

    location="$(resolve_location "$location")"
    call_api GET "/workflows/" "locationId=${location}" "" "$dry_run" | render_output "$dry_run"
    ;;

  list-opportunities)
    dry_run=0
    location=""
    limit="20"
    pipeline_id=""
    status="all"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --location)
          location="${2:-}"; shift 2 ;;
        --limit)
          limit="${2:-}"; shift 2 ;;
        --pipeline-id)
          pipeline_id="${2:-}"; shift 2 ;;
        --status)
          status="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for list-opportunities: $1" ;;
      esac
    done

    location="$(resolve_location "$location")"
    [[ "$limit" =~ ^[0-9]+$ ]] || fail "--limit must be an integer"

    case "$status" in
      open|won|lost|abandoned|all)
        ;;
      *)
        fail "--status must be one of: open|won|lost|abandoned|all"
        ;;
    esac

    query="location_id=${location}&limit=${limit}"
    if [[ -n "$pipeline_id" ]]; then
      query="${query}&pipeline_id=${pipeline_id}"
    fi
    if [[ "$status" != "all" ]]; then
      query="${query}&status=${status}"
    fi

    call_api GET "/opportunities/search" "$query" "" "$dry_run" | render_output "$dry_run"
    ;;

  get-opportunity)
    dry_run=0
    opportunity_id=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --id)
          opportunity_id="${2:-}"; shift 2 ;;
        --dry-run)
          dry_run=1; shift ;;
        -h|--help)
          usage; exit 0 ;;
        *)
          fail "unknown flag for get-opportunity: $1" ;;
      esac
    done

    [[ -n "$opportunity_id" ]] || fail "--id is required"
    call_api GET "/opportunities/${opportunity_id}" "" "" "$dry_run" | render_output "$dry_run"
    ;;

  *)
    fail "unknown command: $cmd"
    ;;
esac
