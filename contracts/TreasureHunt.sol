// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract TreasureHunt is Ownable, ReentrancyGuard {
    uint8 private constant GRID_SIZE = 10;
    uint8 private constant TOTAL_POSITIONS = 100;
    uint8 private constant WINNER_PERCENTAGE = 90;
    uint64 private constant MIN_BET = 0.01 ether;
    uint8 public treasurePosition;

    struct Player {
        uint8 position;
        bool hasJoined;
    }

    mapping(address => Player) public players;
    address[] public playerAddresses;

    event PlayerJoined(address player);
    event PlayerMoved(address player);
    event TreasureMoved(uint8 newPosition);
    event GameWon(address winner, uint256 prize);
    event EmergencyWithdrawal(address to, uint256 amount);

    error InsufficientBet();
    error PlayerAlreadyJoined();
    error PlayerNotJoined();
    error InvalidMove();

    constructor() payable Ownable(msg.sender) {
        treasurePosition = getRandomPosition();
    }

    modifier onlyJoinedPlayer() {
        if (!players[msg.sender].hasJoined) revert PlayerNotJoined();
        _;
    }

    function joinGame() external payable {
        if (msg.value < MIN_BET) revert InsufficientBet();
        if (players[msg.sender].hasJoined) revert PlayerAlreadyJoined();

        uint8 initialPosition = getRandomPosition();
        players[msg.sender].position = initialPosition;
        players[msg.sender].hasJoined = true;
        playerAddresses.push(msg.sender);

        emit PlayerJoined(msg.sender);
    }

    function move(uint8 newPosition) external nonReentrant onlyJoinedPlayer {
        if (!isValidMove(players[msg.sender].position, newPosition))
            revert InvalidMove();

        players[msg.sender].position = newPosition;
        emit PlayerMoved(msg.sender);

        moveTreasure(newPosition);

        if (newPosition == treasurePosition) {
            endGame(msg.sender);
        }
    }

    function moveTreasure(uint8 playerPosition) private {
        if (playerPosition % 5 == 0) {
            treasurePosition = getRandomAdjacentPosition(treasurePosition);
        } else if (isPrime(playerPosition)) {
            treasurePosition = getRandomPosition();
        }
        emit TreasureMoved(treasurePosition);
    }

    function endGame(address winner) private {
        uint256 prize = (address(this).balance * (WINNER_PERCENTAGE)) / 100;
        payable(winner).transfer(prize);
        emit GameWon(winner, prize);

        // Reset game state
        uint256 length = playerAddresses.length;
        for (uint256 i = 0; i < length; ) {
            delete players[playerAddresses[i]];
            unchecked {
                ++i;
            }
        }
        treasurePosition = getRandomPosition();
    }

    function isValidMove(uint8 from, uint8 to) private pure returns (bool) {
        int8 diff = int8(to) - int8(from);
        return
            (diff == 1 ||
                diff == -1 ||
                diff == int8(GRID_SIZE) ||
                diff == -int8(GRID_SIZE)) && to < TOTAL_POSITIONS;
    }

    function getRandomAdjacentPosition(
        uint8 position
    ) private view returns (uint8) {
        uint256 randomValue = getRandomPosition();
        uint256 direction = (randomValue & 3); // Equivalent to % 4, but more gas-efficient
        unchecked {
            if (direction == 0) return (position + 1) % TOTAL_POSITIONS;
            if (direction == 1)
                return (position + TOTAL_POSITIONS - 1) % TOTAL_POSITIONS;
            if (direction == 2) return (position + GRID_SIZE) % TOTAL_POSITIONS;
            return (position + TOTAL_POSITIONS - GRID_SIZE) % TOTAL_POSITIONS;
        }
    }

    function getRandomPosition() private view returns (uint8) {
        return
            uint8(
                uint256(
                    keccak256(abi.encodePacked(block.number, block.timestamp))
                ) % TOTAL_POSITIONS
            );
    }

    function isPrime(uint256 n) private pure returns (bool) {
        if (n <= 1) return false;
        for (uint256 i = 2; i * i <= n; ) {
            if (n % i == 0) return false;
            unchecked {
                ++i;
            }
        }
        return true;
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
        emit EmergencyWithdrawal(owner(), balance);
    }
}
