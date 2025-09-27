// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract YTPay is Ownable, ReentrancyGuard {
<<<<<<< HEAD
    IERC20 public immutable pyUSDC;
=======
    IERC20 public immutable pyUSD;  // changed name here
>>>>>>> anand

    struct Channel {
        address wallet;
        bool registered;
        uint256 locked;
    }

    mapping(bytes32 => Channel) private channels;

    event PaymentLocked(bytes32 indexed key, string channelId, address buyer, uint256 amount);
    event PaymentSent(bytes32 indexed key, string channelId, address buyer, address wallet, uint256 amount);
    event ChannelRegistered(bytes32 indexed key, string channelId, address wallet);
    event FundsReleased(bytes32 indexed key, string channelId, address wallet, uint256 amount);

<<<<<<< HEAD
    constructor(address _pyUSDC) {
        pyUSDC = IERC20(_pyUSDC);
=======
    constructor(address _pyUSD) {
        pyUSD = IERC20(_pyUSD);  // changed name here
>>>>>>> anand
    }

    function _key(string memory channelId) internal pure returns (bytes32) {
        return keccak256(bytes(channelId));
    }

    function pay(string calldata channelId, uint256 amount) external nonReentrant {
        require(amount > 0, "Invalid amount");
        bytes32 k = _key(channelId);

<<<<<<< HEAD
        require(pyUSDC.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        Channel storage ch = channels[k];
        if (ch.registered && ch.wallet != address(0)) {
            pyUSDC.transfer(ch.wallet, amount);
=======
        require(pyUSD.transferFrom(msg.sender, address(this), amount), "Transfer failed"); // changed name here

        Channel storage ch = channels[k];
        if (ch.registered && ch.wallet != address(0)) {
            pyUSD.transfer(ch.wallet, amount); // changed name here
>>>>>>> anand
            emit PaymentSent(k, channelId, msg.sender, ch.wallet, amount);
        } else {
            ch.locked += amount;
            emit PaymentLocked(k, channelId, msg.sender, amount);
        }
    }

    function registerChannel(string calldata channelId, address wallet) external onlyOwner nonReentrant {
        require(wallet != address(0), "Invalid wallet");
        bytes32 k = _key(channelId);
        Channel storage ch = channels[k];
        require(!ch.registered, "Already registered");

        ch.wallet = wallet;
        ch.registered = true;
        emit ChannelRegistered(k, channelId, wallet);

        if (ch.locked > 0) {
            uint256 amt = ch.locked;
            ch.locked = 0;
<<<<<<< HEAD
            pyUSDC.transfer(wallet, amt);
=======
            pyUSD.transfer(wallet, amt); // changed name here
>>>>>>> anand
            emit FundsReleased(k, channelId, wallet, amt);
        }
    }

    function getChannel(string calldata channelId) external view returns (address wallet, bool registered, uint256 locked) {
        bytes32 k = _key(channelId);
        Channel storage ch = channels[k];
        return (ch.wallet, ch.registered, ch.locked);
    }
<<<<<<< HEAD
} 
=======
}
>>>>>>> anand
