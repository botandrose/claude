#!/usr/bin/env bash
# Hook to allow piped commands where ALL components are in the allowed Bash permissions.
# Claude Code's prefix matching doesn't handle pipes - this hook fixes that.
# Dynamically reads allowed commands from:
#   1. ~/.claude/settings.json (global)
#   2. .claude/settings.json (project shared)
#   3. .claude/settings.local.json (project local)
#
# Dependencies: shfmt, jq
#
# Adapted from claude-code-plus by AbdelrahmanHafez
# https://github.com/AbdelrahmanHafez/claude-code-plus

set -euo pipefail

# Re-exec with modern bash if running in old bash (mapfile requires bash 4+)
if [[ "${BASH_VERSINFO[0]}" -lt 4 ]]; then
  for try_bash in /opt/homebrew/bin/bash /usr/local/bin/bash /home/linuxbrew/.linuxbrew/bin/bash; do
    if [[ -x "$try_bash" ]]; then
      exec "$try_bash" "$0" "$@"
    fi
  done
  exit 0
fi

# Read hook data from stdin (passed by dispatcher)
HOOK_DATA=$(cat)

# Only process Bash tool calls
TOOL_NAME=$(echo "$HOOK_DATA" | jq -r '.tool_name // ""' 2>/dev/null)
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

DEBUG=false
NUL_DELIM=false

debug() {
  if $DEBUG; then
    echo "[DEBUG] $*" >&2
  fi
}

extract_prefixes_from_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  jq -r '.permissions.allow[]? // empty' "$file" 2>/dev/null \
    | grep -E '^Bash\(' \
    | sed -E 's/^Bash\(//; s/(:\*)?\)$//'
}

find_git_root() {
  git rev-parse --show-toplevel 2>/dev/null
}

get_allowed_prefixes() {
  local git_root
  git_root=$(find_git_root)

  {
    extract_prefixes_from_file "$HOME/.claude/settings.json"

    if [[ -n "$git_root" ]]; then
      extract_prefixes_from_file "$git_root/.claude/settings.json"
      extract_prefixes_from_file "$git_root/.claude/settings.local.json"
    else
      extract_prefixes_from_file ".claude/settings.json"
      extract_prefixes_from_file ".claude/settings.local.json"
    fi
  } | sort -u
}

is_command_allowed() {
  local full_command="$1"
  local -n prefixes_ref=$2

  for allowed in "${prefixes_ref[@]}"; do
    if [[ "$full_command" == $allowed ]] || [[ "$full_command" == "$allowed "* ]] || [[ "$full_command" == "$allowed/"* ]]; then
      debug "ALLOWED: '$full_command' (matches '$allowed')"
      return 0
    fi
  done

  debug "BLOCKED: '$full_command' (no matching prefix)"
  return 1
}

# Normalize shfmt-incompatible patterns
normalize_for_shfmt() {
  local cmd="$1"
  echo "$cmd" | perl -pe 's/\[\[\s*\\?!\s+(.+?)\s+=~\s*/! [[ $1 =~ /g'
}

# jq filter to extract commands from shfmt AST
read -r -d '' JQ_FILTER << 'JQEOF' || true
def get_part_value:
  if (type == "object" | not) then ""
  elif .Type == "Lit" then .Value // ""
  elif .Type == "DblQuoted" then
    "\"" + ([.Parts[]? | get_part_value] | join("")) + "\""
  elif .Type == "SglQuoted" then
    "'" + (.Value // "") + "'"
  elif .Type == "ParamExp" then
    "$" + (.Param.Value // "")
  elif .Type == "CmdSubst" then
    "$(..)"
  else
    ""
  end;

def find_cmd_substs:
  if type == "object" then
    if .Type == "CmdSubst" or .Type == "ProcSubst" then .
    elif .Type == "DblQuoted" then .Parts[]? | find_cmd_substs
    elif .Type == "ParamExp" then
      (.Exp?.Word | find_cmd_substs),
      (.Repl?.Orig | find_cmd_substs),
      (.Repl?.With | find_cmd_substs)
    elif .Parts then .Parts[]? | find_cmd_substs
    else empty
    end
  elif type == "array" then .[] | find_cmd_substs
  else empty
  end;

def get_arg_value:
  [.Parts[]? | get_part_value] | join("");

def get_command_string:
  if .Type == "CallExpr" and .Args then
    [.Args[] | get_arg_value] | map(select(length > 0)) | join(" ")
  else
    empty
  end;

def extract_commands:
  if type == "object" then
    if .Type == "CallExpr" then
      get_command_string,
      (.Args[]? | find_cmd_substs | .Stmts[]? | extract_commands),
      (.Assigns[]?.Value | find_cmd_substs | .Stmts[]? | extract_commands),
      (.Assigns[]?.Array?.Elems[]?.Value | find_cmd_substs | .Stmts[]? | extract_commands),
      (.Redirs[]?.Word | find_cmd_substs | .Stmts[]? | extract_commands)
    elif .Type == "BinaryCmd" then
      (.X | extract_commands),
      (.Y | extract_commands)
    elif .Type == "Subshell" or .Type == "Block" then
      (.Stmts[]? | extract_commands)
    elif .Type == "CmdSubst" then
      (.Stmts[]? | extract_commands)
    elif .Type == "IfClause" then
      (.Cond[]? | extract_commands),
      (.Then[]? | extract_commands),
      (.Else | extract_commands)
    elif .Type == "WhileClause" or .Type == "UntilClause" then
      (.Cond[]? | extract_commands),
      (.Do[]? | extract_commands)
    elif .Type == "ForClause" then
      (.Loop.Items[]? | find_cmd_substs | .Stmts[]? | extract_commands),
      (.Do[]? | extract_commands)
    elif .Type == "CaseClause" then
      (.Items[]?.Stmts[]? | extract_commands)
    elif .Cmd then
      (.Cmd | extract_commands),
      (.Redirs[]?.Word | find_cmd_substs | .Stmts[]? | extract_commands)
    elif .Stmts then
      (.Stmts[] | extract_commands)
    else
      (.[] | extract_commands)
    end
  elif type == "array" then
    (.[] | extract_commands)
  else
    empty
  end;

extract_commands | select(length > 0)
JQEOF

extract_commands_raw() {
  local cmd="$1"
  local ast

  cmd=$(normalize_for_shfmt "$cmd")

  if ! ast=$(echo "$cmd" | shfmt -ln bash -tojson 2>&1); then
    return 1
  fi

  echo "$ast" | jq -r "$JQ_FILTER" 2>/dev/null
}

get_shell_c_inner() {
  local cmd="$1"
  local stripped="$cmd"

  if [[ "$cmd" =~ ^env[[:space:]]+ ]]; then
    stripped="${cmd#env }"
    stripped="${stripped# }"
  fi

  if [[ "$stripped" =~ ^/[^[:space:]]*/(.+)$ ]]; then
    stripped="${BASH_REMATCH[1]}"
  fi

  if [[ "$stripped" =~ ^(bash|sh)[[:space:]]+-c[[:space:]]*[\'\"](.*)[\'\"]$ ]]; then
    echo "${BASH_REMATCH[2]}"
  elif [[ "$stripped" =~ ^(bash|sh)[[:space:]]+-c[\'\"](.*)[\'\"]$ ]]; then
    echo "${BASH_REMATCH[2]}"
  fi
}

extract_commands_from_string() {
  local cmd="$1"
  local raw_commands

  raw_commands=$(extract_commands_raw "$cmd") || return 1

  while IFS= read -r line; do
    [[ -z "$line" ]] && continue

    local inner
    inner=$(get_shell_c_inner "$line")

    if [[ -n "$inner" ]]; then
      extract_commands_from_string "$inner"
    else
      if $NUL_DELIM; then
        printf '%s\0' "$line"
      else
        echo "$line"
      fi
    fi
  done <<< "$raw_commands"
}

main() {
  # Check for required dependencies
  if ! command -v jq &>/dev/null; then
    exit 0
  fi

  if ! command -v shfmt &>/dev/null; then
    # shfmt not installed, fall through to normal permission check
    exit 0
  fi

  command=$(echo "$HOOK_DATA" | jq -r '.tool_input.command // empty')

  if [[ -z "$command" ]]; then
    exit 0
  fi

  # Load allowed prefixes into array
  mapfile -t allowed_prefixes < <(get_allowed_prefixes)

  if [[ ${#allowed_prefixes[@]} -eq 0 ]]; then
    exit 0
  fi

  # Extract commands using shfmt parser
  NUL_DELIM=true
  mapfile -d '' extracted_commands < <(extract_commands_from_string "$command") || {
    exit 0
  }

  if [[ ${#extracted_commands[@]} -eq 0 ]] || [[ -z "${extracted_commands[0]}" ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
  fi

  # Check each command against allowed prefixes
  all_allowed=true
  for full_command in "${extracted_commands[@]}"; do
    [[ -z "$full_command" ]] && continue

    if ! is_command_allowed "$full_command" allowed_prefixes; then
      all_allowed=false
      break
    fi
  done

  if $all_allowed; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  fi

  exit 0
}

main "$@"
