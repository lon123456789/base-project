// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * StreamVault — single-file payment streaming vault for ETH & ERC20.
 * Category: Payments / Streaming
 * Features:
 * - Create time-based payment streams (ETH or ERC20)
 * - Pull withdrawals by recipient at any time
 * - Cancel stream (sender or owner) with fair split
 * - Platform fee with hard cap (max 1%)
 * - Global pause (withdrawals still allowed)
 * - ReentrancyGuard (custom), SafeTransfer (custom)
 * - No imports → easy verification (no flattening)
 *
 * NOTE: This is a demo-quality contract; audit before production use.
 */
interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

library SafeTransfer {
    function _call(address token, bytes memory data) private returns (bool) {
        (bool ok, bytes memory ret) = token.call(data);
        return ok && (ret.length == 0 || abi.decode(ret, (bool)));
    }

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        require(_call(address(token), abi.encodeWithSelector(token.transfer.selector, to, value)), "TRANSFER_FAIL");
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        require(_call(address(token), abi.encodeWithSelector(token.transferFrom.selector, from, to, value)), "TRANSFER_FROM_FAIL");
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _ENTERED = 2;
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private _status = _NOT_ENTERED;

    modifier nonReentrant() {
        require(_status == _NOT_ENTERED, "REENTRANCY");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

contract StreamVault is ReentrancyGuard {
    using SafeTransfer for IERC20;

    // ====== Types ======
    struct Stream {
        address sender;
        address recipient;
        address token;     // address(0) for ETH
        uint128 deposit;   // total funded amount
        uint128 withdrawn; // amount already withdrawn by recipient
        uint64  start;     // unix seconds
        uint64  end;       // unix seconds (end > start)
        bool    canceled;
    }

    // ====== State ======
    address public owner;
    bool    public paused;              // emergency stop (creation/cancel), withdrawals allowed
    uint16  public feeBps;              // platform fee in basis points (e.g., 50 = 0.5%)
    uint16  public constant FEE_BPS_CAP = 100; // max 1%

    uint256 public nextStreamId = 1;    // incremental id
    mapping(uint256 => Stream) public streams;

    // ====== Events ======
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event Paused(bool status);
    event FeeUpdated(uint16 oldFeeBps, uint16 newFeeBps);

    event StreamCreated(
        uint256 indexed id,
        address indexed sender,
        address indexed recipient,
        address token,
        uint256 amount,
        uint64 start,
        uint64 end
    );

    event Withdraw(uint256 indexed id, address indexed recipient, uint256 amount);
    event Canceled(uint256 indexed id, uint256 refundSender, uint256 paidRecipient);

    // ====== Modifiers ======
    modifier onlyOwner() {
        require(msg.sender == owner, "NOT_OWNER");
        _;
    }

    modifier onlySender(uint256 id) {
        require(streams[id].sender == msg.sender, "NOT_SENDER");
        _;
    }

    modifier streamExists(uint256 id) {
        require(streams[id].sender != address(0), "NO_STREAM");
        _;
    }

    constructor(uint16 _feeBps) {
        require(_feeBps <= FEE_BPS_CAP, "FEE_CAP");
        owner = msg.sender;
        feeBps = _feeBps;
        emit OwnerChanged(address(0), msg.sender);
        emit FeeUpdated(0, _feeBps);
    }

    // ====== Admin ======
    function setOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "ZERO_ADDR");
        emit OwnerChanged(owner, newOwner);
        owner = newOwner;
    }

    function setPaused(bool s) external onlyOwner {
        paused = s;
        emit Paused(s);
    }

    function setFeeBps(uint16 bps) external onlyOwner {
        require(bps <= FEE_BPS_CAP, "FEE_CAP");
        emit FeeUpdated(feeBps, bps);
        feeBps = bps;
    }

    // ====== Core logic ======
    /**
     * Create a stream.
     * token == address(0): ETH stream, send amount via msg.value
     * token != address(0): ERC20 stream, require prior approve
     */
    function createStream(
        address recipient,
        address token,
        uint128 amount,
        uint64 start,
        uint64 end
    ) external payable nonReentrant returns (uint256 id) {
        require(!paused, "PAUSED");
        require(recipient != address(0), "BAD_RECIPIENT");
        require(end > start, "BAD_TIME");
        require(amount > 0, "ZERO_AMOUNT");

        // Collect funds
        if (token == address(0)) {
            require(msg.value == amount, "BAD_MSG_VALUE");
        } else {
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        id = nextStreamId++;
        streams[id] = Stream({
            sender: msg.sender,
            recipient: recipient,
            token: token,
            deposit: amount,
            withdrawn: 0,
            start: start,
            end: end,
            canceled: false
        });

        emit StreamCreated(id, msg.sender, recipient, token, amount, start, end);
    }

    /**
     * Amount recipient has earned so far (including withdrawn).
     */
    function _earned(Stream memory s, uint64 t) internal pure returns (uint256) {
        if (t <= s.start) return 0;
        uint256 elapsed = t >= s.end ? uint256(s.end - s.start) : uint256(t - s.start);
        // linear release
        return (uint256(s.deposit) * elapsed) / uint256(s.end - s.start);
    }

    /**
     * Claim available amount.
     */
    function withdraw(uint256 id) external nonReentrant streamExists(id) returns (uint256 amountOut) {
        Stream storage s = streams[id];
        require(msg.sender == s.recipient, "NOT_RECIPIENT");

        uint64 t = uint64(block.timestamp);
        uint256 earnedNow = _earned(s, t);
        require(earnedNow > s.withdrawn, "NOTHING");

        amountOut = earnedNow - s.withdrawn;
        s.withdrawn = uint128(earnedNow);

        // Apply fee (on withdrawal)
        uint256 fee = (amountOut * feeBps) / 10_000;
        uint256 toRecipient = amountOut - fee;

        if (s.token == address(0)) {
            _safeSend(payable(owner), fee);
            _safeSend(payable(s.recipient), toRecipient);
        } else {
            IERC20 token = IERC20(s.token);
            if (fee > 0) token.safeTransfer(owner, fee);
            token.safeTransfer(s.recipient, toRecipient);
        }

        emit Withdraw(id, s.recipient, toRecipient);
    }

    /**
     * Cancel a stream: sender (or owner) can cancel.
     * Recipient gets the vested part minus already withdrawn; sender gets the rest.
     */
    function cancel(uint256 id) external nonReentrant streamExists(id) {
        Stream storage s = streams[id];
        require(!s.canceled, "ALREADY");
        require(msg.sender == s.sender || msg.sender == owner, "NO_RIGHT");

        uint64 t = uint64(block.timestamp);
        uint256 earnedNow = _earned(s, t);
        uint256 dueToRecipient = earnedNow > s.withdrawn ? earnedNow - s.withdrawn : 0;
        uint256 remaining = uint256(s.deposit) - earnedNow;
        s.canceled = true;

        // Payouts
        if (s.token == address(0)) {
            if (dueToRecipient > 0) _safeSend(payable(s.recipient), dueToRecipient);
            if (remaining > 0) _safeSend(payable(s.sender), remaining);
        } else {
            IERC20 token = IERC20(s.token);
            if (dueToRecipient > 0) token.safeTransfer(s.recipient, dueToRecipient);
            if (remaining > 0) token.safeTransfer(s.sender, remaining);
        }

        emit Canceled(id, remaining, dueToRecipient);
    }

    // ====== Views ======
    function previewWithdraw(uint256 id) external view streamExists(id) returns (uint256 available) {
        Stream memory s = streams[id];
        uint256 earnedNow = _earned(s, uint64(block.timestamp));
        if (earnedNow <= s.withdrawn) return 0;
        uint256 gross = earnedNow - s.withdrawn;
        uint256 fee = (gross * feeBps) / 10_000;
        available = gross - fee;
    }

    function streamInfo(uint256 id) external view streamExists(id)
        returns (Stream memory s, uint256 availableToWithdraw, uint256 earnedTotal)
    {
        s = streams[id];
        earnedTotal = _earned(s, uint64(block.timestamp));
        uint256 gross = earnedTotal > s.withdrawn ? (earnedTotal - s.withdrawn) : 0;
        uint256 fee = (gross * feeBps) / 10_000;
        availableToWithdraw = gross - fee;
    }

    // ====== Utils ======
    function _safeSend(address payable to, uint256 value) internal {
        (bool ok, ) = to.call{value: value}("");
        require(ok, "ETH_SEND_FAIL");
    }

    receive() external payable {}
}

