const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("TreasureHunt", function () {
  let TreasureHunt;
  let treasureHunt;
  let owner;
  let player1;
  let player2;

  function isValidPrime(num) {
    // Check if the number is within the valid range
    if (num < 2 || num > 99) {
      return false;
    }

    // Check for primality
    for (let i = 2; i <= Math.sqrt(num); i++) {
      if (num % i === 0) {
        return false; // Not a prime number
      }
    }

    return true; // It's a prime number
  }

  beforeEach(async function () {
    [owner, player1, player2] = await ethers.getSigners();
    TreasureHunt = await ethers.getContractFactory("TreasureHunt");
    treasureHunt = await TreasureHunt.deploy();
    await treasureHunt.waitForDeployment();
  });

  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      expect(await treasureHunt.owner()).to.equal(owner.address);
    });

    it("Should initialize treasure position", async function () {
      const position = await treasureHunt.treasurePosition();
      expect(position).to.be.lt(100);
    });
  });

  describe("Joining the game", function () {
    it("Should allow a player to join with sufficient bet", async function () {
      await expect(
        treasureHunt
          .connect(player1)
          .joinGame({ value: ethers.parseEther("0.01") })
      )
        .to.emit(treasureHunt, "PlayerJoined")
        .withArgs(player1.address);
    });

    it("Should not allow a player to join with insufficient bet", async function () {
      await expect(
        treasureHunt
          .connect(player1)
          .joinGame({ value: ethers.parseEther("0.009") })
      ).to.be.revertedWithCustomError(treasureHunt, "InsufficientBet");
    });

    it("Should not allow a player to join twice", async function () {
      await treasureHunt
        .connect(player1)
        .joinGame({ value: ethers.parseEther("0.01") });
      await expect(
        treasureHunt
          .connect(player1)
          .joinGame({ value: ethers.parseEther("0.01") })
      ).to.be.revertedWithCustomError(treasureHunt, "PlayerAlreadyJoined");
    });

    it("Should not allow more than MAX_PLAYERS to join", async function () {
      for (let i = 0; i < 100; i++) {
        const wallet = ethers.Wallet.createRandom().connect(ethers.provider);
        await owner.sendTransaction({
          to: wallet.address,
          value: ethers.parseEther("1"),
        });
        await treasureHunt
          .connect(wallet)
          .joinGame({ value: ethers.parseEther("0.01") });
      }
      await expect(
        treasureHunt
          .connect(player1)
          .joinGame({ value: ethers.parseEther("0.01") })
      ).to.be.revertedWithCustomError(treasureHunt, "MaxPlayersReached");
    });
  });

  describe("Moving", function () {
    beforeEach(async function () {
      await treasureHunt
        .connect(player1)
        .joinGame({ value: ethers.parseEther("0.01") });
    });

    it("Should allow a valid move", async function () {
      const initialPosition = Number(
        (await treasureHunt.players(player1.address)).position
      );
      const newPosition = (initialPosition + 1) % 100;
      await expect(treasureHunt.connect(player1).move(newPosition))
        .to.emit(treasureHunt, "PlayerMoved")
        .withArgs(player1.address);
    });

    it("Should not allow an invalid move", async function () {
      const initialPosition = Number(
        (await treasureHunt.players(player1.address)).position
      );
      const invalidPosition = (initialPosition + 2) % 100;
      await expect(
        treasureHunt.connect(player1).move(invalidPosition)
      ).to.be.revertedWithCustomError(treasureHunt, "InvalidMove");
    });

    it("Should not allow a non-joined player to move", async function () {
      await expect(
        treasureHunt.connect(player2).move(0)
      ).to.be.revertedWithCustomError(treasureHunt, "PlayerNotJoined");
    });

    it("Should move treasure when player lands on multiple of 5", async function () {
      const initialTreasurePosition = Number(
        await treasureHunt.treasurePosition()
      );
      let playerPosition = Number(
        (await treasureHunt.players(player1.address)).position
      );
      let moved;
      // Move to the nearest multiple of 5
      while (playerPosition % 5 !== 0) {
        playerPosition = (playerPosition + 1) % 100;
        await treasureHunt.connect(player1).move(playerPosition);
        moved = true;
      }
      if (moved) {
        const newTreasurePosition = Number(
          await treasureHunt.treasurePosition()
        );
        expect(newTreasurePosition).to.not.equal(initialTreasurePosition);
      }
    });

    it("Should move treasure to random position when player lands on prime", async function () {
      const initialTreasurePosition = Number(
        await treasureHunt.treasurePosition()
      );
      let playerPosition = Number(
        (await treasureHunt.players(player1.address)).position
      );

      let moved;

      while (!isValidPrime(playerPosition)) {
        playerPosition = (playerPosition + 1) % 100;

        await treasureHunt.connect(player1).move(playerPosition);
        moved = true;
      }
      if (moved) {
        const newTreasurePosition = Number(
          await treasureHunt.treasurePosition()
        );
        expect(newTreasurePosition).to.not.equal(initialTreasurePosition);
      }
    });
  });

  describe("Winning the game", function () {
    beforeEach(async function () {
      await treasureHunt
        .connect(player1)
        .joinGame({ value: ethers.parseEther("0.01") });
      await treasureHunt
        .connect(player2)
        .joinGame({ value: ethers.parseEther("0.01") });
    });

    it("Should end the game and distribute prize when treasure is found", async function () {
      let treasurePosition = Number(await treasureHunt.treasurePosition());
      let playerPosition = Number(
        (await treasureHunt.players(player1.address)).position
      );
      let finalDiff;
      // Move player1 to the treasure position
      while (playerPosition !== treasurePosition) {
        const diff = (treasurePosition - playerPosition + 100) % 100;
        if (diff === 1 || diff === 99) {
          finalDiff = 1;
          break;
        } else if (diff === 10) {
          finalDiff = 10;
          break;
        } else if (diff < 10) {
          playerPosition = (playerPosition + 1) % 100;
        } else {
          playerPosition = (playerPosition + 10) % 100;
        }

        await treasureHunt.connect(player1).move(playerPosition);
        treasurePosition = Number(await treasureHunt.treasurePosition());
      }
      const initialBalance = await ethers.provider.getBalance(player1.address);
      await expect(
        treasureHunt.connect(player1).move(playerPosition + finalDiff)
      )
        .to.emit(treasureHunt, "GameWon")
        .withArgs(player1.address, ethers.parseEther("0.018")); // 90% of 0.02 ETH

      const finalBalance = await ethers.provider.getBalance(player1.address);
      expect(finalBalance - initialBalance).to.be.closeTo(
        ethers.parseEther("0.018"),
        ethers.parseEther("0.001") // Allow for gas costs
      );
    });
  });

  describe("Emergency withdrawal", function () {
    it("Should allow owner to withdraw funds", async function () {
      await treasureHunt
        .connect(player1)
        .joinGame({ value: ethers.parseEther("0.01") });
      const initialBalance = await ethers.provider.getBalance(owner.address);

      await expect(treasureHunt.connect(owner).emergencyWithdraw())
        .to.emit(treasureHunt, "EmergencyWithdrawal")
        .withArgs(owner.address, ethers.parseEther("0.01"));

      const finalBalance = await ethers.provider.getBalance(owner.address);
      expect(finalBalance - initialBalance).to.be.closeTo(
        ethers.parseEther("0.01"),
        ethers.parseEther("0.001") // Allow for gas costs
      );
    });
    it("Should not allow non-owner to withdraw funds", async function () {
      await treasureHunt
        .connect(player1)
        .joinGame({ value: ethers.parseEther("0.01") });
      await expect(
        treasureHunt.connect(player1).emergencyWithdraw()
      ).to.be.revertedWithCustomError(
        treasureHunt,
        "OwnableUnauthorizedAccount"
      );
    });

    it("Should reset game state after emergency withdraw", async function () {
      await treasureHunt
        .connect(player1)
        .joinGame({ value: ethers.parseEther("0.01") });

      // Emergency withdraw resets the game state
      await treasureHunt.connect(owner).emergencyWithdraw();
      expect((await treasureHunt.players(player1.address)).hasJoined).to.be
        .false;
    });
  });

  describe("Edge cases", function () {
    beforeEach(async function () {
      await treasureHunt
        .connect(player1)
        .joinGame({ value: ethers.parseEther("0.01") });
      await treasureHunt
        .connect(player2)
        .joinGame({ value: ethers.parseEther("0.01") });
    });

    it("Should handle wrapping around the grid edges", async function () {
      // Move to right edge
      while (
        Number((await treasureHunt.players(player1.address)).position) % 10 !=
        9
      ) {
        await treasureHunt
          .connect(player1)
          .move(
            (Number((await treasureHunt.players(player1.address)).position) +
              1) %
              100
          );
      }

      // Move right (should wrap to left edge)
      await treasureHunt
        .connect(player1)
        .move(
          (Number((await treasureHunt.players(player1.address)).position) + 1) %
            100
        );
      expect(
        Number((await treasureHunt.players(player1.address)).position) % 10
      ).to.equal(0);

      // Move to bottom edge
      while (
        Number((await treasureHunt.players(player1.address)).position) < 90
      ) {
        await treasureHunt
          .connect(player1)
          .move(
            Number((await treasureHunt.players(player1.address)).position) + 10
          );
      }

      // Move down (should wrap to top edge)
      await treasureHunt
        .connect(player1)
        .move(
          Number((await treasureHunt.players(player1.address)).position) - 90
        );
      expect(
        Number((await treasureHunt.players(player1.address)).position)
      ).to.be.lt(10);
    });

    it("Should reset game state after a win", async function () {
      let treasurePosition = Number(await treasureHunt.treasurePosition());
      let playerPosition = Number(
        (await treasureHunt.players(player1.address)).position
      );
      let finalDiff;

      // Move player1 to the treasure position
      while (playerPosition !== treasurePosition) {
        const diff = (treasurePosition - playerPosition + 100) % 100;
        if (diff === 1 || diff === 99) {
          finalDiff = 1;
          break;
        } else if (diff === 10) {
          finalDiff = 10;
          break;
        } else if (diff < 10) {
          playerPosition = (playerPosition + 1) % 100;
        } else {
          playerPosition = (playerPosition + 10) % 100;
        }
        await treasureHunt.connect(player1).move(playerPosition);
        treasurePosition = Number(await treasureHunt.treasurePosition());
      }

      // Win the game
      await treasureHunt.connect(player1).move(playerPosition + finalDiff);

      // Check game state reset
      expect((await treasureHunt.players(player1.address)).hasJoined).to.be
        .false;
      expect((await treasureHunt.players(player2.address)).hasJoined).to.be
        .false;
      expect(await treasureHunt.treasurePosition()).to.not.equal(
        treasurePosition
      );
    });
  });

  describe("Randomness", function () {
    it("Should generate different and non-predictable random positions", async function () {
      const positions = new Set();
      for (let i = 0; i < 50; i++) {
        const wallet = ethers.Wallet.createRandom().connect(ethers.provider);
        await owner.sendTransaction({
          to: wallet.address,
          value: ethers.parseEther("1"),
        });

        await treasureHunt
          .connect(wallet)
          .joinGame({ value: ethers.parseEther("0.01") });
        const position = Number(
          (await treasureHunt.players(wallet.address)).position
        );
        positions.add(position);

        // Emergency withdraw to reset the state
        await treasureHunt.connect(owner).emergencyWithdraw();
      }
      expect(positions.size).to.be.gt(5); // Expect more than 5 unique positions
    });

    it("Should ensure randomness can't be manipulated", async function () {
      const blockNumber = await ethers.provider.getBlockNumber();
      await treasureHunt
        .connect(player1)
        .joinGame({ value: ethers.parseEther("0.01") });

      const initialTreasurePosition = Number(
        await treasureHunt.treasurePosition()
      );
      let playerPosition = Number(
        (await treasureHunt.players(player1.address)).position
      );
      let moved;
      while (!isValidPrime(playerPosition)) {
        playerPosition = (playerPosition + 1) % 100;
        await treasureHunt.connect(player1).move(playerPosition); // Prime number test
        moved = true;
      }

      if (moved) {
        const newBlockNumber = await ethers.provider.getBlockNumber();
        expect(initialTreasurePosition).to.not.equal(
          Number(await treasureHunt.treasurePosition())
        );
        expect(newBlockNumber).to.be.gt(blockNumber);
      }
    });
  });

  describe("Gas usage", function () {
    it("Should have reasonable and efficient gas costs for joining", async function () {
      const tx = await treasureHunt
        .connect(player1)
        .joinGame({ value: ethers.parseEther("0.01") });
      const receipt = await tx.wait();
      expect(receipt.gasUsed).to.be.lt(200000);

      // Test joining efficiency near MAX_PLAYERS
      for (let i = 0; i < 98; i++) {
        const wallet = ethers.Wallet.createRandom().connect(ethers.provider);
        await owner.sendTransaction({
          to: wallet.address,
          value: ethers.parseEther("1"),
        });
        await treasureHunt
          .connect(wallet)
          .joinGame({ value: ethers.parseEther("0.01") });
      }

      const lastJoinTx = await treasureHunt
        .connect(player2)
        .joinGame({ value: ethers.parseEther("0.01") });
      const lastJoinReceipt = await lastJoinTx.wait();
      expect(lastJoinReceipt.gasUsed).to.be.lt(250000); // Slightly higher limit for last join
    });

    it("Should have reasonable gas costs for moving", async function () {
      await treasureHunt
        .connect(player1)
        .joinGame({ value: ethers.parseEther("0.01") });
      const tx = await treasureHunt
        .connect(player1)
        .move(
          (Number((await treasureHunt.players(player1.address)).position) + 1) %
            100
        );
      const receipt = await tx.wait();
      expect(receipt.gasUsed).to.be.lt(100000); // Adjust this value based on your requirements
    });

    it("Should have gas-efficient moves for large number of players", async function () {
      for (let i = 0; i < 50; i++) {
        const wallet = ethers.Wallet.createRandom().connect(ethers.provider);
        await owner.sendTransaction({
          to: wallet.address,
          value: ethers.parseEther("1"),
        });
        await treasureHunt
          .connect(wallet)
          .joinGame({ value: ethers.parseEther("0.01") });
      }
      // Ensure player1 joins the game
      await treasureHunt
        .connect(player1)
        .joinGame({ value: ethers.parseEther("0.01") });
      let playerPosition = Number(
        (await treasureHunt.players(player1.address)).position
      );
      playerPosition = (playerPosition + 1) % 100;

      // Ensure move gas usage stays below expected threshold for multiple players
      const tx = await treasureHunt.connect(player1).move(playerPosition);
      const receipt = await tx.wait();
      expect(receipt.gasUsed).to.be.lt(100000);
    });
  });
});
