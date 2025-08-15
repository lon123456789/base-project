// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Simple DAO Governance
/// @notice Basic DAO for proposals & voting (1 vote per address).
/// @dev No external imports — easy verification.

contract GigaDAO {
    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 voteYes;
        uint256 voteNo;
        uint256 deadline;
        bool executed;
        mapping(address => bool) voted;
    }

    address public chairperson;
    uint256 public proposalCount;
    uint256 public votingPeriod = 3 days;

    mapping(uint256 => Proposal) private proposals;

    event ProposalCreated(uint256 indexed id, address indexed proposer, string description, uint256 deadline);
    event Voted(uint256 indexed id, address indexed voter, bool support);
    event ProposalExecuted(uint256 indexed id, bool passed);

    modifier onlyChair() {
        require(msg.sender == chairperson, "Not chairperson");
        _;
    }

    constructor() {
        chairperson = msg.sender;
    }

    function createProposal(string memory _description) external {
        proposalCount++;
        Proposal storage p = proposals[proposalCount];
        p.id = proposalCount;
        p.proposer = msg.sender;
        p.description = _description;
        p.deadline = block.timestamp + votingPeriod;

        emit ProposalCreated(p.id, msg.sender, _description, p.deadline);
    }

    function vote(uint256 _proposalId, bool _support) external {
        Proposal storage p = proposals[_proposalId];
        require(block.timestamp < p.deadline, "Voting ended");
        require(!p.voted[msg.sender], "Already voted");

        p.voted[msg.sender] = true;

        if (_support) {
            p.voteYes++;
        } else {
            p.voteNo++;
        }

        emit Voted(_proposalId, msg.sender, _support);
    }

    function executeProposal(uint256 _proposalId) external {
        Proposal storage p = proposals[_proposalId];
        require(block.timestamp >= p.deadline, "Voting not ended");
        require(!p.executed, "Already executed");

        p.executed = true;
        bool passed = p.voteYes > p.voteNo;

        emit ProposalExecuted(_proposalId, passed);

        // For simplicity, no external actions — just marks as passed/failed
    }

    function getProposal(uint256 _proposalId)
        external
        view
        returns (
            uint256 id,
            address proposer,
            string memory description,
            uint256 voteYes,
            uint256 voteNo,
            uint256 deadline,
            bool executed
        )
    {
        Proposal storage p = proposals[_proposalId];
        return (
            p.id,
            p.proposer,
            p.description,
            p.voteYes,
            p.voteNo,
            p.deadline,
            p.executed
        );
    }
}

