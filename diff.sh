#!/bin/bash

set -euo pipefail

get_pr_number() {
  if [[ -n "${PR_NUMBER:-}" && "${PR_NUMBER}" != "null" ]]; then
    echo "${PR_NUMBER}"
    return
  fi

  echo "Have not received PR_NUMBER env value."

  if [[ -z "${GITHUB_EVENT_PATH:-}" ]]; then
    echo "GITHUB_EVENT_PATH is not set, so the PR number cannot be determined."
    exit 1
  fi

  local pr_number
  pr_number=$(jq -r ".pull_request.number // .issue.number // empty" "${GITHUB_EVENT_PATH}")

  if [[ -z "${pr_number}" || "${pr_number}" == "null" ]]; then
    echo "Failed to determine PR Number."
    exit 1
  fi

  echo "${pr_number}"
}

get_pr_response() {
  local pr_number="$1"

  if [[ -z "${GITHUB_REPOSITORY:-}" ]]; then
    echo "GITHUB_REPOSITORY is not set."
    exit 1
  fi

  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "GITHUB_TOKEN is not set."
    exit 1
  fi

  local api_uri="https://api.github.com"
  local api_header="Accept: application/vnd.github.v3+json"
  local auth_header="Authorization: token ${GITHUB_TOKEN}"

  curl -X GET -s -H "${auth_header}" -H "${api_header}" \
    "${api_uri}/repos/${GITHUB_REPOSITORY}/pulls/${pr_number}"
}

ensure_base_branch_history() {
  local base_branch="$1"

  if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
    echo "Repository is shallow; fetching full history for the current checkout..."
    git fetch --no-tags --prune --unshallow origin
  fi

  echo "Fetching base branch history for ${base_branch}..."
  git fetch --no-tags origin "refs/heads/${base_branch}:refs/remotes/origin/${base_branch}"
}

resolve_base_ref() {
  local base_branch="$1"
  local remote_ref="refs/remotes/origin/${base_branch}"

  if git rev-parse --verify "${remote_ref}" >/dev/null 2>&1; then
    echo "${remote_ref}"
    return
  fi

  if git rev-parse --verify "${base_branch}" >/dev/null 2>&1; then
    echo "${base_branch}"
    return
  fi

  echo "Cannot find a local ref for base branch ${base_branch}."
  exit 1
}

get_merge_base() {
  local base_ref="$1"

  git merge-base --fork-point "${base_ref}" HEAD 2>/dev/null || git merge-base "${base_ref}" HEAD
}

count_ts_nocheck_occurrences() {
  local diff_prefix="$1"
  local diff_content="$2"

  printf '%s\n' "${diff_content}" | awk -v diff_prefix="${diff_prefix}" '
    index($0, diff_prefix) == 1 && $0 ~ /(\/\/|\/\*) @ts-nocheck/ { count++ }
    END { print count + 0 }
  '
}

main() {
  local pr_number
  pr_number=$(get_pr_number)

  echo "Collecting information about PR #${pr_number} of ${GITHUB_REPOSITORY:-unknown repository}..."

  local pr_response
  pr_response=$(get_pr_response "${pr_number}")

  local base_branch
  base_branch=$(printf '%s' "${pr_response}" | jq -r '.base.ref')

  if [[ -z "${base_branch}" || "${base_branch}" == "null" ]]; then
    echo "Cannot get base branch information for PR #${pr_number}!"
    exit 1
  fi

  ensure_base_branch_history "${base_branch}"

  local base_ref
  base_ref=$(resolve_base_ref "${base_branch}")

  local merge_base
  merge_base=$(get_merge_base "${base_ref}")

  echo "Comparing TypeScript changes from merge-base ${merge_base} to HEAD..."

  local git_diff
  git_diff=$(git diff "${merge_base}" HEAD -- '*.ts' '*.tsx')

  local add_count
  add_count=$(count_ts_nocheck_occurrences "+" "${git_diff}")

  local remove_count
  remove_count=$(count_ts_nocheck_occurrences "-" "${git_diff}")

  if [[ "${add_count}" -gt "${remove_count}" ]]; then
    local diff_count=$((add_count - remove_count))
    echo -e "Oh no! This PR introduces ${diff_count} new @ts-nocheck instance(s) :(\n"
    exit 1
  fi

  echo "No new @ts-nocheck instance(s) introduced! :)"
}

main "$@"
