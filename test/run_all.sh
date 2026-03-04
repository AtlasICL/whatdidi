#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

source "$SCRIPT_DIR/helpers.sh"
source "$SCRIPT_DIR/test_help.sh"
source "$SCRIPT_DIR/test_version.sh"
source "$SCRIPT_DIR/test_args.sh"
source "$SCRIPT_DIR/test_set_default.sh"
source "$SCRIPT_DIR/test_config.sh"
source "$SCRIPT_DIR/test_search.sh"
source "$SCRIPT_DIR/test_sudo.sh"
source "$SCRIPT_DIR/test_compound.sh"
source "$SCRIPT_DIR/test_self_filter.sh"
source "$SCRIPT_DIR/test_word_boundary.sh"
source "$SCRIPT_DIR/test_edge_cases.sh"
source "$SCRIPT_DIR/test_integration.sh"

printf '\n\033[1m=== whatdidi test suite ===\033[0m\n\n'

run_help_tests
printf '\n'
run_version_tests
printf '\n'
run_args_tests
printf '\n'
run_set_default_tests
printf '\n'
run_config_tests
printf '\n'
run_search_tests
printf '\n'
run_sudo_tests
printf '\n'
run_compound_tests
printf '\n'
run_self_filter_tests
printf '\n'
run_word_boundary_tests
printf '\n'
run_edge_cases_tests
printf '\n'
run_integration_tests

print_summary
