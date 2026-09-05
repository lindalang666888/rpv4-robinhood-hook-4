// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "@uniswap/v4-core/src/interfaces/callback/IUnlockCallback.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {BaseCustomAccounting} from "@openzeppelin/uniswap-hooks/src/base/BaseCustomAccounting.sol";

interface IRPV4Token {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external returns (bool);
    function configure(address hook, address poolManager, address feeRecipient) external;
}

interface IRPV4Hook {
    function addLiquidity(BaseCustomAccounting.AddLiquidityParams calldata params)
        external payable returns (BalanceDelta);
}

/// @notice One-shot graph initializer: initialize pool, seed token inventory, and atomically pre-buy.
contract RPV4Initializer is IUnlockCallback {
    using BalanceDeltaLibrary for BalanceDelta;
    uint256 public constant INITIAL_BUY = 0.039 ether;
    uint160 public constant START_PRICE = 1 << 96;
    address public constant POOL_MANAGER = 0x8366a39CC670B4001A1121B8F6A443A643e40951;
    address public constant LAUNCH_WALLET = 0x0000F19B0bf75Fc367A2bf318876d2d87D78DeAD;
    address public constant FEE_RECIPIENT = LAUNCH_WALLET;
    bool public initialized;
    address public token;
    address public hook;

    error UnauthorizedCallback();
    error AlreadyInitialized();
    error InvalidFunding();
    error InvalidContracts();

    function initialize(address token_, address hook_) external payable {
        if (initialized) revert AlreadyInitialized();
        if (msg.value != INITIAL_BUY) revert InvalidFunding();
        if (token_.code.length == 0 || hook_.code.length == 0) revert InvalidContracts();
        initialized = true;
        token = token_;
        hook = hook_;
        IRPV4Token(token_).configure(hook_, POOL_MANAGER, FEE_RECIPIENT);
        PoolKey memory key = _key(token_, hook_);
        IPoolManager(POOL_MANAGER).initialize(key, START_PRICE);
        uint256 supply = IRPV4Token(token_).totalSupply();
        IRPV4Token(token_).approve(hook_, supply);
        IRPV4Hook(hook_).addLiquidity(BaseCustomAccounting.AddLiquidityParams({
            amount0Desired: 0, amount1Desired: supply, amount0Min: 0, amount1Min: supply,
            deadline: block.timestamp, tickLower: TickMath.MIN_TICK, tickUpper: TickMath.MAX_TICK,
            userInputSalt: bytes32(0)
        }));
        IPoolManager(POOL_MANAGER).unlock(bytes("RPV4_INITIAL_BUY"));
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        if (msg.sender != POOL_MANAGER || keccak256(data) != keccak256(bytes("RPV4_INITIAL_BUY"))) {
            revert UnauthorizedCallback();
        }
        PoolKey memory key = _key(token, hook);
        BalanceDelta delta = IPoolManager(POOL_MANAGER).swap(key, SwapParams({
            zeroForOne: true, amountSpecified: -int256(INITIAL_BUY),
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }), bytes(""));
        uint256 nativeIn = uint256(uint128(-delta.amount0()));
        uint256 tokenOut = uint256(uint128(delta.amount1()));
        IPoolManager(POOL_MANAGER).settle{value: nativeIn}();
        IPoolManager(POOL_MANAGER).take(Currency.wrap(token), LAUNCH_WALLET, tokenOut);
        return abi.encode(tokenOut);
    }

    function _key(address token_, address hook_) private pure returns (PoolKey memory) {
        return PoolKey({currency0: Currency.wrap(address(0)), currency1: Currency.wrap(token_),
            fee: 0, tickSpacing: 60, hooks: IHooks(hook_)});
    }
}
