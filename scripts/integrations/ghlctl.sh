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
  ghlctl.sh create-contact --location <id> [--first-name <v>] [--last-name <v>] [--email <v>] [--phone <v>] [--tags a,b] [--dry-run]
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
  local token=""
  if token="$(resolve_api_token 2>/dev/null)"; then
    printf '%s' "$token"
  else
    printf '%s' '${GHL_API_TOKEN}'
  fi
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

url_encode() {
  need_bin jq
  local value="$1"
  jq -nr --arg value "$value" '$value|@uri'
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
