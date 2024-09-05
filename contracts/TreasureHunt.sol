// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract TreasureHunt is ReentrancyGuard {
    uint8 public constant GRID_SIZE = 10;
    uint8 public constant TOTAL_POSITIONS = 100;
    uint8 public constant WINNER_PERCENTAGE = 90;
    uint64 public constant MIN_BET = 0.01 ether;
    uint8 public treasurePosition;

    struct Player {
        uint8 position;
        bool hasJoined;
    }

    mapping(address => Player) public players;
    address[] public playerAddresses;

    event PlayerJoined(address player, uint8 position);
    event PlayerMoved(address player, uint8 newPosition);
    event TreasureMoved(uint8 newPosition);
    event GameWon(address winner, uint256 prize);

    error InsufficientBet();
    error PlayerAlreadyJoined();
    error PlayerNotJoined();
    error InvalidMove();

    constructor() {
        treasurePosition = uint8(
            uint256(
                keccak256(abi.encodePacked(block.number, block.timestamp))
            ) % TOTAL_POSITIONS
        );
    }

    function joinGame() external payable {
        if (msg.value < MIN_BET) revert InsufficientBet();
        if (players[msg.sender].hasJoined) revert PlayerAlreadyJoined();

        uint8 initialPosition = uint8(
            uint256(keccak256(abi.encodePacked(msg.sender, block.timestamp))) %
                TOTAL_POSITIONS
        );
        players[msg.sender] = Player(initialPosition, true);
        playerAddresses.push(msg.sender);

        emit PlayerJoined(msg.sender, initialPosition);
    }

    function move(uint8 newPosition) external nonReentrant {
        if (!players[msg.sender].hasJoined) revert PlayerNotJoined();
        if (!isValidMove(players[msg.sender].position, newPosition))
            revert InvalidMove();

        players[msg.sender].position = newPosition;
        emit PlayerMoved(msg.sender, newPosition);

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
        for (uint i = 0; i < playerAddresses.length; i++) {
            delete players[playerAddresses[i]];
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
        uint8[4] memory possibleMoves = [
            (position + 1) % TOTAL_POSITIONS,
            (position + TOTAL_POSITIONS - 1) % TOTAL_POSITIONS,
            (position + GRID_SIZE) % TOTAL_POSITIONS,
            (position + TOTAL_POSITIONS - GRID_SIZE) % TOTAL_POSITIONS
        ];
        return
            possibleMoves[
                uint256(
                    keccak256(abi.encodePacked(block.number, block.timestamp))
                ) % 4
            ];
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
        for (uint256 i = 2; i * i <= n; i++) {
            if (n % i == 0) return false;
        }
        return true;
    }

    function getPlayerPosition(address player) external view returns (uint8) {
        if (!players[player].hasJoined) revert PlayerNotJoined();
        return players[player].position;
    }

    function getTreasurePosition() external view returns (uint8) {
        return treasurePosition;
    }
}
