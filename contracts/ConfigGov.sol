// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import "./libraries/Constants.sol";

/**
 * @title ConfigGov - Governable Parameter Configuration Contract
 * @notice Manages runtime-adjustable system parameters (fees, limits, oracle addresses, etc.)
 * @dev Separated from ConfigCore: Core manages immutable addresses, Gov manages mutable parameters
 *      Governance logic can be upgraded without affecting core architecture
 */
contract ConfigGov is Ownable2Step {

    /**
     * @notice Parameter type enum (uint256 type)
     * @dev Used for unified management of all system parameters, supports unlimited extension
     */
    enum ParamType {
        MintFeeBp,        // 0 - Minting fee rate (basis points)
        InterestFeeBp,    // 1 - Interest fee rate (basis points)
        MinBtbPrice,      // 2 - BTB minimum price (18 decimals)
        MaxBtbRate,       // 3 - BTB maximum interest rate (basis points)
        PceMaxDeviation,  // 4 - PCE maximum deviation rate (18 decimals, e.g., 2e16 = 2%)
        RedeemFeeBp,      // 5 - Redemption fee rate (basis points)
        MaxBtdRate,       // 6 - BTD maximum interest rate (basis points)
        BaseRateDefault   // 7 - Default base interest rate (basis points, e.g., 500 = 5%)
    }

    /**
     * @notice Address parameter type enum
     * @dev Used for managing governable oracle addresses, external contract addresses, etc.
     */
    enum AddressParamType {
        PceFeed,           // 0 - Chainlink PCE oracle
        ChainlinkBtcUsd,   // 1 - Chainlink BTC/USD feed
        ChainlinkWbtcBtc,  // 2 - Chainlink WBTC/BTC feed
        PythWbtc,          // 3 - Pyth WBTC feed
        ChainlinkUsdcUsd,  // 4 - Chainlink USDC/USD feed
        ChainlinkUsdtUsd   // 5 - Chainlink USDT/USD feed
    }

    // ============ Storage ============

    /// @notice Unified parameter registry (governable fees, limits, and other parameters)
    mapping(ParamType => uint256) private _params;

    /// @notice Address parameter registry (governable oracle addresses, etc.)
    mapping(AddressParamType => address) private _addressParams;

    /// @notice DAO governance contract address (upgradable)
    address private _governor;

    // ============ Events ============

    /// @notice Generic parameter update event (uint256 type)
    event ParamUpdated(ParamType indexed paramType, uint256 newValue);

    /// @notice Address parameter update event
    event AddressParamUpdated(AddressParamType indexed paramType, address newValue);

    /// @notice Governor address update event
    event GovernorUpdated(address indexed oldGovernor, address indexed newGovernor);

    // ============ Initialization ============

    /**
     * @notice Constructor - initializes governance parameters with defaults
     * @param initialOwner Contract owner address
     * @dev Sets default values:
     *      - MINT_FEE_BP: 50 bps (0.5%)
     *      - REDEEM_FEE_BP: 50 bps (0.5%)
     *      - INTEREST_FEE_BP: 500 bps (5%)
     */
    constructor(
        address initialOwner
    ) Ownable(initialOwner) {
        require(initialOwner != address(0), "ConfigGov: zero owner");

        // Initialize default fee parameters
        _params[ParamType.MintFeeBp] = 50;       // 0.5% minting fee
        _params[ParamType.RedeemFeeBp] = 50;     // 0.5% redemption fee
        _params[ParamType.InterestFeeBp] = 500;  // 5% interest fee
        _params[ParamType.BaseRateDefault] = 500; // 5% default base interest rate
    }

    // ============ Parameter Management ============

    /**
     * @notice Sets a single system parameter
     * @dev Only owner can call, used for updating fees, price limits, and other parameters
     * @param paramType Parameter type (from ParamType enum)
     * @param value New parameter value
     */
    function setParam(ParamType paramType, uint256 value) external onlyOwner {
        // Parameter range validation
        _validateParam(paramType, value);

        _params[paramType] = value;
        emit ParamUpdated(paramType, value);
    }

    /**
     * @notice Validates parameter range
     * @dev Internal function to ensure parameters are within reasonable bounds
     * @param paramType Parameter type
     * @param value Parameter value
     */
    function _validateParam(ParamType paramType, uint256 value) private pure {
        if (paramType == ParamType.MintFeeBp) {
            // Range: 0-1000 bps (0%-10%), default 50 bps (0.5%)
            require(value <= 1000, "ConfigGov: mint fee too high"); // Maximum 10%
        } else if (paramType == ParamType.InterestFeeBp) {
            // Range: 0-2000 bps (0%-20%), default 500 bps (5%)
            require(value <= 2000, "ConfigGov: interest fee too high"); // Maximum 20%
        } else if (paramType == ParamType.RedeemFeeBp) {
            // Range: 0-1000 bps (0%-10%), default 50 bps (0.5%)
            require(value <= 1000, "ConfigGov: redeem fee too high"); // Maximum 10%
        } else if (paramType == ParamType.MinBtbPrice) {
            require(value >= 1e17, "ConfigGov: min BTB price too low"); // Minimum 0.1 BTD
            require(value <= 1e18, "ConfigGov: min BTB price too high"); // Maximum 1 BTD
        } else if (paramType == ParamType.MaxBtbRate) {
            require(value >= 100, "ConfigGov: max BTB rate too low"); // Minimum 1% APR (100 bps)
            require(value <= 3000, "ConfigGov: max BTB rate too high"); // Maximum 30% APR (3000 bps)
        } else if (paramType == ParamType.MaxBtdRate) {
            require(value >= 100, "ConfigGov: max BTD rate too low"); // Minimum 1% APR (100 bps)
            require(value <= 3000, "ConfigGov: max BTD rate too high"); // Maximum 30% APR (3000 bps)
        } else if (paramType == ParamType.PceMaxDeviation) {
            require(value >= 1e15, "ConfigGov: PCE deviation too low"); // Minimum 0.1%
            require(value <= 1e17, "ConfigGov: PCE deviation too high"); // Maximum 10%
        } else if (paramType == ParamType.BaseRateDefault) {
            require(value >= 100, "ConfigGov: base rate too low"); // Minimum 1% APR (100 bps)
            require(value <= 1000, "ConfigGov: base rate too high"); // Maximum 10% APR (1000 bps)
        }
    }

    /**
     * @notice Batch sets multiple system parameters
     * @dev Only owner can call, array lengths must be equal
     * @param paramTypes Parameter type array
     * @param values Corresponding new parameter value array
     */
    function setParamsBatch(
        ParamType[] calldata paramTypes,
        uint256[] calldata values
    ) external onlyOwner {
        require(paramTypes.length == values.length, "ConfigGov: length mismatch");
        for (uint i = 0; i < paramTypes.length; i++) {
            // Parameter range validation
            _validateParam(paramTypes[i], values[i]);

            _params[paramTypes[i]] = values[i];
            emit ParamUpdated(paramTypes[i], values[i]);
        }
    }

    /**
     * @notice Gets the value of a specified system parameter type
     * @dev Returns 0 if the parameter is not set
     * @param paramType Parameter type
     * @return Parameter value
     */
    function getParam(ParamType paramType) external view returns (uint256) {
        return _params[paramType];
    }

    // ============ Convenience Access Functions ============

    /**
     * @notice Gets the minting fee rate
     * @return Minting fee rate (basis points, e.g., 50 = 0.5%)
     */
    function mintFeeBP() external view returns (uint256) {
        return _params[ParamType.MintFeeBp];
    }

    function interestFeeBP() external view returns (uint256) {
        return _params[ParamType.InterestFeeBp];
    }

    function minBTBPrice() external view returns (uint256) {
        return _params[ParamType.MinBtbPrice];
    }

    function maxBTBRate() external view returns (uint256) {
        return _params[ParamType.MaxBtbRate];
    }

    /**
     * @notice Gets BTD maximum interest rate
     * @dev Used to cap BTD deposit rate per whitepaper
     * @return BTD maximum interest rate (basis points, e.g., 2000 = 20%)
     */
    function maxBTDRate() external view returns (uint256) {
        return _params[ParamType.MaxBtdRate];
    }

    /**
     * @notice Gets PCE maximum deviation rate
     * @dev Used to prevent abnormal PCE data fluctuations
     * @return PCE maximum deviation rate (18 decimals, e.g., 2e16 = 2%)
     */
    function pceMaxDeviation() external view returns (uint256) {
        return _params[ParamType.PceMaxDeviation];
    }

    /**
     * @notice Gets the redemption fee rate
     * @dev Fee deducted from user when redeeming BTD
     * @return Redemption fee rate (basis points, e.g., 50 = 0.5%)
     */
    function redeemFeeBP() external view returns (uint256) {
        return _params[ParamType.RedeemFeeBp];
    }

    /**
     * @notice Gets the default base interest rate
     * @dev Used as anchor for BTD/BTB rate calculations when CR = 100%
     * @return Default base rate (basis points, e.g., 500 = 5%)
     */
    function baseRateDefault() external view returns (uint256) {
        return _params[ParamType.BaseRateDefault];
    }

    // ============ Address Parameter Management ============

    /**
     * @notice Sets a single address parameter
     * @dev Only owner can call, used for updating oracle addresses, etc.
     * @param paramType Address parameter type (from AddressParamType enum)
     * @param value New address value
     */
    function setAddressParam(AddressParamType paramType, address value) external onlyOwner {
        require(value != address(0), "ConfigGov: zero address");
        _addressParams[paramType] = value;
        emit AddressParamUpdated(paramType, value);
    }

    /**
     * @notice Batch sets multiple address parameters
     * @dev Only owner can call, array lengths must be equal
     * @param paramTypes Address parameter type array
     * @param values Corresponding new address value array
     */
    function setAddressParamsBatch(
        AddressParamType[] calldata paramTypes,
        address[] calldata values
    ) external onlyOwner {
        require(paramTypes.length == values.length, "ConfigGov: length mismatch");
        for (uint i = 0; i < paramTypes.length; i++) {
            require(values[i] != address(0), "ConfigGov: zero address");
            _addressParams[paramTypes[i]] = values[i];
            emit AddressParamUpdated(paramTypes[i], values[i]);
        }
    }

    /**
     * @notice Gets the value of a specified address parameter type
     * @dev Returns address(0) if the parameter is not set
     * @param paramType Address parameter type
     * @return Address value
     */
    function getAddressParam(AddressParamType paramType) external view returns (address) {
        return _addressParams[paramType];
    }

    /**
     * @notice Gets PCE Feed oracle address
     * @return PCE Feed address
     */
    function pceFeed() external view returns (address) {
        return _addressParams[AddressParamType.PceFeed];
    }

    // ============ Oracle Address Convenience Functions ============

    function chainlinkBtcUsd() external view returns (address) {
        return _addressParams[AddressParamType.ChainlinkBtcUsd];
    }

    function chainlinkWbtcBtc() external view returns (address) {
        return _addressParams[AddressParamType.ChainlinkWbtcBtc];
    }

    function pythWbtc() external view returns (address) {
        return _addressParams[AddressParamType.PythWbtc];
    }

    function chainlinkUsdcUsd() external view returns (address) {
        return _addressParams[AddressParamType.ChainlinkUsdcUsd];
    }

    function chainlinkUsdtUsd() external view returns (address) {
        return _addressParams[AddressParamType.ChainlinkUsdtUsd];
    }

    // ============ Governor Management ============

    /**
     * @notice Sets the DAO governance contract address
     * @dev Only owner can call, allows governance upgrades
     * @param newGovernor New governor contract address
     */
    function setGovernor(address newGovernor) external onlyOwner {
        require(newGovernor != address(0), "ConfigGov: zero governor");
        address oldGovernor = _governor;
        _governor = newGovernor;
        emit GovernorUpdated(oldGovernor, newGovernor);
    }

    /**
     * @notice Gets the current DAO governance contract address
     * @return Current governor address
     */
    function governor() external view returns (address) {
        return _governor;
    }
}
