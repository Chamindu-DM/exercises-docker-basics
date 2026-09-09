#!/usr/bin/env bash
# Passes if at least one of exercise 1.15 (Docker Hub repository) or 1.16
# (cloud deployment) is completed -- either is an acceptable submission for
# this part of the course.
set -uo pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  echo "FAIL: $1"
  exit 1
}

pass() {
  echo "PASS: $1"
}

echo "--- Running test_1_15_dockerhub_repository.sh ---"
bash "$TESTS_DIR/test_1_15_dockerhub_repository.sh"
RESULT_1_15=$?

echo "--- Running test_1_16_cloud_deployment.sh ---"
bash "$TESTS_DIR/test_1_16_cloud_deployment.sh"
RESULT_1_16=$?

if [ "$RESULT_1_15" -eq 0 ] || [ "$RESULT_1_16" -eq 0 ]; then
  pass "at least one of exercise 1.15 or 1.16 passed (1.15 exit=$RESULT_1_15, 1.16 exit=$RESULT_1_16)"
else
  fail "neither exercise 1.15 nor 1.16 passed (1.15 exit=$RESULT_1_15, 1.16 exit=$RESULT_1_16)"
fi

echo "All tests passed"
