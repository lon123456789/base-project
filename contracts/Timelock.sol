// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Simple Timelock Contract
/// @notice Holds funds or executes calls only after a delay period.
/// @dev Single file, no flattening required.
contract GigaTimelock {
    address public owner;
    uint256 public delay; // in seconds

    struct QueuedTx {
        address target;
        uint256 value;
        bytes data;
        uint256 executeAfter;
        bool executed;
    }

    mapping(bytes32 => QueuedTx) public queue;

    event Queued(bytes32 indexed txId, address target, uint256 value, bytes data, uint256 executeAfter);
    event Executed(bytes32 indexed txId);
    event Cancelled(bytes32 indexed txId);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(uint256 _delay) {
        owner = msg.sender;
        delay = _delay;
    }

    function queueTx(address target, uint256 value, bytes calldata data) external onlyOwner returns (bytes32) {
        require(target != address(0), "Invalid target");

        bytes32 txId = keccak256(abi.encode(target, value, data, block.timestamp));
        require(queue[txId].target == address(0), "Already queued");

        uint256 executeAfter = block.timestamp + delay;
        queue[txId] = QueuedTx(target, value, data, executeAfter, false);

        emit Queued(txId, target, value, data, executeAfter);
        return txId;
    }

    function executeTx(bytes32 txId) external payable onlyOwner {
        QueuedTx storage queuedTx = queue[txId];
        require(queuedTx.target != address(0), "Tx not found");
        require(!queuedTx.executed, "Already executed");
        require(block.timestamp >= queuedTx.executeAfter, "Too early");

        (bool success, ) = queuedTx.target.call{value: queuedTx.value}(queuedTx.data);
        require(success, "Tx failed");

        queuedTx.executed = true;
        emit Executed(txId);
    }

    function cancelTx(bytes32 txId) external onlyOwner {
        require(queue[txId].target != address(0), "Tx not found");
        delete queue[txId];
        emit Cancelled(txId);
    }

    // Let the contract receive ETH
    receive() external payable {}
}

