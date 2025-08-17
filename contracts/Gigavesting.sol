// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IERC20
 * @dev Minimal ERC20 interface for interacting with tokens.
 */
interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

/**
 * @title GigaVesting
 * @dev A contract that releases ERC20 tokens gradually to a beneficiary over time.
 * Single-file version for easy verification on Basescan.
 */
contract Vestforapp {
    IERC20 public immutable token;        // ERC20 token being vested
    address public immutable beneficiary; // Address receiving vested tokens
    uint256 public immutable start;       // Vesting start timestamp
    uint256 public immutable duration;    // Vesting duration in seconds
    uint256 public released;              // Total tokens released so far

    event TokensReleased(uint256 amount);

    /**
     * @dev Constructor sets vesting schedule.
     * @param _token Address of the ERC20 token to be vested.
     * @param _beneficiary Address receiving the vested tokens.
     * @param _start Vesting start timestamp (in seconds).
     * @param _duration Duration of vesting in seconds.
     */
    constructor(
        address _token,
        address _beneficiary,
        uint256 _start,
        uint256 _duration
    ) {
        require(_token != address(0), "Invalid token");
        require(_beneficiary != address(0), "Invalid beneficiary");
        require(_duration > 0, "Duration must be > 0");

        token = IERC20(_token);
        beneficiary = _beneficiary;
        start = _start;
        duration = _duration;
    }

    /**
     * @dev Calculates the amount of tokens that have vested.
     */
    function vestedAmount() public view returns (uint256) {
        uint256 totalBalance = tokenBalance() + released;
        if (block.timestamp < start) {
            return 0;
        } else if (block.timestamp >= start + duration) {
            return totalBalance;
        } else {
            uint256 timeElapsed = block.timestamp - start;
            return (totalBalance * timeElapsed) / duration;
        }
    }

    /**
     * @dev Release vested tokens to the beneficiary.
     */
    function release() external {
        uint256 vested = vestedAmount();
        uint256 unreleased = vested - released;
        require(unreleased > 0, "No tokens to release");

        released += unreleased;
        require(token.transfer(beneficiary, unreleased), "Token transfer failed");

        emit TokensReleased(unreleased);
    }

    /**
     * @dev Current token balance held by this contract.
     */
    function tokenBalance() public view returns (uint256) {
        return tokenBalanceOf(address(this));
    }

    /**
     * @dev Internal helper to get token balance of an address.
     */
    function tokenBalanceOf(address account) internal view returns (uint256) {
        (bool success, bytes memory data) =
            address(token).staticcall(abi.encodeWithSignature("balanceOf(address)", account));
        require(success && data.length >= 32, "Failed to get balance");
        return abi.decode(data, (uint256));
    }
}
