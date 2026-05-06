#!/bin/bash
# Stable strict Halmos gate for core safety properties.
#
# This intentionally excludes the slowest monotonic/non-linear arithmetic
# properties that are still tracked by npm run formal:audit.

set -euo pipefail

CORE_PROPERTIES='^(check_smoke_|check_collateralValue_zero_|check_maxRedeemable_|check_inflationMultiplier_unity|check_emissionFor_zero(Time|RewardRate|TotalAlloc)|check_clampToMax_|check_accRewardPerShare_|check_pending_(zeroAmount|zeroAccPerShare)|check_rewardDebtValue_(zeroAmount|zeroAccPerShare)|check_pendingReward_(zeroAmount|zeroAccInterest)|check_interestPerShareDelta_zero(Rate|Time)|check_feeAmount_zero(Amount|Fee)|check_splitWithdrawal_(sumEqualsAmount|zeroAmount|noPendingInterest|interestShareBounded)(\(|$)|check_priceChangeBps_(equalPrices|zeroPreviousPrice)|check_fee_zero_when_feeBP_zero|check_normalizedWBTC_correct|check_fee_calculation|check_no_compensation_overcollateralized|check_deviationWithin_(reflexive|zeroPrice)|check_BTDFloor_neverAboveIUSD|check_inversePrice_nonZero|check_normalizeAmount_|check_spotPrice_positive_when_representable)'

export FORMAL_RUN_MODE="${FORMAL_RUN_MODE:-contract}"
export FORMAL_STRICT_TIMEOUTS="${FORMAL_STRICT_TIMEOUTS:-true}"
export FORMAL_MATCH_PROPERTIES="${FORMAL_MATCH_PROPERTIES:-${CORE_PROPERTIES}}"
export FORMAL_CONTRACT_TIMEOUT="${FORMAL_CONTRACT_TIMEOUT:-240}"

exec bash scripts/formal-verify.sh
