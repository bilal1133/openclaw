#!/usr/bin/env bash
set -euo pipefail

ROOT="${OPENCLAW_ROOT:-/Users/bilal/.openclaw}"
KNOWLEDGE_ROOT="$ROOT/knowledge"
LOCK_FILE="$KNOWLEDGE_ROOT/.memory.lock"

usage() {
  cat <<USAGE
Usage:
  memoryctl.sh import --input <abs_path> --brand tkturners --scope shared|private
  memoryctl.sh read --brand tkturners --query "<text>" --scope shared|private|both
  memoryctl.sh append --brand tkturners --type fact|todo|decision --text "<text>" --source "<abs_path>" --scope shared|private --agent "<id>"
  memoryctl.sh compact --brand tkturners
USAGE
}

err() {
  echo "error: $*" >&2
  exit 1
}

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

sanitize_filename() {
  local name="$1"
  name="${name// /_}"
  name="${name//\//_}"
  name="${name//:/_}"
  name="${name//[^A-Za-z0-9._-]/_}"
  printf '%s' "$name"
}

normalize_text() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | tr -s '[:space:]' ' ' \
    | sed -e 's/^ //' -e 's/ $//'
}

hash_text() {
  local normalized
  normalized="$(normalize_text "$1")"
  printf '%s' "$normalized" | shasum -a 256 | awk '{print $1}'
}

brand_root() {
  printf '%s/%s' "$KNOWLEDGE_ROOT" "$1"
}

source_dir() {
  printf '%s/source' "$(brand_root "$1")"
}

shared_file() {
  printf '%s/TKTURNERS_SHARED_MEMORY.md' "$(brand_root "$1")"
}

private_file() {
  printf '%s/TKTURNERS_PRIVATE_ANNEX.md' "$(brand_root "$1")"
}

changelog_file() {
  printf '%s/changelog.jsonl' "$(brand_root "$1")"
}

readme_file() {
  printf '%s/README.md' "$(brand_root "$1")"
}

ensure_brand_layout() {
  local brand="$1"
  local broot
  local sdir
  local sfile
  local pfile
  local cfile
  local rfile

  broot="$(brand_root "$brand")"
  sdir="$(source_dir "$brand")"
  sfile="$(shared_file "$brand")"
  pfile="$(private_file "$brand")"
  cfile="$(changelog_file "$brand")"
  rfile="$(readme_file "$brand")"

  mkdir -p "$sdir"
  touch "$cfile"

  if [[ ! -f "$sfile" ]]; then
    cat > "$sfile" <<'SHARED'
# TkTurners Shared Memory

## Canonical Facts

## Open Decisions

## Operational TODOs

## Brand Direction

## Auto Updates

## Change Log
SHARED
  fi

  if [[ ! -f "$pfile" ]]; then
    cat > "$pfile" <<'PRIVATE'
# TkTurners Private Annex

## Legal Identifiers

## Ownership and Compliance

## Restricted Notes

## Change Log
PRIVATE
  fi

  if [[ ! -f "$rfile" ]]; then
    cat > "$rfile" <<'README'
# TkTurners Knowledge Vault

- Shared memory: `TKTURNERS_SHARED_MEMORY.md`
- Private annex: `TKTURNERS_PRIVATE_ANNEX.md`
- Normalized source copies: `source/`
- Audit log: `changelog.jsonl`

Rules:
- All agents may read shared memory.
- Sensitive identifiers must stay in private annex.
- Use `memoryctl.sh` for writes.
README
  fi
}

is_sensitive_text() {
  local text="$1"
  local lc
  lc="$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')"
  # Use token boundaries for short identifiers to avoid false positives
  # (for example, "file-first" should not match "irs").
  if grep -Eq '((^|[^a-z0-9])(ein|fincen|boir|irs|ntn|strn|organizer)([^a-z0-9]|$)|beneficial ownership|ownership split|ownership %|wyoming secretary|certificate of organization|registered agent|tax registration|w-8ben-e|37-2182659|2025-001676916|2000-0731-2978|legal id)' <<<"$lc"; then
    return 0
  fi
  return 1
}

append_changelog() {
  local brand="$1"
  local action="$2"
  local scope="$3"
  local source="$4"
  local details="$5"
  local agent="$6"
  local line
  line="$(jq -nc \
    --arg ts "$(now_iso)" \
    --arg action "$action" \
    --arg brand "$brand" \
    --arg scope "$scope" \
    --arg source "$source" \
    --arg details "$details" \
    --arg agent "$agent" \
    '{ts:$ts,action:$action,brand:$brand,scope:$scope,source:$source,details:$details,agent:$agent}')"
  printf '%s\n' "$line" >> "$(changelog_file "$brand")"
}

append_entry_to_file() {
  local file="$1"
  local brand="$2"
  local type="$3"
  local text="$4"
  local source="$5"
  local scope="$6"
  local agent="$7"

  [[ -n "$text" ]] || return 2
  [[ "$source" == /* ]] || err "source must be absolute: $source"
  [[ -f "$source" ]] || err "source file does not exist: $source"

  local normalized
  local hash
  local ts
  local entry_id

  normalized="$(normalize_text "$text")"
  [[ ${#normalized} -ge 24 ]] || return 2

  hash="$(hash_text "$normalized")"
  if rg -q "\\[hash:${hash}\\]" "$file"; then
    return 3
  fi

  ts="$(now_iso)"
  entry_id="tkm-${hash:0:12}"

  printf -- '- [id:%s] [ts:%s] [type:%s] [source:%s] [agent:%s] [hash:%s] %s\n' \
    "$entry_id" "$ts" "$type" "$source" "$agent" "$hash" "$text" >> "$file"

  append_changelog "$brand" "append" "$scope" "$source" "id=$entry_id type=$type" "$agent"
  return 0
}

paragraph_stream() {
  local file="$1"
  awk '
    BEGIN { RS=""; ORS="\n" }
    {
      gsub(/\r/, " ")
      gsub(/\n+/, " ")
      gsub(/[[:space:]]+/, " ")
      sub(/^[[:space:]]+/, "")
      sub(/[[:space:]]+$/, "")
      if (length($0) >= 40) print $0
    }
  ' "$file"
}

copy_and_normalize_source() {
  local brand="$1"
  local input_file="$2"
  local sdir
  local base
  local stem
  local ext
  local safe_base
  local out_file
  local tmp_txt

  sdir="$(source_dir "$brand")"
  base="$(basename "$input_file")"
  stem="$(basename "${input_file%.*}")"
  ext="${input_file##*.}"
  ext="$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')"

  safe_base="$(sanitize_filename "$base")"

  if [[ "$ext" == "md" ]]; then
    out_file="$sdir/$safe_base"
    cp "$input_file" "$out_file"
    printf '%s' "$out_file"
    return 0
  fi

  if [[ "$ext" == "docx" ]]; then
    out_file="$sdir/$(sanitize_filename "$stem").docx.md"
    tmp_txt="$(mktemp)"
    textutil -convert txt -stdout "$input_file" > "$tmp_txt"
    {
      printf '# Imported DOCX Source\n\n'
      printf -- '- Original: `%s`\n\n' "$input_file"
      cat "$tmp_txt"
      printf '\n'
    } > "$out_file"
    rm -f "$tmp_txt"
    printf '%s' "$out_file"
    return 0
  fi

  err "unsupported import format: $input_file"
}

collect_import_files() {
  local input_path="$1"

  if [[ -f "$input_path" ]]; then
    printf '%s\n' "$input_path"
    return 0
  fi

  [[ -d "$input_path" ]] || err "input path not found: $input_path"
  find "$input_path" -type f \( -iname '*.md' -o -iname '*.docx' \) -print \
    | awk '
      function tolower_safe(s) { return tolower(s) }
      {
        n = split($0, p, "/")
        base = p[n]
        if (substr(base, 1, 2) == "~$") next
        ext = ""
        stem = base
        dot = match(base, /\.[^.]+$/)
        if (dot > 0) {
          ext = tolower_safe(substr(base, dot + 1))
          stem = tolower_safe(substr(base, 1, dot - 1))
        } else {
          stem = tolower_safe(base)
        }
        files[++count] = $0
        exts[count] = ext
        stems[count] = stem
        if (ext == "md") {
          has_md[stem] = 1
        }
      }
      END {
        for (i = 1; i <= count; i++) {
          if (exts[i] == "docx" && has_md[stems[i]] == 1) continue
          print files[i]
        }
      }
    '
}

cmd_import() {
  local input_path=""
  local brand="tkturners"
  local scope="shared"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --input)
        input_path="${2:-}"
        shift 2
        ;;
      --brand)
        brand="${2:-}"
        shift 2
        ;;
      --scope)
        scope="${2:-}"
        shift 2
        ;;
      *)
        err "unknown import option: $1"
        ;;
    esac
  done

  [[ -n "$input_path" ]] || err "--input is required"
  [[ "$scope" == "shared" || "$scope" == "private" ]] || err "--scope must be shared or private"
  [[ "$input_path" == /* ]] || err "--input must be an absolute path"

  ensure_brand_layout "$brand"

  local -a files=()
  local f
  local normalized_source
  local paragraph
  local target_scope
  local target_file
  local rc

  local appended=0
  local deduped=0
  local skipped=0

  while IFS= read -r f; do
    [[ -n "$f" ]] && files+=("$f")
  done < <(collect_import_files "$input_path")
  [[ ${#files[@]} -gt 0 ]] || err "no importable files found"

  for f in "${files[@]}"; do
    normalized_source="$(copy_and_normalize_source "$brand" "$f")"

    while IFS= read -r paragraph; do
      [[ -n "$paragraph" ]] || continue

      target_scope="$scope"
      if [[ "$scope" != "private" ]] && is_sensitive_text "$paragraph"; then
        target_scope="private"
      fi

      if [[ "$target_scope" == "private" ]]; then
        target_file="$(private_file "$brand")"
      else
        target_file="$(shared_file "$brand")"
      fi

      if append_entry_to_file "$target_file" "$brand" "fact" "$paragraph" "$normalized_source" "$target_scope" "memoryctl-import"; then
        appended=$((appended + 1))
      else
        rc=$?
        case "$rc" in
          2)
            skipped=$((skipped + 1))
            ;;
          3)
            deduped=$((deduped + 1))
            ;;
          *)
            skipped=$((skipped + 1))
            ;;
        esac
      fi
    done < <(paragraph_stream "$normalized_source")
  done

  append_changelog "$brand" "import" "$scope" "$input_path" "appended=$appended deduped=$deduped skipped=$skipped files=${#files[@]}" "memoryctl-import"
  echo "import complete: appended=$appended deduped=$deduped skipped=$skipped files=${#files[@]}"
}

cmd_read() {
  local brand="tkturners"
  local query=""
  local scope="both"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --brand)
        brand="${2:-}"
        shift 2
        ;;
      --query)
        query="${2:-}"
        shift 2
        ;;
      --scope)
        scope="${2:-}"
        shift 2
        ;;
      *)
        err "unknown read option: $1"
        ;;
    esac
  done

  [[ "$scope" == "shared" || "$scope" == "private" || "$scope" == "both" ]] || err "--scope must be shared, private, or both"
  ensure_brand_layout "$brand"

  local -a targets=()
  case "$scope" in
    shared)
      targets+=("$(shared_file "$brand")")
      ;;
    private)
      targets+=("$(private_file "$brand")")
      ;;
    both)
      targets+=("$(shared_file "$brand")" "$(private_file "$brand")")
      ;;
  esac

  memory_entry_count() {
    local file="$1"
    rg -c '^- \[id:' "$file" 2>/dev/null || echo 0
  }

  emit_memory_summary() {
    local file="$1"
    local count
    count="$(memory_entry_count "$file")"
    echo "===== $file"
    echo "record_count=$count"
    echo "sections:"
    if ! rg '^## ' "$file" | sed 's/^## /- /'; then
      echo "- (none)"
    fi
    echo
  }

  keyword_fallback_search() {
    local file="$1"
    shift || true
    local joined
    joined="$(printf '%s\n' "$@" | paste -sd '|' -)"
    awk -v terms="$joined" '
      BEGIN {
        n = split(terms, t, "|")
        threshold = (n >= 2 ? 2 : 1)
      }
      {
        line = tolower($0)
        matched = 0
        for (i = 1; i <= n; i++) {
          if (t[i] != "" && index(line, t[i]) > 0) matched++
        }
        if (matched >= threshold) {
          printf "%d:%s\n", NR, $0
          found = 1
        }
      }
      END { exit(found ? 0 : 1) }
    ' "$file"
  }

  if [[ -z "$query" ]]; then
    for target in "${targets[@]}"; do
      echo "===== $target"
      cat "$target"
      echo
    done
    return 0
  fi

  # Exact literal query first (avoids regex surprises from special chars).
  if rg -n -i -F -- "$query" "${targets[@]}"; then
    return 0
  fi

  # Keyword fallback to improve recall when exact phrase is not present.
  local -a terms=()
  while IFS= read -r t; do
    [[ -n "$t" ]] && terms+=("$t")
  done < <(
    printf '%s' "$query" \
      | tr -cs '[:alnum:]' '\n' \
      | tr '[:upper:]' '[:lower:]' \
      | awk '
          length($0) < 4 { next }
          $0 ~ /^(and|the|for|with|from|into|than|then|this|that|these|those|are|was|were|have|has|had|not|none|found|missing|query|search|record|records|memory|about|info|details|present)$/ { next }
          !seen[$0]++ { print }
        ' \
      | head -n 6
  )

  if [[ ${#terms[@]} -gt 0 ]]; then
    local fallback_found=0
    local target
    local tmp_out
    for target in "${targets[@]}"; do
      tmp_out="$(mktemp)"
      if keyword_fallback_search "$target" "${terms[@]}" > "$tmp_out"; then
        while IFS= read -r line; do
          printf '%s:%s\n' "$target" "$line"
        done < "$tmp_out"
        fallback_found=1
      fi
      rm -f "$tmp_out"
    done
    if [[ "$fallback_found" -eq 1 ]]; then
      echo "note: exact phrase not found; returned keyword-fallback matches." >&2
      return 0
    fi
  fi

  echo "No matches for query: $query"
  echo "memory summary:"
  for target in "${targets[@]}"; do
    emit_memory_summary "$target"
  done
  return 0
}

cmd_append() {
  local brand="tkturners"
  local type="fact"
  local text=""
  local source=""
  local scope="shared"
  local agent="manual"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --brand)
        brand="${2:-}"
        shift 2
        ;;
      --type)
        type="${2:-}"
        shift 2
        ;;
      --text)
        text="${2:-}"
        shift 2
        ;;
      --source)
        source="${2:-}"
        shift 2
        ;;
      --scope)
        scope="${2:-}"
        shift 2
        ;;
      --agent)
        agent="${2:-}"
        shift 2
        ;;
      *)
        err "unknown append option: $1"
        ;;
    esac
  done

  [[ "$type" == "fact" || "$type" == "todo" || "$type" == "decision" ]] || err "--type must be fact, todo, or decision"
  [[ "$scope" == "shared" || "$scope" == "private" ]] || err "--scope must be shared or private"
  [[ -n "$text" ]] || err "--text is required"
  [[ -n "$source" ]] || err "--source is required"
  [[ "$source" == /* ]] || err "--source must be absolute"

  ensure_brand_layout "$brand"

  local effective_scope="$scope"
  if [[ "$scope" == "shared" ]] && is_sensitive_text "$text"; then
    effective_scope="private"
    echo "note: sensitive content detected, routing to private annex"
  fi

  local target
  if [[ "$effective_scope" == "private" ]]; then
    target="$(private_file "$brand")"
  else
    target="$(shared_file "$brand")"
  fi

  local append_rc=0
  append_entry_to_file "$target" "$brand" "$type" "$text" "$source" "$effective_scope" "$agent" || append_rc=$?

  if [[ "$append_rc" -eq 0 ]]; then
    echo "append complete: scope=$effective_scope"
    return 0
  fi

  if [[ "$append_rc" -eq 3 ]]; then
    echo "append skipped: duplicate"
    return 0
  fi
  if [[ "$append_rc" -eq 2 ]]; then
    echo "append skipped: content too short"
    return 0
  fi

  return "$append_rc"
}

compact_single_file() {
  local file="$1"
  local tmp
  local removed_file
  local removed=0

  tmp="$(mktemp)"
  removed_file="$(mktemp)"

  awk -v removed_file="$removed_file" '
    {
      if (match($0, /\[hash:[a-f0-9]{64}\]/)) {
        hash_tag = substr($0, RSTART + 6, RLENGTH - 7)
        if (seen[hash_tag]++) {
          removed++
          next
        }
      }
      print
    }
    END {
      print removed + 0 > removed_file
    }
  ' "$file" > "$tmp"

  mv "$tmp" "$file"
  removed="$(cat "$removed_file")"
  rm -f "$removed_file"
  echo "$removed"
}

cmd_compact() {
  local brand="tkturners"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --brand)
        brand="${2:-}"
        shift 2
        ;;
      *)
        err "unknown compact option: $1"
        ;;
    esac
  done

  ensure_brand_layout "$brand"

  local shared
  local private
  local removed_shared
  local removed_private
  local total

  shared="$(shared_file "$brand")"
  private="$(private_file "$brand")"

  removed_shared="$(compact_single_file "$shared")"
  removed_private="$(compact_single_file "$private")"
  total=$((removed_shared + removed_private))

  append_changelog "$brand" "compact" "both" "internal" "removed_shared=$removed_shared removed_private=$removed_private total=$total" "memoryctl-compact"
  echo "compact complete: removed=$total"
}

run_locked() {
  local subcommand="$1"
  shift
  mkdir -p "$KNOWLEDGE_ROOT"
  lockf "$LOCK_FILE" "$0" __locked "$subcommand" "$@"
}

dispatch() {
  local subcommand="$1"
  shift || true

  case "$subcommand" in
    import)
      cmd_import "$@"
      ;;
    read)
      cmd_read "$@"
      ;;
    append)
      cmd_append "$@"
      ;;
    compact)
      cmd_compact "$@"
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      err "unknown command: $subcommand"
      ;;
  esac
}

main() {
  local subcommand="${1:-}"
  shift || true

  case "$subcommand" in
    import|append|compact)
      run_locked "$subcommand" "$@"
      ;;
    __locked)
      local locked_subcommand="${1:-}"
      shift || true
      dispatch "$locked_subcommand" "$@"
      ;;
    *)
      dispatch "$subcommand" "$@"
      ;;
  esac
}

main "$@"
