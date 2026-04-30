#!/usr/bin/env bash
# Generate a focused branch-coverage report from Forge LCOV output.

set -euo pipefail

REPORT_DIR="${REPORT_DIR:-reports/coverage}"
LCOV_FILE="${LCOV_FILE:-lcov.info}"
RUN_COVERAGE="${RUN_COVERAGE:-true}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_FILE="${REPORT_DIR}/branches-${TIMESTAMP}.txt"

mkdir -p "${REPORT_DIR}"

if [ "${RUN_COVERAGE}" = "true" ]; then
    forge coverage \
        --ir-minimum \
        --report lcov \
        --exclude-tests \
        --no-match-coverage 'contracts/local|contracts/test' \
        --no-match-test 'testPCEDeviationLimit'
fi

if [ ! -f "${LCOV_FILE}" ]; then
    echo "Missing ${LCOV_FILE}. Run with RUN_COVERAGE=true or provide LCOV_FILE=path/to/lcov.info" >&2
    exit 1
fi

{
    echo "Bitres Branch Coverage Report"
    echo "Generated: $(date)"
    echo "LCOV: ${LCOV_FILE}"
    echo ""

    echo "== Totals =="
    awk '
        BEGIN { brf=0; brh=0; lf=0; lh=0; fnf=0; fnh=0 }
        /^BRF:/ { v=$0; sub("BRF:", "", v); brf += v }
        /^BRH:/ { v=$0; sub("BRH:", "", v); brh += v }
        /^LF:/ { v=$0; sub("LF:", "", v); lf += v }
        /^LH:/ { v=$0; sub("LH:", "", v); lh += v }
        /^FNF:/ { v=$0; sub("FNF:", "", v); fnf += v }
        /^FNH:/ { v=$0; sub("FNH:", "", v); fnh += v }
        END {
            printf "Lines      %.2f%% (%d/%d)\n", lh * 100 / lf, lh, lf
            printf "Functions  %.2f%% (%d/%d)\n", fnh * 100 / fnf, fnh, fnf
            printf "Branches   %.2f%% (%d/%d)\n", brh * 100 / brf, brh, brf
        }
    ' "${LCOV_FILE}"
    echo ""

    echo "== Files By Missed Branch Count =="
    awk '
        /^SF:/ {
            file=$0
            sub("SF:", "", file)
            brf=0
            brh=0
        }
        /^BRF:/ { brf=$0; sub("BRF:", "", brf) }
        /^BRH:/ { brh=$0; sub("BRH:", "", brh) }
        /^end_of_record/ {
            if (brf + 0 > 0) {
                missed = brf - brh
                printf "%4d missed  %6.2f%%  %4d/%-4d  %s\n", missed, brh * 100 / brf, brh, brf, file
            }
        }
    ' "${LCOV_FILE}" | sort -nr
    echo ""

    echo "== Files By Lowest Branch Percentage =="
    awk '
        /^SF:/ {
            file=$0
            sub("SF:", "", file)
            brf=0
            brh=0
        }
        /^BRF:/ { brf=$0; sub("BRF:", "", brf) }
        /^BRH:/ { brh=$0; sub("BRH:", "", brh) }
        /^end_of_record/ {
            if (brf + 0 > 0) {
                printf "%6.2f%%  %4d/%-4d  %s\n", brh * 100 / brf, brh, brf, file
            }
        }
    ' "${LCOV_FILE}" | sort -n
    echo ""

    echo "== Missed Branch Lines =="
    awk '
        /^SF:/ {
            file=$0
            sub("SF:", "", file)
        }
        /^BRDA:/ {
            data=$0
            sub("BRDA:", "", data)
            split(data, fields, ",")
            line=fields[1]
            hits=fields[4]
            if (hits == "-" || hits == 0) {
                missed[file ":" line]++
            }
        }
        END {
            for (key in missed) {
                printf "%4d  %s\n", missed[key], key
            }
        }
    ' "${LCOV_FILE}" | sort -nr
} | tee "${REPORT_FILE}"

echo ""
echo "Saved branch report to ${REPORT_FILE}"
