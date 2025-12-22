// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../../contracts/libraries/CollateralMath.sol";
import "../../contracts/libraries/InterestMath.sol";
import "../../contracts/libraries/MintLogic.sol";
import "../../contracts/libraries/RedeemLogic.sol";
import "../../contracts/libraries/RewardMath.sol";
import "../../contracts/libraries/Constants.sol";

contract LibraryFullTest {

    function testCollateralMath() public pure {
        uint256 col = CollateralMath.collateralValue(1e8, 50_000e18);
        uint256 liab = CollateralMath.liabilityValue(1000e18, 0, 1e18); // btdSupply, stBTDEquivalent, iusdPrice
        uint256 cr = CollateralMath.collateralRatio(1e8, 50_000e18, 1000e18, 0, 1e18); // wbtc, wbtcPrice, btd, stBTD, iusdPrice
        require(col == 50_000e18, "collateral value");
        require(liab == 1000e18, "liability value");
        require(cr == 50_000e18 / 1000, "collateral ratio");
        uint256 maxUSD = CollateralMath.maxRedeemableUSD(col, liab);
        uint256 maxBTD = CollateralMath.maxRedeemableBTD(col, liab, 1e18);
        require(maxUSD == 49_000e18, "max usd");
        require(maxBTD == 49_000e18, "max btd");
    }

    function testCollateralMathMinValueFallback() public view {
        // when collateral or liability is zero, function returns 1e18 (neutral ratio)
        bool ok = _callCollateralRatio(0, 1, 0, 0);
        require(ok, "call should not revert");
    }

    // testDailyWithdrawLimit removed - library deleted

    function testInterestMath() public pure {
        uint256 delta = InterestMath.interestPerShareDelta(100, 365 days);
        require(delta > 0, "delta");
        uint256 reward = InterestMath.pendingReward(100e18, delta, 0);
        require(reward > 0, "pending");
        uint256 fee = InterestMath.feeAmount(100e18, 50); // 0.5%
        require(fee == 5e17, "fee");
        (uint256 iShare, uint256 pShare) = InterestMath.splitWithdrawal(100e18, 10e18, 110e18);
        require(iShare > 0 && pShare > 0, "split");
        uint256 assets = InterestMath.totalAssetsWithAccrued(100e18, 100, 0, 365 days);
        require(assets > 100e18, "accrued");
        int256 bps = InterestMath.priceChangeBps(100e18, 110e18);
        require(bps > 0, "bps pos");
    }

    function testInterestMathEdge() public pure {
        // zero/neg changes
        int256 bps = InterestMath.priceChangeBps(100e18, 100e18);
        require(bps == 0, "bps zero");
        // reward debt when acc is zero
        require(InterestMath.rewardDebtValue(10e18, 0) == 0, "zero acc");
        // totalAssets with no time advance
        require(InterestMath.totalAssetsWithAccrued(100e18, 100, 1000, 500) == 100e18, "no accrual");
    }

    function testMintLogic() public pure {
        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: 1e8,
            wbtcPrice: 50_000e18,
            iusdPrice: 1e18,
            currentBTDSupply: 1_000e18,
            feeBP: 100
        });
        MintLogic.MintOutputs memory out = MintLogic.evaluate(inputs);
        require(out.btdToMint > 0 && out.fee > 0, "mint outputs");
    }

    function testMintLogicTooSmall() public view {
        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: 1,
            wbtcPrice: 1,
            iusdPrice: 1,
            currentBTDSupply: 0,
            feeBP: 0
        });
        bool reverted = !_callMint(inputs);
        require(reverted, "too small mint");
    }

    function testRedeemLogicHealthy() public pure {
        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: 100e18,
            wbtcPrice: 50_000e18,
            iusdPrice: 1e18,
            cr: Constants.PRECISION_18 * 2, // 200%
            btdPrice: 1e18,
            btbPrice: 1e18,
            brsPrice: 1e18,
            minBTBPriceInBTD: 8e17,
            redeemFeeBP: 50  // 0.5% redeem fee
        });
        RedeemLogic.RedeemOutputs memory out = RedeemLogic.evaluate(inputs);
        require(out.wbtcOutNormalized > 0, "wbtc out");
        require(out.btbOut == 0 && out.brsOut == 0, "no loss");
        require(out.fee > 0, "fee charged");
    }

    function testRedeemLogicUnderwater() public pure {
        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: 100e18,
            wbtcPrice: 50_000e18,
            iusdPrice: 1e18,
            cr: Constants.PRECISION_18 / 2, // 50%
            btdPrice: 1e18,
            btbPrice: 9e17,
            brsPrice: 1e18,
            minBTBPriceInBTD: 8e17,
            redeemFeeBP: 50  // 0.5% redeem fee
        });
        RedeemLogic.RedeemOutputs memory out = RedeemLogic.evaluate(inputs);
        require(out.wbtcOutNormalized > 0, "wbtc part");
        require(out.btbOut > 0, "btb comp");
        require(out.fee > 0, "fee charged");
    }

    function testRedeemLogicBadSecondaryPrice() public view {
        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: 100e18,
            wbtcPrice: 50_000e18,
            iusdPrice: 1e18,
            cr: Constants.PRECISION_18 / 2, // 50%
            btdPrice: 0,
            btbPrice: 0,
            brsPrice: 0,
            minBTBPriceInBTD: 0,
            redeemFeeBP: 50  // 0.5% redeem fee
        });
        bool reverted = !_callRedeem(inputs);
        require(reverted, "invalid secondary should revert");
    }

    function testRewardMath() public pure {
        uint256 emission = RewardMath.emissionFor(10, 1e18, 10, 100);
        require(emission > 0, "emission");
        uint256 clamped = RewardMath.clampToMax(0, 100, 50);
        require(clamped == 50, "clamp");
        uint256 acc = RewardMath.accRewardPerShare(0, 100, 10);
        uint256 debt = RewardMath.rewardDebtValue(10, acc);
        uint256 pending = RewardMath.pending(10, acc, debt / 2);
        require(pending > 0, "pending");
    }

    function testRewardMathEdge() public pure {
        require(RewardMath.emissionFor(0, 1, 1, 1) == 0, "zero time");
        require(RewardMath.emissionFor(1, 0, 1, 1) == 0, "zero rate");
        require(RewardMath.clampToMax(100, 10, 50) == 0, "minted>=max");
        require(RewardMath.accRewardPerShare(0, 0, 10) == 0, "no reward");
        require(RewardMath.pending(0, 100, 0) == 0, "no amount");
    }

    // helpers to expect revert on pure functions
    function _callCollateralRatio(uint256 a, uint256 b, uint256 c, uint256 d) private view returns (bool) {
        (bool ok, ) = address(this).staticcall(
            abi.encodeWithSelector(this._wrapCollateral.selector, a, b, c, 0, d)
        );
        return ok;
    }

    function _wrapCollateral(uint256 a, uint256 b, uint256 c, uint256 stBTD, uint256 d) external pure returns (uint256) {
        return CollateralMath.collateralRatio(a, b, c, stBTD, d);
    }

    function _callMint(MintLogic.MintInputs memory inputs) private view returns (bool) {
        (bool ok, ) = address(this).staticcall(
            abi.encodeWithSelector(this._wrapMint.selector, inputs)
        );
        return ok;
    }

    function _wrapMint(MintLogic.MintInputs memory inputs) external pure returns (MintLogic.MintOutputs memory) {
        return MintLogic.evaluate(inputs);
    }

    function _callRedeem(RedeemLogic.RedeemInputs memory inputs) private view returns (bool) {
        (bool ok, ) = address(this).staticcall(
            abi.encodeWithSelector(this._wrapRedeem.selector, inputs)
        );
        return ok;
    }

    function _wrapRedeem(RedeemLogic.RedeemInputs memory inputs) external pure returns (RedeemLogic.RedeemOutputs memory) {
        return RedeemLogic.evaluate(inputs);
    }
}
