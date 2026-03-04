#!/usr/bin/env bash
# Category: Integration / end-to-end

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/helpers.sh"

test_set_then_use_default_count() {
    # First set the default count via --set-default
    run_ni --set-default 3
    # The config file was created in TEST_HOME; now run a history search
    local hist
    hist="$(printf '%s\n' "mvn clean" "mvn install" "mvn test" "mvn package" "mvn verify")"
    # Pass the config that was written
    run_hi "$hist" "mvn" "default_count=3"
    assert_line_count 3 "$HI_STDOUT" "set-default-count persisted and used"
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
    run_test test_realistic_mixed_history
    run_test test_realistic_git_search
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'
    run_integration_tests
    print_summary
fi
