// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/libraries/MintLogic.sol";
import "../../contracts/libraries/RedeemLogic.sol";
import "../../contracts/libraries/CollateralMath.sol";

/// @title Minter Integration Test
/// @notice Tests MintLogic, RedeemLogic, and CollateralMath integration
contract MinterIntegrationTest is Test {

    uint256 constant WBTC_PRICE = 50000e18; // $50,000
    uint256 constant IUSD_PRICE = 1e18;     // $1
    uint16 constant MINT_FEE_BP = 50;       // 0.5%
    uint16 constant REDEEM_FEE_BP = 50;     // 0.5%

    // ============ MintLogic Tests ============

    function test_mintLogic_basicMint() public pure {
        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: 1e8, // 1 BTC
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            currentBTDSupply: 0,
            feeBP: MINT_FEE_BP
        });

        MintLogic.MintOutputs memory outputs = MintLogic.evaluate(inputs);

        // Should mint approximately $50k worth of BTD (minus fee)
        assertTrue(outputs.btdToMint > 0, "Should mint BTD");
        assertTrue(outputs.fee > 0, "Should have fee");
        assertEq(outputs.btdToMint + outputs.fee, outputs.btdGross, "btdToMint + fee = btdGross");
    }

    function test_mintLogic_zeroFee() public pure {
        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: 1e8,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            currentBTDSupply: 0,
            feeBP: 0 // No fee
        });

        MintLogic.MintOutputs memory outputs = MintLogic.evaluate(inputs);

        assertEq(outputs.fee, 0, "Fee should be zero");
        assertEq(outputs.btdToMint, outputs.btdGross, "All BTD should go to user");
    }

    function test_mintLogic_smallAmount() public pure {
        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: 1e5, // 0.001 BTC = ~$50
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            currentBTDSupply: 1000000e18,
            feeBP: MINT_FEE_BP
        });

        MintLogic.MintOutputs memory outputs = MintLogic.evaluate(inputs);

        assertTrue(outputs.btdToMint > 0, "Should mint some BTD");
    }

    function test_mintLogic_largeAmount() public pure {
        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: 100e8, // 100 BTC = ~$5M
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            currentBTDSupply: 0,
            feeBP: MINT_FEE_BP
        });

        MintLogic.MintOutputs memory outputs = MintLogic.evaluate(inputs);

        // Approximately $5M worth
        assertGt(outputs.btdGross, 4900000e18, "Should mint ~$5M BTD");
        assertLt(outputs.btdGross, 5100000e18, "Should mint ~$5M BTD");
    }

    function test_mintLogic_highWBTCPrice() public pure {
        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: 1e8,
            wbtcPrice: 100000e18, // $100k BTC
            iusdPrice: IUSD_PRICE,
            currentBTDSupply: 0,
            feeBP: MINT_FEE_BP
        });

        MintLogic.MintOutputs memory outputs = MintLogic.evaluate(inputs);

        // Should mint ~$100k worth
        assertGt(outputs.btdGross, 99000e18, "Should mint ~$100k BTD");
    }

    function test_mintLogic_withInflation() public pure {
        // IUSD price > $1 means inflation happened
        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: 1e8,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: 1.05e18, // 5% inflation
            currentBTDSupply: 0,
            feeBP: MINT_FEE_BP
        });

        MintLogic.MintOutputs memory outputs = MintLogic.evaluate(inputs);

        // Should mint less BTD due to inflation adjustment
        assertTrue(outputs.btdGross < 50000e18, "Inflation should reduce BTD minted");
    }

    // ============ RedeemLogic Tests ============

    function test_redeemLogic_overcollateralized() public pure {
        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: 1000e18, // Redeem 1000 BTD
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            cr: 2e18, // 200% CR
            btdPrice: 1e18,
            btbPrice: 1e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: REDEEM_FEE_BP
        });

        RedeemLogic.RedeemOutputs memory outputs = RedeemLogic.evaluate(inputs);

        // Should get only WBTC, no BTB/BRS compensation
        assertTrue(outputs.wbtcOutNormalized > 0, "Should get WBTC");
        assertEq(outputs.btbOut, 0, "No BTB compensation when overcollateralized");
        assertEq(outputs.brsOut, 0, "No BRS compensation when overcollateralized");
    }

    function test_redeemLogic_undercollateralized() public pure {
        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: 1000e18,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            cr: 0.5e18, // 50% CR
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: REDEEM_FEE_BP
        });

        RedeemLogic.RedeemOutputs memory outputs = RedeemLogic.evaluate(inputs);

        // Should get partial WBTC + BTB/BRS compensation
        assertTrue(outputs.wbtcOutNormalized > 0, "Should get some WBTC");
        assertTrue(outputs.btbOut > 0 || outputs.brsOut > 0, "Should get compensation");
    }

    function test_redeemLogic_exactlyAt100CR() public pure {
        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: 1000e18,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            cr: 1e18, // 100% CR exactly
            btdPrice: 1e18,
            btbPrice: 1e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: REDEEM_FEE_BP
        });

        RedeemLogic.RedeemOutputs memory outputs = RedeemLogic.evaluate(inputs);

        assertTrue(outputs.wbtcOutNormalized > 0, "Should get WBTC");
    }

    function test_redeemLogic_zeroFee() public pure {
        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: 1000e18,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            cr: 2e18,
            btdPrice: 1e18,
            btbPrice: 1e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: 0 // No fee
        });

        RedeemLogic.RedeemOutputs memory outputs = RedeemLogic.evaluate(inputs);

        assertEq(outputs.fee, 0, "Fee should be zero");
    }

    // ============ CollateralMath Tests ============

    function test_collateralRatio_overcollateralized() public pure {
        // 10 BTC @ $50k = $500k collateral
        // 250k BTD = 200% CR
        uint256 cr = CollateralMath.collateralRatio(
            10e8,       // 10 BTC
            WBTC_PRICE, // $50k
            250000e18,  // 250k BTD
            0,          // no stBTD
            IUSD_PRICE
        );

        assertEq(cr, 2e18, "CR should be 200%");
    }

    function test_collateralRatio_undercollateralized() public pure {
        uint256 cr = CollateralMath.collateralRatio(
            1e8,        // 1 BTC = $50k
            WBTC_PRICE,
            100000e18,  // 100k BTD liability
            0,
            IUSD_PRICE
        );

        assertEq(cr, 0.5e18, "CR should be 50%");
    }

    function test_collateralRatio_withStBTD() public pure {
        uint256 cr = CollateralMath.collateralRatio(
            2e8,        // 2 BTC = $100k
            WBTC_PRICE,
            50000e18,   // 50k BTD
            50000e18,   // 50k stBTD equivalent
            IUSD_PRICE
        );

        // $100k / ($50k + $50k) = 100%
        assertEq(cr, 1e18, "CR should be 100%");
    }

    function test_collateralRatio_noLiabilities() public pure {
        uint256 cr = CollateralMath.collateralRatio(
            1e8,
            WBTC_PRICE,
            0,  // No BTD
            0,  // No stBTD
            IUSD_PRICE
        );

        // When no liabilities, CR returns 1e18 (100%) as a safe default
        assertEq(cr, 1e18, "CR should be 100% when no liabilities");
    }

    function test_collateralValue_calculation() public pure {
        uint256 value = CollateralMath.collateralValue(10e8, WBTC_PRICE);
        assertEq(value, 500000e18, "10 BTC @ $50k = $500k");
    }

    function test_liabilityValue_calculation() public pure {
        uint256 value = CollateralMath.liabilityValue(100000e18, 50000e18, IUSD_PRICE);
        assertEq(value, 150000e18, "100k BTD + 50k stBTD = $150k");
    }

    function test_maxRedeemableBTD_withSurplus() public pure {
        // Collateral $200k, Liability $100k, surplus = $100k
        uint256 maxRedeemable = CollateralMath.maxRedeemableBTD(
            200000e18,  // collateral value
            100000e18,  // liability value
            IUSD_PRICE
        );

        assertEq(maxRedeemable, 100000e18, "Max redeemable = surplus");
    }

    function test_maxRedeemableBTD_undercollateralized() public pure {
        // Collateral $50k < Liability $100k
        uint256 maxRedeemable = CollateralMath.maxRedeemableBTD(
            50000e18,
            100000e18,
            IUSD_PRICE
        );

        assertEq(maxRedeemable, 0, "No redeemable when undercollateralized");
    }

    // ============ Fuzz Tests ============

    function testFuzz_mintLogic_outputsConsistent(
        uint256 wbtcAmount,
        uint256 wbtcPrice,
        uint16 feeBP
    ) public pure {
        wbtcAmount = bound(wbtcAmount, 1e5, 100e8);
        wbtcPrice = bound(wbtcPrice, 10000e18, 200000e18);
        feeBP = uint16(bound(feeBP, 0, 1000)); // Max 10%

        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: IUSD_PRICE,
            currentBTDSupply: 0,
            feeBP: feeBP
        });

        MintLogic.MintOutputs memory outputs = MintLogic.evaluate(inputs);

        // Invariant: btdToMint + fee = btdGross
        assertEq(outputs.btdToMint + outputs.fee, outputs.btdGross, "Sum should equal gross");
        assertTrue(outputs.btdToMint <= outputs.btdGross, "User amount <= gross");
    }

    function testFuzz_collateralRatio_positive(
        uint256 wbtcBalance,
        uint256 btdSupply
    ) public pure {
        wbtcBalance = bound(wbtcBalance, 1e5, 100e8);
        btdSupply = bound(btdSupply, 1e15, 1000000e18);

        uint256 cr = CollateralMath.collateralRatio(
            wbtcBalance,
            WBTC_PRICE,
            btdSupply,
            0,
            IUSD_PRICE
        );

        assertTrue(cr > 0, "CR should be positive");
    }

    function testFuzz_redeemLogic_feeNeverExceedsAmount(
        uint256 btdAmount,
        uint16 feeBP
    ) public pure {
        // Use reasonable minimum that passes USD value checks
        btdAmount = bound(btdAmount, 10e18, 1000000e18);
        feeBP = uint16(bound(feeBP, 0, 1000));

        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            cr: 2e18,
            btdPrice: 1e18,
            btbPrice: 1e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: feeBP
        });

        RedeemLogic.RedeemOutputs memory outputs = RedeemLogic.evaluate(inputs);

        assertTrue(outputs.fee <= btdAmount, "Fee should not exceed amount");
    }

    // ============ Edge Cases ============

    function test_mintLogic_smallWBTC() public pure {
        // Use a small but meaningful amount (0.001 BTC = 1e5 satoshis)
        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: 1e5,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            currentBTDSupply: 0,
            feeBP: MINT_FEE_BP
        });

        MintLogic.MintOutputs memory outputs = MintLogic.evaluate(inputs);
        assertTrue(outputs.btdToMint > 0, "Should mint some BTD for small amount");
    }

    function test_collateralRatio_veryHighWBTCPrice() public pure {
        uint256 cr = CollateralMath.collateralRatio(
            1e8,
            1000000e18, // $1M per BTC
            100000e18,
            0,
            IUSD_PRICE
        );

        assertEq(cr, 10e18, "CR should be 1000%");
    }

    function test_collateralRatio_veryLowWBTCPrice() public pure {
        uint256 cr = CollateralMath.collateralRatio(
            1e8,
            1000e18, // $1000 per BTC
            100000e18,
            0,
            IUSD_PRICE
        );

        assertEq(cr, 0.01e18, "CR should be 1%");
    }
}
