// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../../contracts/ConfigGov.sol";
import "../../contracts/IdealUSDManager.sol";
import "../../contracts/PriceOracle.sol";
import "../../contracts/Treasury.sol";
import "../../contracts/Minter.sol";
import "../../contracts/InterestPool.sol";
import "../../contracts/FarmingPool.sol";

/// @title ProxyTestHelper - Deploy upgradeable contracts behind ERC1967 proxies
/// @notice Used in tests to deploy UUPS-upgradeable contracts via proxy
library ProxyTestHelper {

    function deployConfigGov(address owner) internal returns (ConfigGov) {
        ConfigGov impl = new ConfigGov();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(ConfigGov.initialize, (owner))
        );
        return ConfigGov(address(proxy));
    }

    function deployIdealUSDManager(
        address owner,
        address configGov,
        uint256 initialIUSD
    ) internal returns (IdealUSDManager) {
        IdealUSDManager impl = new IdealUSDManager();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(IdealUSDManager.initialize, (owner, configGov, initialIUSD))
        );
        return IdealUSDManager(address(proxy));
    }

    function deployPriceOracle(
        address owner,
        address core,
        address gov,
        address twapOracle,
        bytes32 pythPriceId
    ) internal returns (PriceOracle) {
        PriceOracle impl = new PriceOracle();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(PriceOracle.initialize, (owner, core, gov, twapOracle, pythPriceId))
        );
        return PriceOracle(address(proxy));
    }

    function deployTreasury(
        address owner,
        address core,
        address router
    ) internal returns (Treasury) {
        Treasury impl = new Treasury();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(Treasury.initialize, (owner, core, router))
        );
        return Treasury(payable(address(proxy)));
    }

    function deployMinter(
        address owner,
        address core,
        address gov
    ) internal returns (Minter) {
        Minter impl = new Minter();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(Minter.initialize, (owner, core, gov))
        );
        return Minter(address(proxy));
    }

    function deployInterestPool(
        address owner,
        address core,
        address gov,
        address rateOracle
    ) internal returns (InterestPool) {
        InterestPool impl = new InterestPool();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(InterestPool.initialize, (owner, core, gov, rateOracle))
        );
        return InterestPool(address(proxy));
    }

    function deployFarmingPool(
        address owner,
        address rewardToken,
        address core,
        address[] memory funds,
        uint256[] memory shares
    ) internal returns (FarmingPool) {
        FarmingPool impl = new FarmingPool();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(impl),
            abi.encodeCall(FarmingPool.initialize, (owner, rewardToken, core, funds, shares))
        );
        return FarmingPool(address(proxy));
    }
}
