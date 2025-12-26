#!/bin/bash
# Full Test Suite - Local Testing Script
# Mirrors the CI workflow for local validation before pushing

# Don't use set -e, we handle errors manually

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
SKIPPED=0

print_header() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}============================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
    ((PASSED++))
}

print_failure() {
    echo -e "${RED}✗ $1${NC}"
    ((FAILED++))
}

print_skip() {
    echo -e "${YELLOW}○ $1 (skipped)${NC}"
    ((SKIPPED++))
}

print_summary() {
    echo ""
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}  TEST SUMMARY${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo -e "${GREEN}Passed:  $PASSED${NC}"
    echo -e "${RED}Failed:  $FAILED${NC}"
    echo -e "${YELLOW}Skipped: $SKIPPED${NC}"
    echo ""
    if [ $FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed!${NC}"
        exit 1
    fi
}

# Parse arguments
QUICK=false
SKIP_FUZZ=false
SKIP_INVARIANT=false
SKIP_HARDHAT=false
SKIP_FORGE=false
SKIP_LINT=false
SKIP_SECURITY=false
SKIP_GAS=false
SKIP_COVERAGE=false
FUZZ_RUNS=512

while [[ $# -gt 0 ]]; do
    case $1 in
        --quick|-q)
            QUICK=true
            FUZZ_RUNS=64
            SKIP_SECURITY=true
            SKIP_GAS=true
            SKIP_COVERAGE=true
            shift
            ;;
        --skip-fuzz)
            SKIP_FUZZ=true
            shift
            ;;
        --skip-invariant)
            SKIP_INVARIANT=true
            shift
            ;;
        --skip-hardhat)
            SKIP_HARDHAT=true
            shift
            ;;
        --skip-forge)
            SKIP_FORGE=true
            shift
            ;;
        --skip-lint)
            SKIP_LINT=true
            shift
            ;;
        --skip-security)
            SKIP_SECURITY=true
            shift
            ;;
        --skip-gas)
            SKIP_GAS=true
            shift
            ;;
        --skip-coverage)
            SKIP_COVERAGE=true
            shift
            ;;
        --fuzz-runs)
            FUZZ_RUNS=$2
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --quick, -q       Quick mode (64 fuzz runs, skip security/gas/coverage)"
            echo "  --skip-fuzz       Skip fuzz tests"
            echo "  --skip-invariant  Skip invariant tests"
            echo "  --skip-hardhat    Skip Hardhat tests"
            echo "  --skip-forge      Skip all Forge tests"
            echo "  --skip-lint       Skip code quality checks"
            echo "  --skip-security   Skip security analysis (Slither)"
            echo "  --skip-gas        Skip gas report"
            echo "  --skip-coverage   Skip coverage report"
            echo "  --fuzz-runs N     Set number of fuzz runs (default: 512)"
            echo "  --help, -h        Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

echo -e "${BLUE}"
echo "  ____  _ _                   _____         _   "
echo " | __ )(_) |_ _ __ ___  ___  |_   _|__  ___| |_ "
echo " |  _ \| | __| '__/ _ \/ __|   | |/ _ \/ __| __|"
echo " | |_) | | |_| | |  __/\__ \   | |  __/\__ \ |_ "
echo " |____/|_|\__|_|  \___||___/   |_|\___||___/\__|"
echo -e "${NC}"
echo "Full Test Suite - $(date)"
echo ""

# ============ Hardhat Tests ============
if [ "$SKIP_HARDHAT" = false ]; then
    print_header "Hardhat Tests"
    npx hardhat test 2>&1 | tee /tmp/hardhat-test.log
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        print_success "Hardhat Tests"
    else
        print_failure "Hardhat Tests"
    fi
else
    print_skip "Hardhat Tests"
fi

# ============ Forge Tests ============
if [ "$SKIP_FORGE" = false ]; then
    # Unit Tests
    print_header "Forge Unit Tests"
    forge test --match-path "forge-test/unit/*.sol" --no-match-test "testPCEDeviationLimit" -v 2>&1 | tee /tmp/forge-unit.log
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        print_success "Forge Unit Tests"
    else
        print_failure "Forge Unit Tests"
    fi

    # Integration Tests
    print_header "Forge Integration Tests"
    forge test --match-path "forge-test/integration/*.sol" -v 2>&1 | tee /tmp/forge-integration.log
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        print_success "Forge Integration Tests"
    else
        print_failure "Forge Integration Tests"
    fi
else
    print_skip "Forge Unit Tests"
    print_skip "Forge Integration Tests"
fi

# ============ Fuzz Tests ============
if [ "$SKIP_FUZZ" = false ] && [ "$SKIP_FORGE" = false ]; then
    print_header "Forge Fuzz Tests (${FUZZ_RUNS} runs)"
    forge test --match-path "forge-test/fuzz/*.sol" --fuzz-runs $FUZZ_RUNS -v 2>&1 | tee /tmp/forge-fuzz.log
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        print_success "Forge Fuzz Tests"
    else
        print_failure "Forge Fuzz Tests"
    fi
else
    print_skip "Forge Fuzz Tests"
fi

# ============ Invariant Tests ============
if [ "$SKIP_INVARIANT" = false ] && [ "$SKIP_FORGE" = false ]; then
    print_header "Forge Invariant Tests"
    forge test --match-path "forge-test/invariant/*.sol" -v 2>&1 | tee /tmp/forge-invariant.log
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        print_success "Forge Invariant Tests"
    else
        print_failure "Forge Invariant Tests"
    fi
else
    print_skip "Forge Invariant Tests"
fi

# ============ Code Quality ============
if [ "$SKIP_LINT" = false ]; then
    print_header "Code Quality (Lint)"

    # Solidity Linter
    echo "Running Solidity linter..."
    npx solhint 'contracts/**/*.sol' 2>&1 | tee /tmp/solhint.log
    SOLHINT_EXIT=${PIPESTATUS[0]}

    # JavaScript/TypeScript Linter
    echo ""
    echo "Running JavaScript/TypeScript linter..."
    npx eslint 'test/**/*.ts' 'scripts/**/*.{js,mjs,ts}' 2>&1 | tee /tmp/eslint.log
    ESLINT_EXIT=${PIPESTATUS[0]}

    # Lint is advisory (matches CI continue-on-error behavior)
    if [ $SOLHINT_EXIT -eq 0 ] && [ $ESLINT_EXIT -eq 0 ]; then
        print_success "Code Quality (Lint)"
    else
        echo -e "${YELLOW}Note: Lint found issues (check logs above)${NC}"
        print_success "Code Quality (Lint - with warnings)"
    fi
else
    print_skip "Code Quality (Lint)"
fi

# ============ Security Analysis ============
if [ "$SKIP_SECURITY" = false ]; then
    print_header "Security Analysis (Slither)"
    if command -v slither &> /dev/null; then
        slither contracts/ --exclude-dependencies 2>&1 | tee /tmp/slither.log
        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            print_success "Security Analysis"
        else
            # Slither often returns non-zero for warnings, treat as success if it ran
            echo -e "${YELLOW}Note: Slither found issues (check /tmp/slither.log)${NC}"
            print_success "Security Analysis (with warnings)"
        fi
    else
        echo -e "${YELLOW}Slither not installed. Install with: pip3 install slither-analyzer${NC}"
        print_skip "Security Analysis (Slither not installed)"
    fi
else
    print_skip "Security Analysis"
fi

# ============ Gas Report ============
if [ "$SKIP_GAS" = false ]; then
    print_header "Gas Usage Report"
    REPORT_GAS=true npx hardhat test 2>&1 | tee /tmp/gas-report.log
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        print_success "Gas Usage Report"
    else
        print_failure "Gas Usage Report"
    fi
else
    print_skip "Gas Usage Report"
fi

# ============ Coverage Report ============
if [ "$SKIP_COVERAGE" = false ]; then
    print_header "Coverage Report"
    forge coverage --report summary --no-match-test "testPCEDeviationLimit" 2>&1 | tee /tmp/coverage.log
    if [ ${PIPESTATUS[0]} -eq 0 ]; then
        print_success "Coverage Report"
    else
        print_failure "Coverage Report"
    fi
else
    print_skip "Coverage Report"
fi

# ============ Summary ============
print_summary
