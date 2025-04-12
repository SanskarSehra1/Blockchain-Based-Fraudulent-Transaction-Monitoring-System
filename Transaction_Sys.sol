// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Transaction_Monitoring_System is ReentrancyGuard {
    address public owner;
    uint256 public transactionLimit; // In ether
    uint256 public timeLimit; // In seconds
    uint256 public gasFeeThreshold; // In wei per gas

    mapping(address => uint256) public lastTransactionTime;

    struct SuspiciousActivity {
        address sender;
        address recipient;
        uint256 amount;
        string reason;
        uint256 timestamp;
    }

    struct PendingTransaction {
        address sender;
        address recipient;
        uint256 amount;
        uint256 gasPrice;
        uint256 timestamp;
        bool approved;
        bool executed;
    }

    SuspiciousActivity[] public suspiciousActivities;
    PendingTransaction[] public pendingTransactions;

    event TransactionExecuted(address indexed sender, address indexed recipient, uint256 amount, uint256 gasPrice);
    event SuspiciousActivityDetected(address indexed sender, address indexed recipient, uint256 amount, string reason);
    event LimitsUpdated(uint256 transactionLimit, uint256 timeLimit, uint256 gasFeeThreshold);
    event TransactionQueued(uint256 indexed txId, address sender, address recipient, uint256 amount);
    event TransactionApproved(uint256 indexed txId);
    event TransactionRejected(uint256 indexed txId);

    modifier onlyOwner() {
        require(msg.sender == owner, "Unauthorized");
        _;
    }

    constructor(
        uint256 _transactionLimit,
        uint256 _timeLimit,
        uint256 _gasFeeThreshold
    ) {
        owner = msg.sender;
        transactionLimit = _transactionLimit;
        timeLimit = _timeLimit;
        gasFeeThreshold = _gasFeeThreshold;
    }

    function setLimits(
        uint256 _transactionLimit,
        uint256 _timeLimit,
        uint256 _gasFeeThreshold
    ) external onlyOwner {
        transactionLimit = _transactionLimit;
        timeLimit = _timeLimit;
        gasFeeThreshold = _gasFeeThreshold;
        emit LimitsUpdated(_transactionLimit, _timeLimit, _gasFeeThreshold);
    }

    function transferFunds(address payable _to) external payable nonReentrant {
        require(msg.value > 0, "Zero value transfer");
        require(_to != address(0), "Invalid recipient");

        bool suspicious = false;
        string memory reason = "";

        if ((msg.value / 1 ether) > transactionLimit) {
            suspicious = true;
            reason = "Amount exceeds limit";
        }

        if (block.timestamp - lastTransactionTime[msg.sender] < timeLimit) {
            suspicious = true;
            reason = appendReason(reason, "Time limit");
        }

        if (tx.gasprice > gasFeeThreshold) {
            suspicious = true;
            reason = appendReason(reason, "Gas fee");
        }

        lastTransactionTime[msg.sender] = block.timestamp;

        if (suspicious) {
            suspiciousActivities.push(SuspiciousActivity({
                sender: msg.sender,
                recipient: _to,
                amount: msg.value,
                reason: reason,
                timestamp: block.timestamp
            }));

            emit SuspiciousActivityDetected(msg.sender, _to, msg.value, reason);

            pendingTransactions.push(PendingTransaction({
                sender: msg.sender,
                recipient: _to,
                amount: msg.value,
                gasPrice: tx.gasprice,
                timestamp: block.timestamp,
                approved: false,
                executed: false
            }));

            emit TransactionQueued(pendingTransactions.length - 1, msg.sender, _to, msg.value);
        } else {
            (bool success, ) = _to.call{value: msg.value}("");
            require(success, "Transfer failed");
            emit TransactionExecuted(msg.sender, _to, msg.value, tx.gasprice);
        }
    }

    function approveTransaction(uint256 txId) external onlyOwner nonReentrant {
        require(txId < pendingTransactions.length, "Invalid txId");
        PendingTransaction storage txData = pendingTransactions[txId];
        require(!txData.executed, "Already executed");

        txData.approved = true;

        (bool success, ) = payable(txData.recipient).call{value: txData.amount}("");
        require(success, "Transfer failed");

        txData.executed = true;
        emit TransactionApproved(txId);
        emit TransactionExecuted(txData.sender, txData.recipient, txData.amount, txData.gasPrice);
    }

    function rejectTransaction(uint256 txId) external onlyOwner {
        require(txId < pendingTransactions.length, "Invalid txId");
        PendingTransaction storage txData = pendingTransactions[txId];
        require(!txData.executed, "Already executed");

        txData.executed = true; // Mark as handled
        emit TransactionRejected(txId);
    }

    function getSuspiciousActivities() external view returns (SuspiciousActivity[] memory) {
        return suspiciousActivities;
    }

    function getPendingTransactions() external view returns (PendingTransaction[] memory) {
        return pendingTransactions;
    }

    function appendReason(string memory existing, string memory newReason) internal pure returns (string memory) {
        if (bytes(existing).length > 0) {
            return string(abi.encodePacked(existing, ", ", newReason));
        } else {
            return newReason;
        }
    }

    receive() external payable {}
}
