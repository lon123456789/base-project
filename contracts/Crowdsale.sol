// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Simple Crowdsale / ICO Contract
/// @notice Allows people to buy your ERC20 token with ETH during the sale period.
/// @dev Single file, no flattening needed.

contract SimpleToken {
    string public name = "Gigasale Token";
    string public symbol = "CST";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(uint256 initialSupply, address owner) {
        totalSupply = initialSupply;
        balanceOf[owner] = initialSupply;
        emit Transfer(address(0), owner, initialSupply);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        require(balanceOf[msg.sender] >= value, "Not enough tokens");
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        require(balanceOf[from] >= value, "Not enough tokens");
        require(allowance[from][msg.sender] >= value, "Not approved");
        balanceOf[from] -= value;
        balanceOf[to] += value;
        allowance[from][msg.sender] -= value;
        emit Transfer(from, to, value);
        return true;
    }
}

contract SimpleCrowdsale {
    address public owner;
    SimpleToken public token;
    uint256 public rate; // tokens per 1 ETH
    uint256 public startTime;
    uint256 public endTime;
    bool public finalized;

    event TokensPurchased(address indexed buyer, uint256 amountETH, uint256 amountTokens);
    event Finalized();

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(
        uint256 _tokenSupply,
        uint256 _rate,
        uint256 _saleDurationSeconds
    ) {
        owner = msg.sender;
        token = new SimpleToken(_tokenSupply * (10 ** 18), address(this));
        rate = _rate;
        startTime = block.timestamp;
        endTime = block.timestamp + _saleDurationSeconds;
    }

    receive() external payable {
        buyTokens();
    }

    function buyTokens() public payable {
        require(block.timestamp >= startTime && block.timestamp <= endTime, "Sale not active");
        require(msg.value > 0, "No ETH sent");

        uint256 tokenAmount = msg.value * rate;
        require(token.balanceOf(address(this)) >= tokenAmount, "Not enough tokens left");

        token.transfer(msg.sender, tokenAmount);
        emit TokensPurchased(msg.sender, msg.value, tokenAmount);
    }

    function withdrawETH(address payable to) external onlyOwner {
        require(finalized, "Not finalized");
        to.transfer(address(this).balance);
    }

    function finalize() external onlyOwner {
        require(block.timestamp > endTime, "Sale not ended");
        finalized = true;
        emit Finalized();
    }

    function withdrawUnsoldTokens(address to) external onlyOwner {
        require(finalized, "Not finalized");
        uint256 balance = token.balanceOf(address(this));
        token.transfer(to, balance);
    }
}

