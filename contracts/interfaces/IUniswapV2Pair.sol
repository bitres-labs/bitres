// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/**
 * @title IUniswapV2Pair - Uniswap V2 trading pair interface
 * @notice Defines the standard interface for Uniswap V2 liquidity pools, including ERC20 functionality and AMM trading functionality
 */
interface IUniswapV2Pair {
    /**
     * @notice Emitted when allowance changes
     * @param owner Token owner
     * @param spender Approved spender
     * @param value Approved amount
     */
    event Approval(address indexed owner, address indexed spender, uint value);

    /**
     * @notice Emitted when tokens are transferred
     * @param from Sender
     * @param to Recipient
     * @param value Transfer amount
     */
    event Transfer(address indexed from, address indexed to, uint value);

    /**
     * @notice Get LP token name
     * @return LP token name
     */
    function name() external pure returns (string memory);

    /**
     * @notice Get LP token symbol
     * @return LP token symbol
     */
    function symbol() external pure returns (string memory);

    /**
     * @notice Get LP token decimals
     * @return LP token decimals (usually 18)
     */
    function decimals() external pure returns (uint8);

    /**
     * @notice Get LP token total supply
     * @return LP token total amount
     */
    function totalSupply() external view returns (uint);

    /**
     * @notice Get account's LP token balance
     * @param owner Account address
     * @return LP token balance
     */
    function balanceOf(address owner) external view returns (uint);

    /**
     * @notice Get allowance
     * @param owner Token owner
     * @param spender Approved spender
     * @return Allowance amount
     */
    function allowance(address owner, address spender) external view returns (uint);

    /**
     * @notice Approve another address to use your LP tokens
     * @param spender Approved spender
     * @param value Approved amount
     * @return Success status
     */
    function approve(address spender, uint value) external returns (bool);

    /**
     * @notice Transfer LP tokens
     * @param to Recipient
     * @param value Transfer amount
     * @return Success status
     */
    function transfer(address to, uint value) external returns (bool);

    /**
     * @notice Transfer LP tokens from another account (requires approval)
     * @param from Sender
     * @param to Recipient
     * @param value Transfer amount
     * @return Success status
     */
    function transferFrom(address from, address to, uint value) external returns (bool);

    /**
     * @notice Get EIP-712 domain separator
     * @return EIP-712 domain separator hash
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /**
     * @notice Get permit type hash
     * @return Permit type hash value
     */
    function PERMIT_TYPEHASH() external pure returns (bytes32);

    /**
     * @notice Get account's signature nonce
     * @param owner Account address
     * @return Nonce value
     */
    function nonces(address owner) external view returns (uint);

    /**
     * @notice Approve token usage via signature (EIP-2612)
     * @param owner Token owner
     * @param spender Approved spender
     * @param value Approved amount
     * @param deadline Approval deadline
     * @param v Signature parameter v
     * @param r Signature parameter r
     * @param s Signature parameter s
     */
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    /**
     * @notice Emitted when liquidity is added
     * @param sender Operation initiator
     * @param amount0 Amount of token0 added
     * @param amount1 Amount of token1 added
     */
    event Mint(address indexed sender, uint amount0, uint amount1);

    /**
     * @notice Emitted when liquidity is removed
     * @param sender Operation initiator
     * @param amount0 Amount of token0 removed
     * @param amount1 Amount of token1 removed
     * @param to Recipient address
     */
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);

    /**
     * @notice Emitted when a swap is executed
     * @param sender Operation initiator
     * @param amount0In Input amount of token0
     * @param amount1In Input amount of token1
     * @param amount0Out Output amount of token0
     * @param amount1Out Output amount of token1
     * @param to Recipient address
     */
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );

    /**
     * @notice Emitted when reserves are synced
     * @param reserve0 token0 reserve
     * @param reserve1 token1 reserve
     */
    event Sync(uint112 reserve0, uint112 reserve1);

    /**
     * @notice Get minimum liquidity (minimum LP locked at zero address)
     * @return Minimum liquidity value (usually 1000)
     */
    function MINIMUM_LIQUIDITY() external pure returns (uint);

    /**
     * @notice Get factory contract address
     * @return Factory contract address
     */
    function factory() external view returns (address);

    /**
     * @notice Get token0 address
     * @return token0 contract address
     */
    function token0() external view returns (address);

    /**
     * @notice Get token1 address
     * @return token1 contract address
     */
    function token1() external view returns (address);

    /**
     * @notice Get reserves info
     * @return reserve0 token0 reserve
     * @return reserve1 token1 reserve
     * @return blockTimestampLast Last update timestamp
     */
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    /**
     * @notice Get token0 cumulative price
     * @return token0 cumulative price (used for TWAP calculation)
     */
    function price0CumulativeLast() external view returns (uint);

    /**
     * @notice Get token1 cumulative price
     * @return token1 cumulative price (used for TWAP calculation)
     */
    function price1CumulativeLast() external view returns (uint);

    /**
     * @notice Get last k value (reserve0 * reserve1)
     * @return k value
     */
    function kLast() external view returns (uint);

    /**
     * @notice Mint LP tokens (add liquidity)
     * @param to LP token recipient address
     * @return liquidity Amount of LP tokens minted
     */
    function mint(address to) external returns (uint liquidity);

    /**
     * @notice Burn LP tokens (remove liquidity)
     * @param to Underlying token recipient address
     * @return amount0 Amount of token0 returned
     * @return amount1 Amount of token1 returned
     */
    function burn(address to) external returns (uint amount0, uint amount1);

    /**
     * @notice Execute token swap
     * @param amount0Out Output amount of token0
     * @param amount1Out Output amount of token1
     * @param to Recipient address
     * @param data Callback data (for flash loans)
     */
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;

    /**
     * @notice Force balance to match reserves (remove excess tokens)
     * @param to Excess token recipient address
     */
    function skim(address to) external;

    /**
     * @notice Force update reserves to match balance
     */
    function sync() external;

    /**
     * @notice Initialize trading pair (set token0 and token1)
     * @param _token0 token0 address
     * @param _token1 token1 address
     */
    function initialize(address _token0, address _token1) external;
}
