// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Payment Splitter
/// @notice Splits ETH among multiple recipients based on percentage shares.
contract GigaSplitter {
    address public owner;
    address[] public payees;
    uint256[] public shares; // In percentage points (e.g., 20 = 20%)

    event PaymentReceived(address indexed from, uint256 amount);
    event PaymentReleased(address indexed to, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(address[] memory _payees, uint256[] memory _shares) {
        require(_payees.length == _shares.length, "Mismatched arrays");
        require(_payees.length > 0, "No payees");
        
        uint256 totalShares;
        for (uint256 i = 0; i < _shares.length; i++) {
            totalShares += _shares[i];
        }
        require(totalShares == 100, "Shares must total 100");

        owner = msg.sender;
        payees = _payees;
        shares = _shares;
    }

    receive() external payable {
        emit PaymentReceived(msg.sender, msg.value);
    }

    function releaseAll() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds");

        for (uint256 i = 0; i < payees.length; i++) {
            uint256 payment = (balance * shares[i]) / 100;
            payable(payees[i]).transfer(payment);
            emit PaymentReleased(payees[i], payment);
        }
    }

    function getPayees() external view returns (address[] memory, uint256[] memory) {
        return (payees, shares);
    }
}
