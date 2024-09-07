// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title TreasureHunt
/// @notice A smart contract for an on-chain treasure hunt game
/// @dev Inherits from Ownable and ReentrancyGuard for security
contract TreasureHunt is Ownable, ReentrancyGuard {
    uint8 public treasurePosition;
    uint8 private nonce;
    uint8 private constant GRID_SIZE = 10;
    uint8 private constant TOTAL_POSITIONS = 100;
    uint8 private constant WINNER_PERCENTAGE = 90;
    uint8 private constant MAX_PLAYERS = 100;
    uint64 private constant MIN_BET = 0.01 ether;

    /// @notice Struct to store player information
    struct Player {
        uint256 position;
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
    error MaxPlayersReached();

    /// @notice Initializes the contract and sets the initial treasure position
    /// @dev The contract is initialized with the deployer as the owner
    constructor() payable Ownable(msg.sender) {
        treasurePosition = getRandomPosition();
    }

    /// @notice Modifier to check if the caller has joined the game
    modifier onlyJoinedPlayer() {
        if (!players[msg.sender].hasJoined) revert PlayerNotJoined();
        _;
    }

    /// @notice Allows a player to join the game by placing a bet
    /// @dev Reverts if the bet is insufficient, player has already joined, or max players reached
    function joinGame() external payable {
        if (msg.value < MIN_BET) revert InsufficientBet();

        Player storage player = players[msg.sender];

        if (player.hasJoined) revert PlayerAlreadyJoined();
        if (playerAddresses.length == MAX_PLAYERS) revert MaxPlayersReached();

        player.position = getRandomPosition();
        player.hasJoined = true;

        playerAddresses.push(msg.sender);

        emit PlayerJoined(msg.sender);
    }

    /// @notice Allows a player to move to a new position
    /// @param newPosition The position the player wants to move to
    /// @dev Checks for valid move, updates treasure position, and ends game if treasure is found
    function move(
        uint256 newPosition
    ) external payable nonReentrant onlyJoinedPlayer {
        if (!isValidMove(players[msg.sender].position, newPosition))
            revert InvalidMove();

        players[msg.sender].position = newPosition;
        emit PlayerMoved(msg.sender);

        if (newPosition == treasurePosition) {
            endGame(msg.sender);
        } else {
            moveTreasure(newPosition);
        }
    }

    /// @notice Moves the treasure based on the player's new position
    /// @param playerPosition The player's new position
    /// @dev Moves treasure to adjacent position if player lands on multiple of 5, or random position if prime
    function moveTreasure(uint256 playerPosition) private {
        uint8 newPosition = treasurePosition;
        if (playerPosition % 5 == 0) {
            newPosition = getRandomAdjacentPosition(treasurePosition);
        } else if (isPrime(playerPosition)) {
            newPosition = getRandomPosition();
        }
        if (newPosition != treasurePosition) {
            treasurePosition = newPosition;
            emit TreasureMoved(treasurePosition);
        }
    }

    /// @notice Ends the game when a player finds the treasure
    /// @param winner The address of the winning player
    /// @dev Transfers prize to winner and resets game state
    function endGame(address winner) private {
        uint256 prize = (address(this).balance * (WINNER_PERCENTAGE)) / 100;
        payable(winner).transfer(prize);
        emit GameWon(winner, prize);

        resetGame();
        treasurePosition = getRandomPosition();
    }

    function resetGame() private {
        // Reset game state
        uint256 length = playerAddresses.length;
        for (uint256 i = 0; i < length; ) {
            delete players[playerAddresses[i]];
            unchecked {
                ++i;
            }
        }
        playerAddresses = new address[](0);
    }

    /// @notice Returns all valid adjacent positions for a given position
    /// @param currentPosition The current position of the player
    /// @return adjacentPositions An array of valid adjacent positions
    function getValidAdjacentPositions(
        uint256 currentPosition
    ) public pure returns (uint256[] memory adjacentPositions) {
        require(currentPosition < TOTAL_POSITIONS, "Invalid position");

        adjacentPositions = new uint256[](4); // Up, Down, Left, Right
        adjacentPositions[0] = (currentPosition + 1) % TOTAL_POSITIONS;
        adjacentPositions[1] =
            (currentPosition + TOTAL_POSITIONS - 1) %
            TOTAL_POSITIONS;
        adjacentPositions[2] = (currentPosition + GRID_SIZE) % TOTAL_POSITIONS;
        adjacentPositions[3] =
            (currentPosition + TOTAL_POSITIONS - GRID_SIZE) %
            TOTAL_POSITIONS;
    }

    /// @notice Checks if a move is valid
    /// @param from The starting position
    /// @param to The ending position
    /// @return bool indicating if the move is valid
    function isValidMove(uint256 from, uint256 to) public pure returns (bool) {
        uint256[] memory validPositions = getValidAdjacentPositions(from);

        // Check if 'to' is in the valid positions
        for (uint256 i; i <= 3; i++) {
            if (validPositions[i] == to) {
                return true; // 'to' is a valid move
            }
            unchecked {
                ++i;
            }
        }

        return false; // 'to' is not a valid move
    }

    /// @notice Gets a random adjacent position
    /// @param position The current position
    /// @return uint8 A random adjacent position
    function getRandomAdjacentPosition(uint8 position) private returns (uint8) {
        uint256 randomValue = getRandomPosition();
        uint256 direction = (randomValue & 3); // Equivalent to % 4, but more gas-efficient

        if (direction == 0) return (position + 1) % TOTAL_POSITIONS;
        if (direction == 1)
            return (position + TOTAL_POSITIONS - 1) % TOTAL_POSITIONS;
        if (direction == 2) return (position + GRID_SIZE) % TOTAL_POSITIONS;
        return (position + TOTAL_POSITIONS - GRID_SIZE) % TOTAL_POSITIONS;
    }

    /// @notice Generates a random position
    /// @return uint8 A random position on the grid
    function getRandomPosition() private returns (uint8) {
        return
            uint8(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            block.number,
                            block.timestamp,
                            msg.sender,
                            nonce++
                        )
                    )
                ) % TOTAL_POSITIONS
            );
    }

    /// @notice Checks if a number is prime
    /// @param n The number to check
    /// @return bool indicating if the number is prime
    function isPrime(uint256 n) private pure returns (bool) {
        if (n <= 1) return false;
        if (n <= 3) return true;
        if (n % 2 == 0 || n % 3 == 0) return false;
        for (uint256 i = 5; i * i <= n; i += 6) {
            if (n % i == 0 || n % (i + 2) == 0) return false;
        }
        return true;
    }

    /// @notice Allows the owner to withdraw all funds in case of emergency
    /// @dev Can only be called by the contract owner
    function emergencyWithdraw() external payable onlyOwner {
        resetGame();
        uint256 balance = address(this).balance;
        payable(owner()).transfer(balance);
        emit EmergencyWithdrawal(owner(), balance);
    }
}
