// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Mutual Lottery Contract
/// @notice People send ETH to join, owner picks a random winner.
contract Raffle1 {
    address public owner;
    address[] public players;
    uint256 public ticketPrice;
    bool public isActive;

    event TicketPurchased(address indexed player);
    event WinnerSelected(address indexed winner, uint256 prize);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(uint256 _ticketPrice) {
        owner = msg.sender;
        ticketPrice = _ticketPrice;
        isActive = true;
    }

    function buyTicket() external payable {
        require(isActive, "Lottery closed");
        require(msg.value == ticketPrice, "Incorrect ETH sent");
        players.push(msg.sender);
        emit TicketPurchased(msg.sender);
    }

    function pickWinner() external onlyOwner {
        require(isActive, "Already ended");
        require(players.length > 0, "No players");

        // Simple pseudo-randomness (not secure for large stakes!)
        uint256 randomIndex = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.prevrandao, players))
        ) % players.length;

        address winner = players[randomIndex];
        uint256 prize = address(this).balance;

        isActive = false;
        payable(winner).transfer(prize);

        emit WinnerSelected(winner, prize);
    }

    function getPlayers() external view returns (address[] memory) {
        return players;
    }
}

