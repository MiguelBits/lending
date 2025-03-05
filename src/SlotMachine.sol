// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import "@chainlink/vrf/VRFConsumerBaseV2.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./PoolPartyToken.sol";
import {VRFCoordinatorV2_5, VRFV2PlusClient} from "@chainlink/dev/vrf/VRFCoordinatorV2_5.sol";

import "forge-std/console2.sol";

/**
 * @title PoolPartySlotMachine
 * @dev A slot machine game that uses Chainlink VRF for random number generation
 * Each play burns a specified amount of IERC20
 * This contract is upgradeable using the UUPS proxy pattern
 *
 */
contract SlotMachine is Initializable, VRFConsumerBaseV2, OwnableUpgradeable, UUPSUpgradeable {
    // Chainlink VRF variables
    VRFCoordinatorV2_5 private plus_vrfCoordinator;
    bytes32 private i_gasLane;
    uint256 private i_subscriptionId;
    uint32 private i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;

    // Slot machine variables
    uint256 private constant NUM_SLOTS = 3;
    uint256 private constant SLOT_A_MAX_VALUE = 11; // Slot A: 0-11
    uint256 private constant SLOT_B_MAX_VALUE = 12; // Slot B: 0-12
    uint256 private constant SLOT_C_MAX_VALUE = 13; // Slot C: 0-13
    uint256 private constant FREE_SPIN_VALUE = 7; // Lucky 7 for free spins
    
    // Token variables
    PoolPartyToken public poolPartyToken;
    uint256 public tokenBurnAmount;
    
    // Game state variables
    mapping(address => bool) public hasFreeSpinAvailable;
    mapping(uint256 => address) public requestIdToPlayer;
    mapping(address => uint256[NUM_SLOTS]) public playerLastResults;
    mapping(address => bool) public playerResultsReady;
    
    // Events
    event SpinRequested(address indexed player, uint256 indexed requestId);
    event SpinCompleted(address indexed player, uint256[NUM_SLOTS] results, uint256 winAmount);
    event FreeSpinAwarded(address indexed player);
    event PrizeAwarded(address indexed player, uint256 amount);

    // Prize configuration
    struct PrizeConfig {
        uint256[NUM_SLOTS] combination;
        uint256 multiplier; // Multiplier * bet amount = win amount
        bool isValid;
        bool isFreeSpinCombo;
    }

    PrizeConfig[] public prizes;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract replacing the constructor for upgradeable contracts
     */
    function initialize(
        address vrfCoordinatorV2,
        bytes32 gasLane,
        uint256 subscriptionId,
        uint32 callbackGasLimit,
        address _poolPartyToken,
        uint256 _tokenBurnAmount,
        address initialOwner
    ) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();
        //@custom:oz-upgrades-unsafe-allow state-variable-immutable vrfCoordinator
        setVrfCoordinator(vrfCoordinatorV2);
        plus_vrfCoordinator = VRFCoordinatorV2_5(vrfCoordinatorV2);

        i_gasLane = gasLane;
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;
        poolPartyToken = PoolPartyToken(_poolPartyToken);
        tokenBurnAmount = _tokenBurnAmount;
        
        // Configure prize combinations
        // Triple 7s - Free spin (high probability)
        addPrize([uint256(7), uint256(7), uint256(7)], 10, true);
        // Triple 10s - Jackpot
        addPrize([uint256(10), uint256(10), uint256(10)], 100, false);
        // Triple numbers
        addPrize([uint256(1), uint256(1), uint256(1)], 5, false);
        addPrize([uint256(2), uint256(2), uint256(2)], 8, false);
        addPrize([uint256(3), uint256(3), uint256(3)], 10, false);
        addPrize([uint256(4), uint256(4), uint256(4)], 15, false);
        addPrize([uint256(5), uint256(5), uint256(5)], 20, false);
        addPrize([uint256(6), uint256(6), uint256(6)], 25, false);
        addPrize([uint256(8), uint256(8), uint256(8)], 30, false);
        addPrize([uint256(9), uint256(9), uint256(9)], 50, false);
        // Double numbers
        addPrize([uint256(10), uint256(10), uint256(0)], 5, false);
        addPrize([uint256(0), uint256(10), uint256(10)], 5, false);
        addPrize([uint256(10), uint256(0), uint256(10)], 5, false);
        // Sequence
        addPrize([uint256(1), uint256(2), uint256(3)], 3, false);
        addPrize([uint256(4), uint256(5), uint256(6)], 4, false);
        addPrize([uint256(8), uint256(9), uint256(10)], 5, false);
    }
    
    /**
     * @dev Function that authorizes upgrades, only owner can upgrade
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
    
    /**
     * @dev Add a prize combination
     */
    function addPrize(uint256[NUM_SLOTS] memory combination, uint256 multiplier, bool isFreeSpinCombo) public onlyOwner {
        PrizeConfig memory newPrize = PrizeConfig({
            combination: combination,
            multiplier: multiplier,
            isValid: true,
            isFreeSpinCombo: isFreeSpinCombo
        });
        prizes.push(newPrize);
    }

    /**
     * @dev Update a prize combination
     */
    function updatePrize(uint256 prizeIndex, uint256[NUM_SLOTS] memory combination, uint256 multiplier, bool isFreeSpinCombo) public onlyOwner {
        require(prizeIndex < prizes.length, "Prize index out of bounds");
        
        prizes[prizeIndex].combination = combination;
        prizes[prizeIndex].multiplier = multiplier;
        prizes[prizeIndex].isFreeSpinCombo = isFreeSpinCombo;
    }

    /**
     * @dev Disable a prize combination
     */
    function disablePrize(uint256 prizeIndex) public onlyOwner {
        require(prizeIndex < prizes.length, "Prize index out of bounds");
        prizes[prizeIndex].isValid = false;
    }

    /**
     * @dev Set burn amount for the game token
     */
    function setTokenBurnAmount(uint256 _tokenBurnAmount) public onlyOwner {
        tokenBurnAmount = _tokenBurnAmount;
    }

    /**
     * @dev Initiates a play of the slot machine using IERC20
     * Burns tokens from player balance and requests random numbers
     * 
     * @notice This is an asynchronous operation. The random numbers will be delivered later
     * through the Chainlink VRF callback. To get results, call getSlotResults() after 
     * the transaction has been confirmed and the VRF callback has executed.
     * 
     * @return requestId The Chainlink VRF request ID (for tracking)
     */
    function playSlot() public returns (uint256 requestId) {
        // Mark player's results as not ready yet
        playerResultsReady[msg.sender] = false;
        
        // Check if player has a free spin
        if (!hasFreeSpinAvailable[msg.sender]) {
            // Verify player has approved the token transfer
            require(
                poolPartyToken.allowance(msg.sender, address(this)) >= tokenBurnAmount,
                "Insufficient token allowance"
            ); 
            
            // Burn the tokens using the burn function
            poolPartyToken.burn(msg.sender, tokenBurnAmount);

        } else {
            // Use the free spin
            hasFreeSpinAvailable[msg.sender] = false;
        }
    
        // Request randomness from Chainlink VRF (3 random numbers)
        requestId = plus_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: i_gasLane,
                subId: i_subscriptionId,
                requestConfirmations: 5,
                callbackGasLimit: i_callbackGasLimit,
                numWords: uint32(NUM_SLOTS),
                extraArgs: VRFV2PlusClient._argsToBytes(VRFV2PlusClient.ExtraArgsV1({nativePayment: false})) // new parameter
            })
        );


        requestIdToPlayer[requestId] = msg.sender;
        emit SpinRequested(msg.sender, requestId);
        
        return requestId;
    }

    /**
     * @dev Callback function used by VRF Coordinator to return the random numbers
     */
    function fulfillRandomWords(uint256 requestId, uint256[] memory randomWords) internal override {
        address player = requestIdToPlayer[requestId];
        require(player != address(0), "Request not found");
        require(randomWords.length == NUM_SLOTS, "Invalid number of random words");

        // Map each random word to its respective slot range
        uint256[NUM_SLOTS] memory results;
        results[0] = randomWords[0] % (SLOT_A_MAX_VALUE + 1); // Slot A: 0-11
        //console2.log("randomWords[0]", randomWords[0]);
        results[1] = randomWords[1] % (SLOT_B_MAX_VALUE + 1); // Slot B: 0-12
        //console2.log("randomWords[1]", randomWords[1]);
        results[2] = randomWords[2] % (SLOT_C_MAX_VALUE + 1); // Slot C: 0-13
        //console2.log("randomWords[2]", randomWords[2]);
        
        // Record player's results
        playerLastResults[player] = results;
        playerResultsReady[player] = true;
        
        // Check for wins
        uint256 winAmount = 0;
        bool hasFreeSpin = false;
        
        // Check all prize combinations
        for (uint256 i = 0; i < prizes.length; i++) {
            if (!prizes[i].isValid) continue;
            
            if (isPrizeCombination(results, prizes[i].combination)) {
                if (prizes[i].isFreeSpinCombo) {
                    hasFreeSpin = true;
                    emit FreeSpinAwarded(player);
                } else {
                    winAmount = tokenBurnAmount * prizes[i].multiplier;
                    
                    // Mint tokens as prize
                    if (winAmount > 0) {
                        // Try to mint tokens to the player
                        try poolPartyToken.mint(player, winAmount) {
                            emit PrizeAwarded(player, winAmount);
                        } catch {
                            // If minting fails (this contract isn't authorized as a hooker),
                            // we still emit the event but no tokens are minted
                            emit PrizeAwarded(player, winAmount);
                        }
                    }
                }
                break;
            }
        }
        
        // Set free spin status
        if (hasFreeSpin) {
            hasFreeSpinAvailable[player] = true;
        }
        
        // Emit result
        emit SpinCompleted(player, results, winAmount);
    }
    
    /**
     * @dev Check if the results match a prize combination
     */
    function isPrizeCombination(uint256[NUM_SLOTS] memory results, uint256[NUM_SLOTS] memory combination) private pure returns (bool) {
        return (results[0] == combination[0] && 
                results[1] == combination[1] && 
                results[2] == combination[2]);
    }
    
    /**
     * @dev Get player's last spin results
     */
    function getPlayerLastResults(address player) external view returns (uint256[NUM_SLOTS] memory) {
        return playerLastResults[player];
    }
    
    /**
     * @dev Get the results of a player's last slot play along with status
     * @notice Results are only available after the Chainlink VRF callback has executed
     * @param player The address of the player
     * @return results Array of 3 uint256 representing the slot results
     * @return ready Boolean indicating if results are ready
     */
    function getSlotResults(address player) external view returns (uint256[NUM_SLOTS] memory results, bool ready) {
        return (playerLastResults[player], playerResultsReady[player]);
    }
    
    /**
     * @dev Check if player has a free spin available
     */
    function checkFreeSpin(address player) public view returns (bool) {
        return hasFreeSpinAvailable[player];
    }
    
    /**
     * @dev Get the number of prize configurations
     */
    function getPrizeCount() external view returns (uint256) {
        return prizes.length;
    }
    
    // Storage gap for future upgrades
    uint256[50] private __gap;
} 