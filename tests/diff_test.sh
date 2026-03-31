#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

assert_status() {
  local expected_status="$1"
  local actual_status="$2"
  local scenario="$3"
  local output="$4"

  if [[ "${expected_status}" -ne "${actual_status}" ]]; then
    echo "Scenario '${scenario}' failed: expected exit ${expected_status}, got ${actual_status}."
    echo
    echo "${output}"
    exit 1
  fi
}

init_repo() {
  local repo_path="$1"

  git -C "${repo_path}" config user.name "Copilot Test"
  git -C "${repo_path}" config user.email "copilot-tests@example.com"
}

write_file() {
  local repo_path="$1"
  local relative_path="$2"
  local content="$3"

  mkdir -p "$(dirname "${repo_path}/${relative_path}")"
  printf '%s\n' "${content}" > "${repo_path}/${relative_path}"
}

commit_all() {
  local repo_path="$1"
  local message="$2"

  git -C "${repo_path}" add .
  git -C "${repo_path}" commit -m "${message}" >/dev/null
}

setup_stale_base_pass() {
  local origin_path="$1"
  local seed_path="$2"

  git init --bare "${origin_path}" >/dev/null
  git clone "${origin_path}" "${seed_path}" >/dev/null
  init_repo "${seed_path}"

  write_file "${seed_path}" "src/example.ts" "export const value = 1;"
  commit_all "${seed_path}" "initial"
  git -C "${seed_path}" branch -M master
  git -C "${seed_path}" push -u origin master >/dev/null

  git -C "${seed_path}" checkout -b feature >/dev/null
  write_file "${seed_path}" "src/example.ts" "export const value = 2;"
  commit_all "${seed_path}" "feature change"
  git -C "${seed_path}" push -u origin feature >/dev/null

  git -C "${seed_path}" checkout master >/dev/null
  write_file "${seed_path}" "src/base-only.ts" $'// @ts-nocheck\nexport const baseOnly = true;'
  commit_all "${seed_path}" "base adds ts-nocheck"
  git -C "${seed_path}" push >/dev/null
}

setup_true_positive_fail() {
  local origin_path="$1"
  local seed_path="$2"

  git init --bare "${origin_path}" >/dev/null
  git clone "${origin_path}" "${seed_path}" >/dev/null
  init_repo "${seed_path}"

  write_file "${seed_path}" "src/example.ts" "export const value = 1;"
  commit_all "${seed_path}" "initial"
  git -C "${seed_path}" branch -M master
  git -C "${seed_path}" push -u origin master >/dev/null

  git -C "${seed_path}" checkout -b feature >/dev/null
  write_file "${seed_path}" "src/example.ts" $'// @ts-nocheck\nexport const value = 2;'
  commit_all "${seed_path}" "feature adds ts-nocheck"
  git -C "${seed_path}" push -u origin feature >/dev/null
}

setup_removal_pass() {
  local origin_path="$1"
  local seed_path="$2"

  git init --bare "${origin_path}" >/dev/null
  git clone "${origin_path}" "${seed_path}" >/dev/null
  init_repo "${seed_path}"

  write_file "${seed_path}" "src/example.ts" "export const value = 1;"
  commit_all "${seed_path}" "initial"
  git -C "${seed_path}" branch -M master
  git -C "${seed_path}" push -u origin master >/dev/null

  write_file "${seed_path}" "src/example.ts" $'// @ts-nocheck\nexport const value = 1;'
  commit_all "${seed_path}" "base adds ts-nocheck"
  git -C "${seed_path}" push >/dev/null

  git -C "${seed_path}" checkout -b feature >/dev/null
  write_file "${seed_path}" "src/example.ts" "export const value = 1;"
  commit_all "${seed_path}" "feature removes ts-nocheck"
  git -C "${seed_path}" push -u origin feature >/dev/null
}

create_checkout() {
  local origin_path="$1"
  local checkout_path="$2"

  git clone --depth 1 --branch feature "file://${origin_path}" "${checkout_path}" >/dev/null
  git -C "${checkout_path}" checkout --detach HEAD >/dev/null
}

create_mock_curl() {
  local mock_bin_path="$1"

  mkdir -p "${mock_bin_path}"
  cat > "${mock_bin_path}/curl" <<'EOF'
#!/bin/bash
cat <<'JSON'
{"base":{"ref":"master"},"head":{"ref":"feature"}}
JSON
EOF
  chmod +x "${mock_bin_path}/curl"
}

run_scenario() {
  local scenario_name="$1"
  local expected_status="$2"
  local setup_function="$3"

  local temp_dir
  temp_dir="$(mktemp -d)"

  local origin_path="${temp_dir}/origin.git"
  local seed_path="${temp_dir}/seed"
  local checkout_path="${temp_dir}/checkout"
  local mock_bin_path="${temp_dir}/mock-bin"

  "${setup_function}" "${origin_path}" "${seed_path}"
  create_checkout "${origin_path}" "${checkout_path}"
  create_mock_curl "${mock_bin_path}"

  local output
  local actual_status=0

  output="$(
    cd "${checkout_path}"
    PATH="${mock_bin_path}:${PATH}" \
      PR_NUMBER=123 \
      GITHUB_REPOSITORY="Airbase/gh-action-tscheck-action-shell" \
      GITHUB_TOKEN="test-token" \
      bash "${ROOT_DIR}/diff.sh"
  )" || actual_status=$?

  assert_status "${expected_status}" "${actual_status}" "${scenario_name}" "${output}"
  rm -rf "${temp_dir}"
}

run_scenario "stale base changes are ignored" 0 setup_stale_base_pass
run_scenario "new ts-nocheck addition fails" 1 setup_true_positive_fail
run_scenario "ts-nocheck removal passes" 0 setup_removal_pass

echo "All diff.sh tests passed."
