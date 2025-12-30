// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ConfirmedOwner} from "@chainlink/contracts/src/v0.8/shared/access/ConfirmedOwner.sol";
import {IIdealUSDManager} from "./interfaces/IIdealUSDManager.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {ConfigGov} from "./ConfigGov.sol";
import "./libraries/Constants.sol";
import "./libraries/OracleMath.sol";
import "./libraries/IUSDMath.sol";
import "./libraries/FeedValidation.sol";

/**
 * @title IdealUSDManager - Ideal USD Manager
 * @notice Manages IUSD (Ideal USD), automatically adjusts based on fixed 2% annual inflation rate
 * @dev IUSD = IUSD x (current month PCE / previous month PCE) / monthlyGrowthFactor
 * @dev Non-upgradeable contract - core parameters are fixed after deployment, as per whitepaper requirements
 * @dev Inflation parameters use Constants library constants (ANNUAL_INFLATION_RATE, MONTHLY_GROWTH_FACTOR)
 * @dev PCE Feed address is dynamically retrieved from ConfigGov, supports governance replacement
 */
contract IdealUSDManager is ConfirmedOwner, IIdealUSDManager {

    // ============ Immutable State ============

    /// @notice ConfigGov contract address
    /// @dev Cannot be changed after deployment, used to get governable PCE Feed address
    ConfigGov public immutable configGov;

    // ============ Mutable State ============

    /// @notice Current IUSD value (18 decimals)
    uint256 public iusdValue;

    /// @notice Timestamp of most recent update
    uint256 public lastUpdateTime;

    /// @notice Timestamp of most recent PCE read
    /// @dev Using uint64 to avoid year 2106 overflow issue (usable until year 584,942,417,355)
    uint64 public lastPCEUpdateTime;

    /// @notice Most recent PCE value (18 decimals)
    uint256 public lastPCEValue;

    /// @notice Previous PCE value (18 decimals)
    uint256 public previousPCEValue;

    // Authorized addresses (optional, disabled by default)
    mapping(address => bool) public authorizedUpdaters;
    bool public updaterWhitelistEnabled;

    // Manual override safety controls
    uint256 public lastManualOverrideTime;           // Last manual override timestamp
    uint256 public constant MIN_OVERRIDE_INTERVAL = 7 days;  // Minimum override interval (7 days)
    uint256 public constant MAX_MANUAL_DEVIATION = 5e16;     // Maximum manual deviation (5% = 0.05)
    uint256 public manualOverrideCount;              // Manual override count for auditing

    // History records
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

    /// @notice Updater whitelist change
    event UpdaterAuthorized(address indexed updater, bool authorized);
    event IUSDManuallySet(
        uint256 indexed timestamp,
        uint256 oldValue,
        uint256 newValue,
        address indexed setter,
        string reason
    );

    /**
     * @notice Constructor - initializes IUSD manager
     * @dev Uses fixed 2% annual inflation rate and monthly growth multiplier from Constants library
     * @dev Monthly growth multiplier = (1.02)^(1/12) = 1.001651581301920174
     * @dev PCE Feed address is dynamically retrieved from ConfigGov, ConfigGov must be configured at deployment
     */
    constructor(
        address _owner,                  // Contract owner address
        address _configGov,              // ConfigGov contract address
        uint256 _initialIUSD             // Initial IUSD value (18 decimals, e.g., 1e18 = 1.0)
    ) ConfirmedOwner(_owner) {
        require(_configGov != address(0), "Invalid ConfigGov");
        require(_initialIUSD > 0, "Invalid initial value");

        // Set immutable parameters
        configGov = ConfigGov(_configGov);

        // Verify PCE Feed is configured
        address pceFeedAddr = configGov.pceFeed();
        require(pceFeedAddr != address(0), "PCE Feed not set in ConfigGov");

        // Set mutable state
        iusdValue = _initialIUSD;
        lastUpdateTime = block.timestamp;
        lastPCEUpdateTime = uint64(block.timestamp);

        // Authorize deployer
        authorizedUpdaters[_owner] = true;
    }

    /**
     * @notice Updates IUSD value (automatically adjusts based on PCE data)
     * @dev Retrieves latest data from Chainlink PCE Feed and adjusts IUSD based on inflation rate
     * @dev Access control: default is owner only; when updaterWhitelist is enabled, requires whitelist authorization
     * @dev Formula: IUSD = IUSD x (current month PCE / previous month PCE) / monthlyGrowthFactor
     */
    function updateIUSD() external {
        require(isUpdaterAuthorized(msg.sender), "Not authorized");

        // Get data from PCE data source
        (uint256 currentPCE, uint256 previousPCE) = _pullPCEData();
        uint256 oldIUSD = iusdValue;

        (uint256 actualInflationMultiplier, uint256 adjustmentFactor) =
            IUSDMath.adjustmentFactor(currentPCE, previousPCE, Constants.MONTHLY_GROWTH_FACTOR);

        // Update IUSD: IUSD = IUSD x adjustment factor
        iusdValue = (iusdValue * adjustmentFactor) / Constants.PRECISION_18;
        lastUpdateTime = block.timestamp;

        // Calculate actual monthly inflation rate (for event)
        uint256 actualMonthlyRate = actualInflationMultiplier > Constants.PRECISION_18 ?
            actualInflationMultiplier - Constants.PRECISION_18 : 0;

        // Record history
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
            Constants.MONTHLY_GROWTH_FACTOR - Constants.PRECISION_18, // Convert to monthly growth rate format
            adjustmentFactor
        );
    }

    /**
     * @notice Minimum interval for lazy IUSD updates (25 days)
     * @dev PCE is published monthly, 25 days ensures at most one update per month
     */
    uint256 public constant MIN_LAZY_UPDATE_INTERVAL = 25 days;

    /**
     * @notice Tries to update IUSD if enough time has passed (lazy update)
     * @dev Can be called by anyone, but only executes if MIN_LAZY_UPDATE_INTERVAL has passed
     * @dev Designed to be called by Minter during user operations (mint/redeem)
     * @dev Silently returns if update conditions not met or PCE feed fails
     * @return updated True if IUSD was actually updated
     */
    function tryUpdateIUSD() external returns (bool updated) {
        // Only update if enough time has passed since last update
        if (block.timestamp < lastUpdateTime + MIN_LAZY_UPDATE_INTERVAL) {
            return false;
        }

        // Try to pull PCE data and update - silently fail if PCE feed unavailable
        try this.updateIUSDInternal() {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice Internal update function callable only by this contract
     * @dev Used by tryUpdateIUSD() to enable try-catch pattern
     */
    function updateIUSDInternal() external {
        require(msg.sender == address(this), "Only internal call");

        // Get data from PCE data source
        (uint256 currentPCE, uint256 previousPCE) = _pullPCEData();
        uint256 oldIUSD = iusdValue;

        (uint256 actualInflationMultiplier, uint256 adjustmentFactor) =
            IUSDMath.adjustmentFactor(currentPCE, previousPCE, Constants.MONTHLY_GROWTH_FACTOR);

        // Update IUSD: IUSD = IUSD x adjustment factor
        iusdValue = (iusdValue * adjustmentFactor) / Constants.PRECISION_18;
        lastUpdateTime = block.timestamp;

        // Calculate actual monthly inflation rate (for event)
        uint256 actualMonthlyRate = actualInflationMultiplier > Constants.PRECISION_18 ?
            actualInflationMultiplier - Constants.PRECISION_18 : 0;

        // Record history
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

    /**
     * @notice Queries whether an address has IUSD update permission
     * @dev If whitelist is not enabled, only owner has permission; when whitelist is enabled, checks authorization list
     * @param updater Address to query
     * @return Whether has update permission
     */
    function isUpdaterAuthorized(address updater) public view returns (bool) {
        if (!updaterWhitelistEnabled) {
            return updater == owner();
        }
        return authorizedUpdaters[updater] || updater == owner();
    }

    /**
     * @notice Authorizes or revokes updater permission for specified address
     * @dev Only owner can call, used for managing IUSD update permission whitelist
     * @param updater Address to authorize
     * @param authorized true=authorize, false=revoke
     */
    function setUpdaterAuthorization(address updater, bool authorized) external onlyOwner {
        authorizedUpdaters[updater] = authorized;
        emit UpdaterAuthorized(updater, authorized);
    }

    /**
     * @notice Enables or disables updater whitelist mechanism
     * @dev Only owner can call, disabled by default (only owner can update)
     * @param enabled true=enable whitelist verification, false=only owner can update
     */
    function setUpdaterWhitelistEnabled(bool enabled) external onlyOwner {
        updaterWhitelistEnabled = enabled;
    }

    /**
     * @notice Manually sets IUSD value (for emergency use) - enhanced security version
     * @param _newIUSDValue New IUSD value (18 decimals)
     * @param _reason Reason for setting (minimum 20 characters)
     * @dev Only owner can call, for the following scenarios:
     *      1. PCE Feed retrieval failed, manual correction needed
     *      2. updateIUSD() execution failed, emergency adjustment needed
     *      3. Historical data error found, retroactive correction needed
     *
     *      Enhanced security restrictions:
     *      - New value cannot be 0
     *      - Deviation between new value and current value cannot exceed +/-5% (reduced from 10%)
     *      - Must wait at least 7 days between manual overrides
     *      - Detailed reason required (minimum 20 characters)
     *      - Override count recorded for auditing
     *
     *      Example:
     *      Monthly PCE not updated in time, theoretical IUSD should be 1.05, but system still shows 1.04
     *      Call setIUSDValue(1.05e18, "Manual correction for missed PCE update on 2025-01-15")
     */
    function setIUSDValue(uint256 _newIUSDValue, string calldata _reason) external onlyOwner {
        require(_newIUSDValue > 0, "IUSD value must be positive");
        require(bytes(_reason).length >= 20, "Reason must be at least 20 characters");

        uint256 oldValue = iusdValue;

        // Timelock check: must wait at least 7 days between manual overrides
        if (lastManualOverrideTime > 0) {
            require(
                block.timestamp >= lastManualOverrideTime + MIN_OVERRIDE_INTERVAL,
                "Must wait 7 days between manual overrides"
            );
        }

        // Safety check: prevent misoperation, deviation between new and old value cannot exceed +/-5% (reduced from 10%)
        uint256 deviation;
        if (_newIUSDValue > oldValue) {
            deviation = ((_newIUSDValue - oldValue) * Constants.PRECISION_18) / oldValue;
        } else {
            deviation = ((oldValue - _newIUSDValue) * Constants.PRECISION_18) / oldValue;
        }
        require(
            deviation <= MAX_MANUAL_DEVIATION,
            "Deviation exceeds 5% limit"
        );

        // Update IUSD value
        iusdValue = _newIUSDValue;
        lastUpdateTime = block.timestamp;
        lastManualOverrideTime = block.timestamp;
        manualOverrideCount++;

        // Record to history (with special marker)
        updateHistory.push(IUSDUpdate({
            timestamp: block.timestamp,
            oldValue: oldValue,
            newValue: _newIUSDValue,
            currentPCE: 0,        // PCE is 0 for manual setting (marker)
            previousPCE: 0,       // PCE is 0 for manual setting (marker)
            actualMonthlyRate: 0,
            adjustmentFactor: (_newIUSDValue * Constants.PRECISION_18) / oldValue  // Actual adjustment multiplier
        }));

        // Emit event
        emit IUSDManuallySet(
            block.timestamp,
            oldValue,
            _newIUSDValue,
            msg.sender,
            _reason
        );
    }

    // Query functions

    /**
     * @notice Gets current IUSD value
     * @dev Returns inflation-adjusted ideal USD price
     * @return Current IUSD value (18 decimals)
     */
    function getCurrentIUSD() external view returns (uint256) {
        return iusdValue;
    }

    /**
     * @notice Gets inflation parameter configuration
     * @dev Returns annual inflation rate and monthly growth multiplier (from Constants library constants)
     * @dev Monthly growth rate = monthlyFactor - 1e18, example: 1.001653e18 -> 0.1653%
     * @return annual Annual inflation rate (18 decimals, e.g., 2e16 = 2%)
     * @return monthlyFactor Monthly growth multiplier (18 decimals, e.g., 1.001653e18)
     */
    function getInflationParameters() external pure returns (uint256 annual, uint256 monthlyFactor) {
        return (Constants.ANNUAL_INFLATION_RATE, Constants.MONTHLY_GROWTH_FACTOR);
    }

    /**
     * @notice Gets current PCE Feed address
     * @dev Dynamically reads from ConfigGov, supports governance replacement
     * @return PCE Feed oracle address
     */
    function pceFeed() external view returns (address) {
        return configGov.pceFeed();
    }

    /**
     * @notice Gets current PCE Feed decimals
     * @dev Dynamically reads from PCE Feed contract, no storage needed
     * @return PCE Feed decimal places
     */
    function pceFeedDecimals() external view returns (uint8) {
        address pceFeedAddr = configGov.pceFeed();
        require(pceFeedAddr != address(0), "PCE Feed not configured");
        return IAggregatorV3(pceFeedAddr).decimals();
    }

    /**
     * @notice Gets IUSD update history record count
     * @dev Returns updateHistory array length
     * @return History record count
     */
    function getUpdateHistoryLength() external view returns (uint256) {
        return updateHistory.length;
    }

    /**
     * @notice Gets most recent IUSD update record
     * @dev Reverts if no update records exist
     * @return Most recent update record (includes timestamp, IUSD value, PCE data, etc.)
     */
    function getLatestUpdate() external view returns (IUSDUpdate memory) {
        require(updateHistory.length > 0, "No updates yet");
        return updateHistory[updateHistory.length - 1];
    }

    /**
     * @notice Formats IUSD information for display (human readable)
     * @dev Returns formatted string with current IUSD value and target inflation rate
     * @return Formatted string, e.g., "IUSD: 1.050 Target: 2.00%"
     */
    function getFormattedInfo() external view returns (string memory) {
        uint256 iusdFormatted = iusdValue / 1e15; // Convert to 3 decimal display
        uint256 targetPercent = Constants.ANNUAL_INFLATION_RATE / 1e14; // Convert to percentage display (2 decimals)

        return string(abi.encodePacked(
            "IUSD: ", _toString(iusdFormatted / 1000), ".", _toString(iusdFormatted % 1000),
            " Target: ", _toString(targetPercent / 100), ".", _toString(targetPercent % 100), "%"
        ));
    }

    /**
     * @notice Internal function to get PCE data from Chainlink
     * @dev Reads latest PCE value and updates history, uses current value as previous on first call to avoid division by zero
     * @dev PCE Feed address is dynamically retrieved from ConfigGov, supports governance replacement
     * @dev Validates PCE change rate does not exceed maximum deviation set in ConfigGov
     * @return currentPCE Current PCE value (18 decimals)
     * @return previousPCE Previous PCE value (18 decimals)
     */
    function _pullPCEData() private returns (uint256 currentPCE, uint256 previousPCE) {
        // Get current PCE Feed address from ConfigGov
        address pceFeedAddr = configGov.pceFeed();
        require(pceFeedAddr != address(0), "PCE Feed not configured");

        // Use PCE-specific reader with 35-day staleness (monthly macroeconomic data)
        currentPCE = FeedValidation.readPCEAggregator(pceFeedAddr);
        previousPCE = lastPCEValue;

        // For first update, use current value as previous to avoid division by zero and record baseline
        if (previousPCE == 0) {
            previousPCE = currentPCE;
        } else {
            // Validate PCE change rate does not exceed maximum deviation (prevent abnormal data)
            uint256 maxDeviation = configGov.pceMaxDeviation();
            if (maxDeviation > 0) {  // 0 means check disabled
                uint256 deviation;
                if (currentPCE > previousPCE) {
                    deviation = ((currentPCE - previousPCE) * Constants.PRECISION_18) / previousPCE;
                } else {
                    deviation = ((previousPCE - currentPCE) * Constants.PRECISION_18) / previousPCE;
                }
                require(
                    deviation <= maxDeviation,
                    "PCE deviation exceeds limit"
                );
            }
        }

        previousPCEValue = previousPCE;
        lastPCEValue = currentPCE;
        lastPCEUpdateTime = uint64(block.timestamp);
    }

    /**
     * @notice Internal helper function to convert uint256 to string
     * @dev Used for formatted output
     * @param value Value to convert
     * @return String representation
     */
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
