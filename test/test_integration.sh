#!/usr/bin/env bash
# Category: Integration / end-to-end

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_set_then_use_default_count() {
    # Genuinely end-to-end: --set-default-count WRITES the config into TEST_HOME,
    # then the history search reads that PERSISTED config (no explicit config
    # string is passed to run_hi). run_ni and run_hi share the same TEST_HOME
    # within one test, so this exercises the real write->read round-trip and
    # would FAIL if --set-default-count ever stopped persisting.
    run_ni --set-default-count 3
    assert_eq 0 "$NI_EXIT" "set-default-count succeeded" || return 1
    local hist
    hist="$(printf '%s\n' "mvn clean" "mvn install" "mvn test" "mvn package" "mvn verify")"
    # No 3rd arg: run_hi leaves the config that --set-default-count wrote in place.
    run_hi "$hist" "mvn"
    assert_line_count 3 "$HI_STDOUT" "persisted default_count=3 read back and used"
}

test_set_then_use_default_unique() {
    # Symmetric counterpart to test_set_then_use_default_count: --set-default-unique
    # WRITES the config into TEST_HOME, then the history search reads that
    # PERSISTED config (no explicit config string is passed to run_hi). Byte-
    # identical matches collapse to exactly 1 under the now-default unique
    # behavior, so this exercises the real write->read round-trip and would FAIL
    # if the setter ever stopped persisting default_unique or the loader ever
    # stopped reading it back at runtime.
    run_ni --set-default-unique true
    assert_eq 0 "$NI_EXIT" "set-default-unique succeeded" || return 1
    local hist
    hist="$(printf '%s\n' "curl aaa" "curl aaa" "echo hello" "curl aaa")"
    # No 3rd arg: run_hi leaves the config that --set-default-unique wrote in place.
    run_hi "$hist" "curl 10"
    assert_line_count 1 "$HI_STDOUT" "persisted default_unique=true read back and dedups"
}

test_realistic_mixed_history() {
    local hist
    hist="$(printf '%s\n' \
        "cd /home/user/project" \
        "git status" \
        "vim main.py" \
        "python main.py --verbose" \
        "git add ." \
        "git commit -m 'fix bug'" \
        "curl -s https://api.example.com/health" \
        "sudo systemctl restart nginx" \
        "git push origin main" \
        "docker compose up -d" \
        "curl -X POST https://api.example.com/deploy" \
        "whatdidi curl" \
        "git log --oneline -5" \
        "sudo docker ps")"
    run_hi "$hist" "curl 5"
    # Should find both curl commands, skip "whatdidi curl"
    assert_line_count 2 "$HI_STDOUT" "exactly 2 curl commands" &&
    assert_not_contains "$HI_STDOUT" "whatdidi" "whatdidi filtered out"
}

test_realistic_git_search() {
    local hist
    hist="$(printf '%s\n' \
        "cd /home/user/project" \
        "git status" \
        "vim main.py" \
        "git add ." \
        "git commit -m 'fix bug'" \
        "git push origin main" \
        "git log --oneline -5")"
    run_hi "$hist" "git 10"
    assert_line_count 5 "$HI_STDOUT" "all 5 git commands found" &&
    # Most recent should be first
    local first_line
    first_line="$(printf '%s\n' "$HI_STDOUT" | head -1)"
    assert_eq "git log --oneline -5" "$first_line" "most recent git cmd first"
}

run_integration_tests() {
    printf '\033[1mIntegration\033[0m\n'
    run_test test_set_then_use_default_count
    run_test test_set_then_use_default_unique
    run_test test_realistic_mixed_history
    run_test test_realistic_git_search
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_integration_tests
    print_summary
fi
