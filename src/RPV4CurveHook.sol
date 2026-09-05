// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {BaseCustomCurve} from "@openzeppelin/uniswap-hooks/src/base/BaseCustomCurve.sol";
import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {SwapParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencySettler} from "@openzeppelin/uniswap-hooks/src/utils/CurrencySettler.sol";

/// @notice Hook-owned, token-only inventory with a virtual constant-product curve.
contract RPV4CurveHook is BaseCustomCurve {
    using CurrencyLibrary for Currency;
    using CurrencySettler for Currency;
    using PoolIdLibrary for PoolKey;

    uint256 public constant FEE_DENOMINATOR = 100;
    uint256 public constant BUY_FEE = 1;
    uint256 public constant SELL_FEE = 1;
    uint256 public constant MAX_BUY_NATIVE = 0.05 ether;
    uint256 public constant INITIAL_VIRTUAL_NATIVE = 2 ether;
    uint256 public constant INITIAL_VIRTUAL_TOKEN = 1_000_000_000 ether;

    address public immutable token;
    address public immutable initializer;
    address public immutable feeRecipient;
    uint256 public virtualNative = INITIAL_VIRTUAL_NATIVE;
    uint256 public virtualToken = INITIAL_VIRTUAL_TOKEN;
    uint256 public accruedNativeFees;
    uint256 public accruedTokenFees;
    bool public inventorySeeded;

    error Unauthorized();
    error InvalidPool();
    error ExactOutputDisabled();
    error BuyLimitExceeded(uint256 amount);
    error ZeroOutput();
    error InventoryAlreadySeeded();
    error LiquidityRemovalDisabled();
    error CallbackCallerNotPoolManager(address caller);
    error UnexpectedPool(bytes32 actual, bytes32 expected);

    constructor(IPoolManager manager, address token_, address initializer_, address feeRecipient_)
        BaseHook(manager)
    {
        if (token_ == address(0) || initializer_ == address(0) || feeRecipient_ == address(0)) revert Unauthorized();
        token = token_;
        initializer = initializer_;
        feeRecipient = feeRecipient_;
    }

    function _beforeInitialize(address sender, PoolKey calldata key, uint160 price)
        internal override returns (bytes4)
    {
        _requirePoolManagerCallback();
        if (sender != initializer || !key.currency0.isAddressZero()
            || Currency.unwrap(key.currency1) != token || address(key.hooks) != address(this) || key.fee != 0) {
            revert InvalidPool();
        }
        return super._beforeInitialize(sender, key, price);
    }

    /// @dev Repeat callback authentication in the exact submitted target source.
    /// BaseHook also authenticates the external entrypoint; this explicit guard
    /// makes every enabled callback independently auditable by source admission.
    function _beforeAddLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        _requirePoolManagerCallback();
        _requireCanonicalPool(key);
        return super._beforeAddLiquidity(sender, key, params, hookData);
    }

    function _beforeRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {
        _requirePoolManagerCallback();
        _requireCanonicalPool(key);
        return super._beforeRemoveLiquidity(sender, key, params, hookData);
    }

    function _beforeSwap(address sender, PoolKey calldata key, SwapParams calldata params, bytes calldata hookData)
        internal override returns (bytes4, BeforeSwapDelta, uint24)
    {
        _requirePoolManagerCallback();
        _requireCanonicalPool(key);
        return super._beforeSwap(sender, key, params, hookData);
    }

    function _requirePoolManagerCallback() internal view {
        if (msg.sender != address(poolManager)) revert CallbackCallerNotPoolManager(msg.sender);
    }

    function _requireCanonicalPool(PoolKey calldata key) internal view {
        PoolKey memory expected = poolKey();
        bytes32 actualId = PoolId.unwrap(key.toId());
        bytes32 expectedId = PoolId.unwrap(expected.toId());
        if (address(expected.hooks) == address(0) || actualId != expectedId) {
            revert UnexpectedPool(actualId, expectedId);
        }
    }

    function _getUnspecifiedAmount(SwapParams calldata params) internal override returns (uint256 amountOut) {
        if (params.amountSpecified >= 0) revert ExactOutputDisabled();
        uint256 gross = uint256(-params.amountSpecified);
        if (params.zeroForOne) {
            if (gross > MAX_BUY_NATIVE) revert BuyLimitExceeded(gross);
            uint256 fee = gross * BUY_FEE / FEE_DENOMINATOR;
            uint256 net = gross - fee;
            amountOut = virtualToken * net / (virtualNative + net);
            if (amountOut == 0 || amountOut >= virtualToken) revert ZeroOutput();
            virtualNative += net;
            virtualToken -= amountOut;
            accruedNativeFees += fee;
        } else {
            uint256 fee = gross * SELL_FEE / FEE_DENOMINATOR;
            uint256 net = gross - fee;
            amountOut = virtualNative * net / (virtualToken + net);
            if (amountOut == 0 || amountOut >= virtualNative - INITIAL_VIRTUAL_NATIVE) revert ZeroOutput();
            virtualToken += net;
            virtualNative -= amountOut;
            accruedTokenFees += fee;
        }
    }

    function _getSwapFeeAmount(SwapParams calldata params, uint256) internal pure override returns (uint256) {
        uint256 gross = uint256(-params.amountSpecified);
        return gross / FEE_DENOMINATOR;
    }

    function _getAmountIn(AddLiquidityParams memory params)
        internal view override returns (uint256 amount0, uint256 amount1, uint256 shares)
    {
        if (msg.sender != initializer || inventorySeeded || params.amount0Desired != 0
            || params.amount1Desired != INITIAL_VIRTUAL_TOKEN) revert Unauthorized();
        return (0, params.amount1Desired, params.amount1Desired);
    }

    function _getAmountOut(RemoveLiquidityParams memory)
        internal pure override returns (uint256, uint256, uint256)
    { revert LiquidityRemovalDisabled(); }

    function _mint(AddLiquidityParams memory, BalanceDelta, BalanceDelta, uint256) internal override {
        if (msg.sender != initializer || inventorySeeded) revert InventoryAlreadySeeded();
        inventorySeeded = true;
    }

    function _burn(RemoveLiquidityParams memory, BalanceDelta, BalanceDelta, uint256) internal pure override {
        revert LiquidityRemovalDisabled();
    }

    /// @notice Anyone may trigger payout, but funds can only go to the immutable recipient.
    function claimFees() external {
        poolManager.unlock(abi.encode(uint256(1)));
    }

    function unlockCallback(bytes calldata data) public override onlyPoolManager returns (bytes memory) {
        if (data.length != 32) return super.unlockCallback(data);
        uint256 nativeFee = accruedNativeFees;
        uint256 tokenFee = accruedTokenFees;
        accruedNativeFees = 0;
        accruedTokenFees = 0;
        Currency nativeCurrency = Currency.wrap(address(0));
        Currency tokenCurrency = Currency.wrap(token);
        nativeCurrency.settle(poolManager, address(this), nativeFee, true);
        nativeCurrency.take(poolManager, feeRecipient, nativeFee, false);
        tokenCurrency.settle(poolManager, address(this), tokenFee, true);
        tokenCurrency.take(poolManager, feeRecipient, tokenFee, false);
        return bytes("");
    }
}
