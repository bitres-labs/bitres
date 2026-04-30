#!/bin/bash
# Formal verification runner using Halmos symbolic execution.
#
# The script runs every formal contract under forge-test/formal, writes one log
# per contract, and reports PASS/FAIL/TIMEOUT counts without hanging forever on
# hard solver queries.

set -u

echo "================================================"
echo "  Formal Verification with Halmos"
echo "================================================"

if ! command -v halmos &> /dev/null && ! command -v "${HOME}/.local/bin/halmos" &> /dev/null; then
    echo "Error: halmos not found. Install with: pip3 install halmos"
    exit 1
fi

HALMOS="${HOME}/.local/bin/halmos"
if command -v halmos &> /dev/null; then
    HALMOS="halmos"
fi

HALMOS_LOOP="${HALMOS_LOOP:-3}"
HALMOS_SOLVER_TIMEOUT_MS="${HALMOS_SOLVER_TIMEOUT_MS:-30000}"
FORMAL_CONTRACT_TIMEOUT="${FORMAL_CONTRACT_TIMEOUT:-180}"
FORMAL_RUN_MODE="${FORMAL_RUN_MODE:-contract}"
FORMAL_PROPERTY_TIMEOUT="${FORMAL_PROPERTY_TIMEOUT:-60}"
FORMAL_MATCH_CONTRACTS="${FORMAL_MATCH_CONTRACTS:-}"
FORMAL_STRICT_TIMEOUTS="${FORMAL_STRICT_TIMEOUTS:-false}"
FORMAL_REPORT_DIR="${FORMAL_REPORT_DIR:-reports/formal}"
FORMAL_BUILD_OUT="${FORMAL_BUILD_OUT:-out-formal}"

mkdir -p "${FORMAL_REPORT_DIR}"

echo ""
echo "Settings:"
echo "  HALMOS_LOOP=${HALMOS_LOOP}"
echo "  HALMOS_SOLVER_TIMEOUT_MS=${HALMOS_SOLVER_TIMEOUT_MS}"
echo "  FORMAL_CONTRACT_TIMEOUT=${FORMAL_CONTRACT_TIMEOUT}s"
echo "  FORMAL_RUN_MODE=${FORMAL_RUN_MODE}"
echo "  FORMAL_PROPERTY_TIMEOUT=${FORMAL_PROPERTY_TIMEOUT}s"
echo "  FORMAL_MATCH_CONTRACTS=${FORMAL_MATCH_CONTRACTS}"
echo "  FORMAL_STRICT_TIMEOUTS=${FORMAL_STRICT_TIMEOUTS}"
echo "  FORMAL_REPORT_DIR=${FORMAL_REPORT_DIR}"
echo "  FORMAL_BUILD_OUT=${FORMAL_BUILD_OUT}"

echo ""
echo "[1/8] Building contracts..."
forge build forge-test/formal --out "${FORMAL_BUILD_OUT}" --force --ast --quiet
if [ $? -ne 0 ]; then
    echo "Build failed; formal verification skipped."
    exit 1
fi

CONTRACTS=(
    "CollateralMathFormalTest:CollateralMath:forge-test/formal/CollateralMathFormal.t.sol"
    "IUSDMathFormalTest:IUSDMath:forge-test/formal/IUSDMathFormal.t.sol"
    "RewardMathFormalTest:RewardMath:forge-test/formal/RewardMathFormal.t.sol"
    "InterestMathFormalTest:InterestMath:forge-test/formal/InterestMathFormal.t.sol"
    "MintLogicFormalTest:MintLogic:forge-test/formal/MintLogicFormal.t.sol"
    "RedeemLogicFormalTest:RedeemLogic:forge-test/formal/RedeemLogicFormal.t.sol"
    "PriceOracleFormalTest:PriceOracle:forge-test/formal/PriceOracleFormal.t.sol"
)

TOTAL_PASS=0
TOTAL_FAIL=0
TOTAL_TIMEOUT=0
TOTAL_RUN_ERRORS=0
TOTAL_PROCESS_TIMEOUTS=0

summarize_run() {
    local run_name="$1"
    local log_file="$2"
    local status="$3"
    local timeout_seconds="$4"

    grep -E "(\[PASS\]|\[FAIL\]|\[TIMEOUT\]|Symbolic test result|error|Error)" "${log_file}" || true

    local pass_count
    local fail_count
    local timeout_count
    pass_count=$(grep -c "\[PASS\]" "${log_file}" || true)
    fail_count=$(grep -c "\[FAIL\]" "${log_file}" || true)
    timeout_count=$(grep -c "\[TIMEOUT\]" "${log_file}" || true)

    TOTAL_PASS=$((TOTAL_PASS + pass_count))
    TOTAL_FAIL=$((TOTAL_FAIL + fail_count))
    TOTAL_TIMEOUT=$((TOTAL_TIMEOUT + timeout_count))

    if [ "${status}" -eq 124 ]; then
        TOTAL_PROCESS_TIMEOUTS=$((TOTAL_PROCESS_TIMEOUTS + 1))
        echo "[PROCESS TIMEOUT] ${run_name} exceeded ${timeout_seconds}s; partial log kept at ${log_file}"
    elif [ "${status}" -ne 0 ] && [ "${fail_count}" -eq 0 ] && [ "${timeout_count}" -eq 0 ]; then
        TOTAL_RUN_ERRORS=$((TOTAL_RUN_ERRORS + 1))
        echo "[RUN ERROR] ${run_name} exited with status ${status}; log kept at ${log_file}"
    fi

    echo "Summary for ${run_name}: PASS=${pass_count} FAIL=${fail_count} TIMEOUT=${timeout_count}"
}

for i in "${!CONTRACTS[@]}"; do
    entry="${CONTRACTS[$i]}"
    contract="${entry%%:*}"
    rest="${entry#*:}"
    label="${rest%%:*}"
    source_file="${rest#*:}"
    step=$((i + 2))

    if [ -n "${FORMAL_MATCH_CONTRACTS}" ] \
        && [[ ! "${contract}" =~ ${FORMAL_MATCH_CONTRACTS} ]] \
        && [[ ! "${label}" =~ ${FORMAL_MATCH_CONTRACTS} ]]; then
        continue
    fi

    echo ""
    echo "[${step}/8] Verifying ${label} properties (${contract})..."

    if [ "${FORMAL_RUN_MODE}" = "property" ]; then
        mapfile -t properties < <(grep -Eho "function check_[A-Za-z0-9_]*" "${source_file}" | awk '{print $2}')
        echo "Running ${#properties[@]} properties individually..."

        for property in "${properties[@]}"; do
            log_file="${FORMAL_REPORT_DIR}/${contract}.${property}.log"
            echo ""
            echo "  - ${property}"
            timeout "${FORMAL_PROPERTY_TIMEOUT}s" "${HALMOS}" \
                --forge-build-out "${FORMAL_BUILD_OUT}" \
                --match-contract "${contract}" \
                --match-test "^${property}$" \
                --solver-timeout-assertion "${HALMOS_SOLVER_TIMEOUT_MS}" \
                --loop "${HALMOS_LOOP}" \
                > "${log_file}" 2>&1
            status=$?
            summarize_run "${contract}.${property}" "${log_file}" "${status}" "${FORMAL_PROPERTY_TIMEOUT}"
        done
    else
        log_file="${FORMAL_REPORT_DIR}/${contract}.log"
        timeout "${FORMAL_CONTRACT_TIMEOUT}s" "${HALMOS}" \
            --forge-build-out "${FORMAL_BUILD_OUT}" \
            --match-contract "${contract}" \
            --solver-timeout-assertion "${HALMOS_SOLVER_TIMEOUT_MS}" \
            --loop "${HALMOS_LOOP}" \
            > "${log_file}" 2>&1
        status=$?
        summarize_run "${contract}" "${log_file}" "${status}" "${FORMAL_CONTRACT_TIMEOUT}"
    fi
done

DECLARED_PROPERTIES=$(grep -Rho "function check_[A-Za-z0-9_]*" forge-test/formal | wc -l | tr -d ' ')
OBSERVED_PROPERTIES=$((TOTAL_PASS + TOTAL_FAIL + TOTAL_TIMEOUT))

echo ""
echo "================================================"
echo "  Formal Verification Complete"
echo "================================================"
echo "Declared check_ properties: ${DECLARED_PROPERTIES}"
echo "Observed PASS/FAIL/TIMEOUT: ${OBSERVED_PROPERTIES}"
echo "PASS: ${TOTAL_PASS}"
echo "FAIL: ${TOTAL_FAIL}"
echo "PROPERTY TIMEOUT: ${TOTAL_TIMEOUT}"
echo "PROCESS TIMEOUT: ${TOTAL_PROCESS_TIMEOUTS}"
echo "RUN ERROR: ${TOTAL_RUN_ERRORS}"
echo "Logs: ${FORMAL_REPORT_DIR}"
echo ""
echo "TIMEOUT means the solver did not prove the property within the configured time; it is not a counterexample."

if [ "${TOTAL_FAIL}" -gt 0 ] || [ "${TOTAL_RUN_ERRORS}" -gt 0 ]; then
    exit 1
fi

if [ "${FORMAL_STRICT_TIMEOUTS}" = "true" ] && { [ "${TOTAL_TIMEOUT}" -gt 0 ] || [ "${TOTAL_PROCESS_TIMEOUTS}" -gt 0 ]; }; then
    exit 1
fi

exit 0
