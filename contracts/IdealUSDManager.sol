// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IIdealUSDManager} from "./interfaces/IIdealUSDManager.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {ConfigGov} from "./ConfigGov.sol";
import "./libraries/Constants.sol";
import "./libraries/OracleMath.sol";
import "./libraries/IUSDMath.sol";
import "./libraries/FeedValidation.sol";

/**
 * @title IdealUSDManager
 * @notice Manages IUSD with 2% annual inflation rate adjustment based on PCE data
 * @dev IUSD = IUSD x (currentPCE / previousPCE) / monthlyGrowthFactor
 */
contract IdealUSDManager is Ownable2Step, IIdealUSDManager {

    // ============ Immutable State ============

    /// @notice ConfigGov contract for retrieving PCE Feed address
    ConfigGov public immutable configGov;

    // ============ Mutable State ============

    /// @notice Current IUSD value (18 decimals)
    uint256 public iusdValue;
    /// @notice Timestamp of most recent update
    uint256 public lastUpdateTime;
    /// @notice Timestamp of most recent PCE read (uint64 for extended range)
    uint64 public lastPCEUpdateTime;
    /// @notice Most recent PCE value (18 decimals)
    uint256 public lastPCEValue;
    /// @notice Previous PCE value (18 decimals)
    uint256 public previousPCEValue;

    // Authorized updaters (optional, disabled by default)
    mapping(address => bool) public authorizedUpdaters;
    bool public updaterWhitelistEnabled;

    // Manual override safety controls
    uint256 public lastManualOverrideTime;
    uint256 public constant MIN_OVERRIDE_INTERVAL = 7 days;
    uint256 public constant MAX_MANUAL_DEVIATION = 5e16; // 5%
    uint256 public manualOverrideCount;

    struct IUSDUpdate {
        uint256 timestamp;
        uint256 oldValue;
        uint256 newValue;
        uint256 currentPCE;
        uint256 previousPCE;
        uint256 actualMonthlyRate;
        uint256 adjustmentFactor;
    }

    IUSDUpdate[] public updateHistory;

    // Events
    event IUSDUpdated(
        uint256 indexed timestamp,
        uint256 oldValue,
        uint256 newValue,
        uint256 currentPCE,
        uint256 previousPCE,
        uint256 actualRate,
        uint256 targetRate,
        uint256 adjustmentFactor
    );
    event UpdaterAuthorized(address indexed updater, bool authorized);
    event IUSDManuallySet(
        uint256 indexed timestamp,
        uint256 oldValue,
        uint256 newValue,
        address indexed setter,
        string reason
    );

    /// @notice Initialize IUSD manager with ConfigGov and initial value
    constructor(
        address _owner,
        address _configGov,
        uint256 _initialIUSD
    ) Ownable(_owner) {
        require(_configGov != address(0), "Invalid ConfigGov");
        require(_initialIUSD > 0, "Invalid initial value");

        configGov = ConfigGov(_configGov);
        require(configGov.pceFeed() != address(0), "PCE Feed not set in ConfigGov");

        iusdValue = _initialIUSD;
        lastUpdateTime = block.timestamp;
        lastPCEUpdateTime = uint64(block.timestamp);
        authorizedUpdaters[_owner] = true;
    }

    /// @notice Update IUSD based on PCE data (authorized callers only)
    function updateIUSD() external {
        require(isUpdaterAuthorized(msg.sender), "Not authorized");

        (uint256 currentPCE, uint256 previousPCE) = _pullPCEData();
        uint256 oldIUSD = iusdValue;

        (uint256 actualInflationMultiplier, uint256 adjustmentFactor) =
            IUSDMath.adjustmentFactor(currentPCE, previousPCE, Constants.MONTHLY_GROWTH_FACTOR);

        iusdValue = (iusdValue * adjustmentFactor) / Constants.PRECISION_18;
        lastUpdateTime = block.timestamp;

        uint256 actualMonthlyRate = actualInflationMultiplier > Constants.PRECISION_18 ?
            actualInflationMultiplier - Constants.PRECISION_18 : 0;

        updateHistory.push(IUSDUpdate({
            timestamp: block.timestamp,
            oldValue: oldIUSD,
            newValue: iusdValue,
            currentPCE: currentPCE,
            previousPCE: previousPCE,
            actualMonthlyRate: actualMonthlyRate,
            adjustmentFactor: adjustmentFactor
        }));

        emit IUSDUpdated(
            block.timestamp,
            oldIUSD,
            iusdValue,
            currentPCE,
            previousPCE,
            actualMonthlyRate,
            Constants.MONTHLY_GROWTH_FACTOR - Constants.PRECISION_18,
            adjustmentFactor
        );
    }

    /// @notice Minimum interval for lazy updates (25 days, ensures at most one update per month)
    uint256 public constant MIN_LAZY_UPDATE_INTERVAL = 25 days;

    /// @notice Try to update IUSD if enough time has passed (callable by anyone)
    /// @return updated True if IUSD was actually updated
    function tryUpdateIUSD() external returns (bool updated) {
        if (block.timestamp < lastUpdateTime + MIN_LAZY_UPDATE_INTERVAL) {
            return false;
        }

        try this.updateIUSDInternal() {
            return true;
        } catch {
            return false;
        }
    }

    /// @notice Internal update function for try-catch pattern (only callable by this contract)
    function updateIUSDInternal() external {
        require(msg.sender == address(this), "Only internal call");

        (uint256 currentPCE, uint256 previousPCE) = _pullPCEData();
        uint256 oldIUSD = iusdValue;

        (uint256 actualInflationMultiplier, uint256 adjustmentFactor) =
            IUSDMath.adjustmentFactor(currentPCE, previousPCE, Constants.MONTHLY_GROWTH_FACTOR);

        iusdValue = (iusdValue * adjustmentFactor) / Constants.PRECISION_18;
        lastUpdateTime = block.timestamp;

        uint256 actualMonthlyRate = actualInflationMultiplier > Constants.PRECISION_18 ?
            actualInflationMultiplier - Constants.PRECISION_18 : 0;

        updateHistory.push(IUSDUpdate({
            timestamp: block.timestamp,
            oldValue: oldIUSD,
            newValue: iusdValue,
            currentPCE: currentPCE,
            previousPCE: previousPCE,
            actualMonthlyRate: actualMonthlyRate,
            adjustmentFactor: adjustmentFactor
        }));

        emit IUSDUpdated(
            block.timestamp,
            oldIUSD,
            iusdValue,
            currentPCE,
            previousPCE,
            actualMonthlyRate,
            Constants.MONTHLY_GROWTH_FACTOR - Constants.PRECISION_18,
            adjustmentFactor
        );
    }

    /// @notice Check if address has update permission
    function isUpdaterAuthorized(address updater) public view returns (bool) {
        if (!updaterWhitelistEnabled) {
            return updater == owner();
        }
        return authorizedUpdaters[updater] || updater == owner();
    }

    /// @notice Authorize or revoke updater permission (owner only)
    function setUpdaterAuthorization(address updater, bool authorized) external onlyOwner {
        authorizedUpdaters[updater] = authorized;
        emit UpdaterAuthorized(updater, authorized);
    }

    /// @notice Enable or disable updater whitelist (owner only)
    function setUpdaterWhitelistEnabled(bool enabled) external onlyOwner {
        updaterWhitelistEnabled = enabled;
    }

    /**
     * @notice Manually set IUSD value for emergency use (owner only)
     * @param _newIUSDValue New IUSD value (18 decimals)
     * @param _reason Reason for override (min 20 chars)
     * @dev Restrictions: max 5% deviation, 7-day cooldown between overrides
     */
    function setIUSDValue(uint256 _newIUSDValue, string calldata _reason) external onlyOwner {
        require(_newIUSDValue > 0, "IUSD value must be positive");
        require(bytes(_reason).length >= 20, "Reason must be at least 20 characters");

        uint256 oldValue = iusdValue;

        if (lastManualOverrideTime > 0) {
            require(
                block.timestamp >= lastManualOverrideTime + MIN_OVERRIDE_INTERVAL,
                "Must wait 7 days between manual overrides"
            );
        }

        uint256 deviation;
        if (_newIUSDValue > oldValue) {
            deviation = ((_newIUSDValue - oldValue) * Constants.PRECISION_18) / oldValue;
        } else {
            deviation = ((oldValue - _newIUSDValue) * Constants.PRECISION_18) / oldValue;
        }
        require(deviation <= MAX_MANUAL_DEVIATION, "Deviation exceeds 5% limit");

        iusdValue = _newIUSDValue;
        lastUpdateTime = block.timestamp;
        lastManualOverrideTime = block.timestamp;
        manualOverrideCount++;

        updateHistory.push(IUSDUpdate({
            timestamp: block.timestamp,
            oldValue: oldValue,
            newValue: _newIUSDValue,
            currentPCE: 0,
            previousPCE: 0,
            actualMonthlyRate: 0,
            adjustmentFactor: (_newIUSDValue * Constants.PRECISION_18) / oldValue
        }));

        emit IUSDManuallySet(block.timestamp, oldValue, _newIUSDValue, msg.sender, _reason);
    }

    // ============ Query Functions ============

    /// @notice Get current IUSD value (18 decimals)
    function getCurrentIUSD() external view returns (uint256) {
        return iusdValue;
    }

    /// @notice Get inflation parameters from Constants library
    /// @return annual Annual inflation rate (18 decimals, e.g., 2e16 = 2%)
    /// @return monthlyFactor Monthly growth multiplier (18 decimals)
    function getInflationParameters() external pure returns (uint256 annual, uint256 monthlyFactor) {
        return (Constants.ANNUAL_INFLATION_RATE, Constants.MONTHLY_GROWTH_FACTOR);
    }

    /// @notice Get current PCE Feed address from ConfigGov
    function pceFeed() external view returns (address) {
        return configGov.pceFeed();
    }

    /// @notice Get PCE Feed decimals
    function pceFeedDecimals() external view returns (uint8) {
        address pceFeedAddr = configGov.pceFeed();
        require(pceFeedAddr != address(0), "PCE Feed not configured");
        return IAggregatorV3(pceFeedAddr).decimals();
    }

    /// @notice Get update history count
    function getUpdateHistoryLength() external view returns (uint256) {
        return updateHistory.length;
    }

    /// @notice Get most recent update record
    function getLatestUpdate() external view returns (IUSDUpdate memory) {
        require(updateHistory.length > 0, "No updates yet");
        return updateHistory[updateHistory.length - 1];
    }

    /// @notice Get formatted IUSD info for display
    /// @return Formatted string, e.g., "IUSD: 1.050 Target: 2.00%"
    function getFormattedInfo() external view returns (string memory) {
        uint256 iusdFormatted = iusdValue / 1e15;
        uint256 targetPercent = Constants.ANNUAL_INFLATION_RATE / 1e14;

        return string(abi.encodePacked(
            "IUSD: ", _toString(iusdFormatted / 1000), ".", _toString(iusdFormatted % 1000),
            " Target: ", _toString(targetPercent / 100), ".", _toString(targetPercent % 100), "%"
        ));
    }

    /// @dev Pull PCE data from Chainlink, validate deviation, update history
    function _pullPCEData() private returns (uint256 currentPCE, uint256 previousPCE) {
        address pceFeedAddr = configGov.pceFeed();
        require(pceFeedAddr != address(0), "PCE Feed not configured");

        currentPCE = FeedValidation.readPCEAggregator(pceFeedAddr);
        previousPCE = lastPCEValue;

        if (previousPCE == 0) {
            previousPCE = currentPCE;
        } else {
            uint256 maxDeviation = configGov.pceMaxDeviation();
            if (maxDeviation > 0) {
                uint256 deviation;
                if (currentPCE > previousPCE) {
                    deviation = ((currentPCE - previousPCE) * Constants.PRECISION_18) / previousPCE;
                } else {
                    deviation = ((previousPCE - currentPCE) * Constants.PRECISION_18) / previousPCE;
                }
                require(deviation <= maxDeviation, "PCE deviation exceeds limit");
            }
        }

        previousPCEValue = previousPCE;
        lastPCEValue = currentPCE;
        lastPCEUpdateTime = uint64(block.timestamp);
    }

    /// @dev Convert uint256 to string for formatted output
    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
    }
}
