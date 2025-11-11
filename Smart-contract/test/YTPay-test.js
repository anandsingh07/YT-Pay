const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("YTPay Contract", function () {
  let YTPay, ytPay, owner, user1, user2, pyUSDC;

  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();

    // Deploy a mock ERC20 for testing
    const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    pyUSDC = await ERC20Mock.deploy("Test USDC", "tUSDC", 18);
    await pyUSDC.waitForDeployment();

    // Mint tokens to users
    await pyUSDC.mint(user1.address, ethers.parseUnits("1000", 18));
    await pyUSDC.mint(user2.address, ethers.parseUnits("1000", 18));

    // Deploy YTPay contract
    YTPay = await ethers.getContractFactory("YTPay");
    ytPay = await YTPay.deploy(pyUSDC.target);
    await ytPay.waitForDeployment();
  });

  describe("pay()", function () {
    it("should lock funds if channel is not registered", async function () {
      const channelId = "channel1";
      await pyUSDC.connect(user1).approve(ytPay.target, ethers.parseUnits("100", 18));

      await expect(ytPay.connect(user1).pay(channelId, ethers.parseUnits("100", 18)))
        .to.emit(ytPay, "PaymentLocked")
        .withArgs(
          ethers.keccak256(ethers.toUtf8Bytes(channelId)),
          channelId,
          user1.address,
          ethers.parseUnits("100", 18)
        );

      const ch = await ytPay.getChannel(channelId);
      expect(ch.locked).to.equal(ethers.parseUnits("100", 18));
      expect(ch.registered).to.be.false;
    });

    it("should send funds immediately if channel is registered", async function () {
      const channelId = "channel2";
      await ytPay.connect(owner).registerChannel(channelId, user2.address);

      await pyUSDC.connect(user1).approve(ytPay.target, ethers.parseUnits("50", 18));

      const balanceBefore = await pyUSDC.balanceOf(user2.address);

      await expect(ytPay.connect(user1).pay(channelId, ethers.parseUnits("50", 18)))
        .to.emit(ytPay, "PaymentSent")
        .withArgs(
          ethers.keccak256(ethers.toUtf8Bytes(channelId)),
          channelId,
          user1.address,
          user2.address,
          ethers.parseUnits("50", 18)
        );

      const balanceAfter = await pyUSDC.balanceOf(user2.address);
      expect(balanceAfter - balanceBefore).to.equal(ethers.parseUnits("50", 18));
    });

    it("should revert if amount is zero", async function () {
      await expect(ytPay.connect(user1).pay("channel3", 0))
        .to.be.revertedWith("Invalid amount");
    });
  });

  describe("registerChannel()", function () {
    it("should register a channel and release locked funds", async function () {
      const channelId = "channel4";

      // user1 pays before registration
      await pyUSDC.connect(user1).approve(ytPay.target, ethers.parseUnits("100", 18));
      await ytPay.connect(user1).pay(channelId, ethers.parseUnits("100", 18));

      const balanceBefore = await pyUSDC.balanceOf(user2.address);

      await expect(ytPay.connect(owner).registerChannel(channelId, user2.address))
        .to.emit(ytPay, "ChannelRegistered")
        .withArgs(ethers.keccak256(ethers.toUtf8Bytes(channelId)), channelId, user2.address)
        .and.to.emit(ytPay, "FundsReleased")
        .withArgs(
          ethers.keccak256(ethers.toUtf8Bytes(channelId)),
          channelId,
          user2.address,
          ethers.parseUnits("100", 18)
        );

      const balanceAfter = await pyUSDC.balanceOf(user2.address);
      expect(balanceAfter - balanceBefore).to.equal(ethers.parseUnits("100", 18));

      const ch = await ytPay.getChannel(channelId);
      expect(ch.registered).to.be.true;
      expect(ch.locked).to.equal(0n);
    });

    it("should revert if trying to register twice", async function () {
      const channelId = "channel5";
      await ytPay.connect(owner).registerChannel(channelId, user2.address);
      await expect(ytPay.connect(owner).registerChannel(channelId, user2.address))
        .to.be.revertedWith("Already registered");
    });

    it("should revert if wallet is zero address", async function () {
      await expect(ytPay.connect(owner).registerChannel("channel6", ethers.ZeroAddress))
        .to.be.revertedWith("Invalid wallet");
    });
  });

  describe("getChannel()", function () {
    it("should return correct channel info", async function () {
      const channelId = "channel7";
      let ch = await ytPay.getChannel(channelId);
      expect(ch.wallet).to.equal(ethers.ZeroAddress);
      expect(ch.registered).to.be.false;
      expect(ch.locked).to.equal(0n);

      // Register and check again
      await ytPay.connect(owner).registerChannel(channelId, user2.address);
      ch = await ytPay.getChannel(channelId);
      expect(ch.wallet).to.equal(user2.address);
      expect(ch.registered).to.be.true;
      expect(ch.locked).to.equal(0n);
    });
  });
});
