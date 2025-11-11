// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

contract ChannelTipping is ReentrancyGuard, Pausable, Ownable, EIP712 {
    using ECDSA for bytes32;

    struct Tip {
        address sender;
        uint256 amount;
        uint256 claimedAmount;
        uint256 timestamp;
        bool claimed;
        bool refunded;
    }

    mapping(uint256 => Tip[]) private channelTips;
    mapping(uint256 => uint256) private lockedFunds;
    mapping(uint256 => uint256) private totalReceived;
    mapping(address => uint256) private totalSent;
    mapping(uint256 => bool) private channelExists;
    mapping(uint256 => uint256) public channelNonce;
    mapping(uint256 => uint256) public channelClaimedTimestamp;
    mapping(bytes32 => bool) private usedPermit;

    uint256[] private allChannelIDs;
    uint256 public reclaimAfter = 180 days;
    uint256 private totalLockedGlobal;

    address public verifier;

    bytes32 private constant CLAIM_TYPEHASH = keccak256(
        "ClaimPermit(uint256 channelID,address receiver,uint256 amount,uint256 nonce,uint256 deadline)"
    );

    event TipSent(uint256 indexed channelID, address indexed sender, uint256 amount, uint256 timestamp, uint256 tipIndex);
    event TipClaimed(uint256 indexed channelID, address indexed receiver, uint256 amount, uint256 timestamp);
    event TipReclaimed(uint256 indexed channelID, address indexed sender, uint256 amount, uint256 timestamp);
    event EmergencyWithdraw(address indexed owner, uint256 amount, uint256 timestamp);
    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);
    event PermitUsed(bytes32 indexed permitHash, uint256 indexed channelID, address indexed receiver, uint256 amount, uint256 nonce, uint256 timestamp);

    error InvalidChannelID();
    error NoFundsToClaim();
    error TransferFailed();
    error InvalidPermit();
    error PermitExpired();
    error AlreadyUsedPermit();
    error UseTipChannel();
    error InvalidIndex();
    error AccountingMismatch();

    constructor(address _verifier)
        EIP712("ChannelTipping", "1")
        Ownable(msg.sender)
    {
        require(_verifier != address(0), "Invalid verifier");
        verifier = _verifier;
    }

    function tipChannel(uint256 channelID)
        external
        payable
        whenNotPaused
        nonReentrant
    {
        if (channelID == 0) revert InvalidChannelID();
        require(msg.value >= 0.0001 ether, "Tip too small");
        require(channelTips[channelID].length < 1000, "Channel tip limit reached");

        Tip[] storage tips = channelTips[channelID];
        uint256 tipIndex = tips.length;

        tips.push(Tip({
            sender: msg.sender,
            amount: msg.value,
            claimedAmount: 0,
            timestamp: block.timestamp,
            claimed: false,
            refunded: false
        }));

        lockedFunds[channelID] += msg.value;
        totalLockedGlobal += msg.value;
        totalReceived[channelID] += msg.value;
        totalSent[msg.sender] += msg.value;

        if (!channelExists[channelID]) {
            channelExists[channelID] = true;
            allChannelIDs.push(channelID);
        }

        emit TipSent(channelID, msg.sender, msg.value, block.timestamp, tipIndex);
    }

    function claimWithPermit(
        uint256 channelID,
        address receiver,
        uint256 amount,
        uint256 nonce,
        uint256 deadline,
        bytes calldata signature
    ) external whenNotPaused nonReentrant {
        if (channelID == 0) revert InvalidChannelID();
        if (block.timestamp > deadline) revert PermitExpired();

        uint256 locked = lockedFunds[channelID];
        if (locked == 0) revert NoFundsToClaim();
        require(amount > 0, "Amount must be > 0");
        require(amount <= locked, "Amount exceeds locked balance");
        require(nonce == channelNonce[channelID], "Invalid nonce");

        bytes32 structHash = keccak256(
            abi.encode(CLAIM_TYPEHASH, channelID, receiver, amount, nonce, deadline)
        );
        bytes32 digest = _hashTypedDataV4(structHash);
        if (usedPermit[digest]) revert AlreadyUsedPermit();

        address signer = ECDSA.recover(digest, signature);
        if (signer != verifier) revert InvalidPermit();

        usedPermit[digest] = true;
        channelNonce[channelID]++;

        Tip[] storage tips = channelTips[channelID];
        uint256 remaining = amount;
        uint256 len = tips.length;

        for (uint256 i = 0; i < len && remaining > 0; ++i) {
            Tip storage t = tips[i];
            if (t.refunded) continue;
            uint256 available = 0;
            if (t.amount > t.claimedAmount) {
                available = t.amount - t.claimedAmount;
            } else {
                continue;
            }
            uint256 take = available <= remaining ? available : remaining;
            t.claimedAmount += take;
            if (t.claimedAmount == t.amount) {
                t.claimed = true;
            }
            remaining -= take;
        }

        if (remaining != 0) revert AccountingMismatch();

        lockedFunds[channelID] -= amount;
        totalLockedGlobal -= amount;
        channelClaimedTimestamp[channelID] = block.timestamp;

        (bool success, ) = payable(receiver).call{value: amount}("");
        if (!success) revert TransferFailed();

        emit PermitUsed(digest, channelID, receiver, amount, nonce, block.timestamp);
        emit TipClaimed(channelID, receiver, amount, block.timestamp);
    }

    function reclaim(uint256 channelID, uint256 tipIndex)
        external
        nonReentrant
    {
        Tip[] storage tips = channelTips[channelID];
        if (tips.length == 0 || tipIndex >= tips.length) revert InvalidIndex();

        Tip storage tip = tips[tipIndex];
        require(tip.sender == msg.sender, "Not your tip");
        require(!tip.refunded, "Already refunded");

        uint256 refundable = 0;
        if (tip.amount > tip.claimedAmount) {
            refundable = tip.amount - tip.claimedAmount;
        }

        require(refundable > 0, "Nothing to reclaim");
        require(block.timestamp > tip.timestamp + reclaimAfter, "Not expired");
        require(lockedFunds[channelID] >= refundable, "Accounting mismatch");

        tip.refunded = true;
        lockedFunds[channelID] -= refundable;
        totalLockedGlobal -= refundable;

        (bool success, ) = payable(msg.sender).call{value: refundable}("");
        if (!success) revert TransferFailed();

        emit TipReclaimed(channelID, msg.sender, refundable, block.timestamp);
    }

    function setVerifier(address newVerifier) external onlyOwner {
        require(newVerifier != address(0), "Invalid verifier");
        address old = verifier;
        verifier = newVerifier;
        emit VerifierUpdated(old, newVerifier);
    }

    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    function setReclaimAfter(uint256 _days) external onlyOwner {
        reclaimAfter = _days * 1 days;
    }

    function emergencyWithdraw(address payable to)
        external
        onlyOwner
        whenPaused
        nonReentrant
    {
        require(to != address(0), "Invalid address");

        uint256 contractBal = address(this).balance;
        uint256 withdrawable = contractBal > totalLockedGlobal
            ? contractBal - totalLockedGlobal
            : 0;

        require(withdrawable > 0, "No withdrawable funds");

        (bool success, ) = to.call{value: withdrawable}("");
        if (!success) revert TransferFailed();

        emit EmergencyWithdraw(to, withdrawable, block.timestamp);
    }

    function getLockedFunds(uint256 channelID)
        external
        view
        returns (uint256)
    {
        return lockedFunds[channelID];
    }

    function getTotalReceived(uint256 channelID)
        external
        view
        returns (uint256)
    {
        return totalReceived[channelID];
    }

    function getTotalSent(address user)
        external
        view
        returns (uint256)
    {
        return totalSent[user];
    }

    function getAllChannelIDs() external view returns (uint256[] memory) {
        return allChannelIDs;
    }

    function getTipsForChannel(uint256 channelID)
        external
        view
        returns (Tip[] memory)
    {
        return channelTips[channelID];
    }

    function getTotalLockedGlobal() external view returns (uint256) {
        return totalLockedGlobal;
    }

    function isPermitUsed(bytes32 permitHash) external view returns (bool) {
        return usedPermit[permitHash];
    }

    receive() external payable { revert UseTipChannel(); }
    fallback() external payable { revert UseTipChannel(); }
}
