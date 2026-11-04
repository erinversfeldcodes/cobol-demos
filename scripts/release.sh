#!/usr/bin/env bash
# Conventional-commit release helper. Each app is versioned on its own,
# from the commits that touched its directory since its last
# <app>-v<version> tag.
#
#   release.sh version APP   print APP's next version, or nothing if no
#                            commit since its last release warrants one
#   release.sh notes APP     print release notes for those commits
#   release.sh lint          check the commit subjects read on stdin
#
# A breaking change (`type!:` or a BREAKING CHANGE footer) bumps the
# major version, feat the minor, fix and perf the patch. Other types
# (docs, test, ci, ...) are recorded but don't release anything.
set -euo pipefail

TYPES="feat|fix|perf|refactor|docs|test|build|ci|chore|style|revert"
SUBJECT_RE="^($TYPES)(\([a-z0-9-]+\))?(!)?: .+"
BREAKING_RE="^[a-z]+(\([a-z0-9-]+\))?!: "
FEAT_RE="^feat(\([a-z0-9-]+\))?: "
FIX_RE="^(fix|perf)(\([a-z0-9-]+\))?: "

last_tag() {
  git tag --list "$1-v*" --sort=-v:refname | head -n1
}

# Commit messages that touched APP since its last tag, NUL-separated.
messages() {
  local tag
  tag=$(last_tag "$1")
  git log -z --no-merges --format=%B "${tag:+$tag..}HEAD" -- "$1"
}

# 3 major, 2 minor, 1 patch, 0 no release.
bump_of() {
  local subject=${1%%$'\n'*}
  if [[ $subject =~ $BREAKING_RE ]] || grep -qE '^BREAKING[ -]CHANGE: ' <<<"$1"; then
    echo 3
  elif [[ $subject =~ $FEAT_RE ]]; then
    echo 2
  elif [[ $subject =~ $FIX_RE ]]; then
    echo 1
  else
    echo 0
  fi
}

version() {
  local app=$1 bump=0 b msg tag current major minor patch
  while IFS= read -r -d '' msg; do
    b=$(bump_of "$msg")
    ((b > bump)) && bump=$b
  done < <(messages "$app")
  ((bump > 0)) || return 0

  tag=$(last_tag "$app")
  current=${tag#"$app-v"}
  IFS=. read -r major minor patch <<<"${current:-0.0.0}"
  case $bump in
    3) echo "$((major + 1)).0.0" ;;
    2) echo "$major.$((minor + 1)).0" ;;
    1) echo "$major.$minor.$((patch + 1))" ;;
  esac
}

notes() {
  local msg subject
  local -a breaking=() features=() fixes=() other=()
  while IFS= read -r -d '' msg; do
    subject=${msg%%$'\n'*}
    case $(bump_of "$msg") in
      3) breaking+=("$subject") ;;
      2) features+=("$subject") ;;
      1) fixes+=("$subject") ;;
      *) other+=("$subject") ;;
    esac
  done < <(messages "$1")

  section "Breaking changes" "${breaking[@]+"${breaking[@]}"}"
  section "Features" "${features[@]+"${features[@]}"}"
  section "Fixes" "${fixes[@]+"${fixes[@]}"}"
  section "Other changes" "${other[@]+"${other[@]}"}"
}

section() {
  local title=$1
  shift
  (($# > 0)) || return 0
  printf '## %s\n\n' "$title"
  printf -- '- %s\n' "$@"
  printf '\n'
}

lint() {
  local subject status=0
  while IFS= read -r subject; do
    [[ -n $subject ]] || continue
    if [[ ! $subject =~ $SUBJECT_RE ]]; then
      echo "not a conventional commit: $subject" >&2
      status=1
    fi
  done
  if ((status != 0)); then
    echo "expected '<type>[(scope)][!]: <description>', type one of ${TYPES//|/, }" >&2
  fi
  return $status
}

case ${1:-}:$# in
  version:2 | notes:2) "$1" "$2" ;;
  lint:1) lint ;;
  *)
    echo "usage: release.sh version APP | notes APP | lint" >&2
    exit 2
    ;;
esac
