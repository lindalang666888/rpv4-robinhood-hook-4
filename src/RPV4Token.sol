// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Fixed-supply RPV4 token with an immutable 2% per-wallet ceiling.
contract RPV4Token {
    string public constant name = "RPV4";
    string public constant symbol = "RPV4";
    uint8 public constant decimals = 18;
    uint256 public constant totalSupply = 1_000_000_000 ether;
    uint256 public constant MAX_WALLET = 20_000_000 ether;

    address public immutable initializer;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => bool) public isLimitExempt;
    bool public configured;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error Unauthorized();
    error AlreadyConfigured();
    error ZeroAddress();
    error InsufficientBalance();
    error InsufficientAllowance();
    error WalletLimitExceeded(address wallet, uint256 resultingBalance);

    constructor(address initializer_) {
        if (initializer_ == address(0)) revert ZeroAddress();
        initializer = initializer_;
        isLimitExempt[initializer_] = true;
        balanceOf[initializer_] = totalSupply;
        emit Transfer(address(0), initializer_, totalSupply);
    }

    /// @dev One-shot binding performed by the graph initializer before inventory is deposited.
    function configure(address hook, address poolManager, address feeRecipient) external {
        if (msg.sender != initializer) revert Unauthorized();
        if (configured) revert AlreadyConfigured();
        if (hook == address(0) || poolManager == address(0) || feeRecipient == address(0)) revert ZeroAddress();
        configured = true;
        isLimitExempt[hook] = true;
        isLimitExempt[poolManager] = true;
        isLimitExempt[feeRecipient] = true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 approved = allowance[from][msg.sender];
        if (approved != type(uint256).max) {
            if (approved < value) revert InsufficientAllowance();
            unchecked { allowance[from][msg.sender] = approved - value; }
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        if (to == address(0)) revert ZeroAddress();
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) revert InsufficientBalance();
        uint256 resulting = balanceOf[to] + value;
        if (!isLimitExempt[to] && resulting > MAX_WALLET) revert WalletLimitExceeded(to, resulting);
        unchecked { balanceOf[from] = fromBalance - value; }
        balanceOf[to] = resulting;
        emit Transfer(from, to, value);
    }
}
