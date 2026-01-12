// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import "./libraries/Constants.sol";

/// @title ConfigGov - Governable Parameter Configuration Contract
/// @notice Manages runtime-adjustable system parameters (fees, limits, oracle addresses)
contract ConfigGov is Ownable2Step {

    /// @notice Parameter type enum for uint256 values
    enum ParamType {
        MintFeeBp,        // Minting fee (basis points)
        InterestFeeBp,    // Interest fee (basis points)
        MinBtbPrice,      // BTB minimum price (18 decimals)
        MaxBtbRate,       // BTB max interest rate (basis points)
        PceMaxDeviation,  // PCE max deviation (18 decimals)
        RedeemFeeBp,      // Redemption fee (basis points)
        MaxBtdRate,       // BTD max interest rate (basis points)
        BaseRateDefault   // Default base rate (basis points)
    }

    /// @notice Address parameter type enum
    enum AddressParamType {
        PceFeed,           // Chainlink PCE oracle
        ChainlinkBtcUsd,   // Chainlink BTC/USD feed
        ChainlinkWbtcBtc,  // Chainlink WBTC/BTC feed
        PythWbtc,          // Pyth WBTC feed
        ChainlinkUsdcUsd,  // Chainlink USDC/USD feed
        ChainlinkUsdtUsd   // Chainlink USDT/USD feed
    }

    // ============ Storage ============

    mapping(ParamType => uint256) private _params;
    mapping(AddressParamType => address) private _addressParams;
    address private _governor;

    // ============ Events ============

    event ParamUpdated(ParamType indexed paramType, uint256 newValue);
    event AddressParamUpdated(AddressParamType indexed paramType, address newValue);
    event GovernorUpdated(address indexed oldGovernor, address indexed newGovernor);

    // ============ Initialization ============

    /// @notice Initializes governance parameters with defaults (0.5% mint/redeem fee, 5% interest fee)
    constructor(address initialOwner) Ownable(initialOwner) {
        require(initialOwner != address(0), "ConfigGov: zero owner");
        _params[ParamType.MintFeeBp] = 50;
        _params[ParamType.RedeemFeeBp] = 50;
        _params[ParamType.InterestFeeBp] = 500;
        _params[ParamType.BaseRateDefault] = 500;
    }

    // ============ Parameter Management ============

    /// @notice Sets a single system parameter
    /// @param paramType Parameter type from ParamType enum
    /// @param value New parameter value
    function setParam(ParamType paramType, uint256 value) external onlyOwner {
        _validateParam(paramType, value);
        _params[paramType] = value;
        emit ParamUpdated(paramType, value);
    }

    function _validateParam(ParamType paramType, uint256 value) private pure {
        if (paramType == ParamType.MintFeeBp) {
            require(value <= 1000, "ConfigGov: mint fee too high");
        } else if (paramType == ParamType.InterestFeeBp) {
            require(value <= 2000, "ConfigGov: interest fee too high");
        } else if (paramType == ParamType.RedeemFeeBp) {
            require(value <= 1000, "ConfigGov: redeem fee too high");
        } else if (paramType == ParamType.MinBtbPrice) {
            require(value >= 1e17, "ConfigGov: min BTB price too low");
            require(value <= 1e18, "ConfigGov: min BTB price too high");
        } else if (paramType == ParamType.MaxBtbRate) {
            require(value >= 100, "ConfigGov: max BTB rate too low");
            require(value <= 3000, "ConfigGov: max BTB rate too high");
        } else if (paramType == ParamType.MaxBtdRate) {
            require(value >= 100, "ConfigGov: max BTD rate too low");
            require(value <= 3000, "ConfigGov: max BTD rate too high");
        } else if (paramType == ParamType.PceMaxDeviation) {
            require(value >= 1e15, "ConfigGov: PCE deviation too low");
            require(value <= 1e17, "ConfigGov: PCE deviation too high");
        } else if (paramType == ParamType.BaseRateDefault) {
            require(value >= 100, "ConfigGov: base rate too low");
            require(value <= 1000, "ConfigGov: base rate too high");
        }
    }

    /// @notice Batch sets multiple system parameters
    function setParamsBatch(ParamType[] calldata paramTypes, uint256[] calldata values) external onlyOwner {
        require(paramTypes.length == values.length, "ConfigGov: length mismatch");
        for (uint i = 0; i < paramTypes.length; i++) {
            _validateParam(paramTypes[i], values[i]);
            _params[paramTypes[i]] = values[i];
            emit ParamUpdated(paramTypes[i], values[i]);
        }
    }

    /// @notice Gets the value of a specified parameter type (returns 0 if not set)
    function getParam(ParamType paramType) external view returns (uint256) {
        return _params[paramType];
    }

    // ============ Convenience Access Functions ============

    function mintFeeBP() external view returns (uint256) { return _params[ParamType.MintFeeBp]; }
    function interestFeeBP() external view returns (uint256) { return _params[ParamType.InterestFeeBp]; }
    function minBTBPrice() external view returns (uint256) { return _params[ParamType.MinBtbPrice]; }
    function maxBTBRate() external view returns (uint256) { return _params[ParamType.MaxBtbRate]; }
    function maxBTDRate() external view returns (uint256) { return _params[ParamType.MaxBtdRate]; }
    function pceMaxDeviation() external view returns (uint256) { return _params[ParamType.PceMaxDeviation]; }
    function redeemFeeBP() external view returns (uint256) { return _params[ParamType.RedeemFeeBp]; }
    function baseRateDefault() external view returns (uint256) { return _params[ParamType.BaseRateDefault]; }

    // ============ Address Parameter Management ============

    /// @notice Sets a single address parameter
    function setAddressParam(AddressParamType paramType, address value) external onlyOwner {
        require(value != address(0), "ConfigGov: zero address");
        _addressParams[paramType] = value;
        emit AddressParamUpdated(paramType, value);
    }

    /// @notice Batch sets multiple address parameters
    function setAddressParamsBatch(AddressParamType[] calldata paramTypes, address[] calldata values) external onlyOwner {
        require(paramTypes.length == values.length, "ConfigGov: length mismatch");
        for (uint i = 0; i < paramTypes.length; i++) {
            require(values[i] != address(0), "ConfigGov: zero address");
            _addressParams[paramTypes[i]] = values[i];
            emit AddressParamUpdated(paramTypes[i], values[i]);
        }
    }

    /// @notice Gets the value of a specified address parameter (returns address(0) if not set)
    function getAddressParam(AddressParamType paramType) external view returns (address) {
        return _addressParams[paramType];
    }

    function pceFeed() external view returns (address) { return _addressParams[AddressParamType.PceFeed]; }

    // ============ Oracle Address Convenience Functions ============

    function chainlinkBtcUsd() external view returns (address) { return _addressParams[AddressParamType.ChainlinkBtcUsd]; }
    function chainlinkWbtcBtc() external view returns (address) { return _addressParams[AddressParamType.ChainlinkWbtcBtc]; }
    function pythWbtc() external view returns (address) { return _addressParams[AddressParamType.PythWbtc]; }
    function chainlinkUsdcUsd() external view returns (address) { return _addressParams[AddressParamType.ChainlinkUsdcUsd]; }
    function chainlinkUsdtUsd() external view returns (address) { return _addressParams[AddressParamType.ChainlinkUsdtUsd]; }

    // ============ Governor Management ============

    /// @notice Sets the DAO governance contract address
    function setGovernor(address newGovernor) external onlyOwner {
        require(newGovernor != address(0), "ConfigGov: zero governor");
        address oldGovernor = _governor;
        _governor = newGovernor;
        emit GovernorUpdated(oldGovernor, newGovernor);
    }

    function governor() external view returns (address) { return _governor; }
}
