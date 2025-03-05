// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console2} from "forge-std/Test.sol";
import {PoolPartyToken} from "../src/PoolPartyToken.sol";
import {SlotMachine} from "../src/SlotMachine.sol";
import {Upgrades} from "@openzeppelin-foundry-upgrades/Upgrades.sol";

//VRF imports are fucking stupid and hard to get working
import {VRFCoordinatorV2_5Mock} from "../lib/chainlink/contracts/src/v0.8/vrf/mocks/VRFCoordinatorV2_5Mock.sol";

contract SlotMachineTest is Test {

    address public slotMachine_proxy; // proxy instance
    SlotMachine public slotMachine; // implementation instance

    // Test addresses
    address public deployer = 0xE419f5c05fd2377F75cdADF87C3529F0C9B59FCb;
    address public player = address(0x2);
    
    // Slot machine constants
    uint256 private constant SLOT_A_MAX_VALUE = 11; // Slot A: 0-11
    uint256 private constant SLOT_B_MAX_VALUE = 12; // Slot B: 0-12
    uint256 private constant SLOT_C_MAX_VALUE = 13; // Slot C: 0-13
    uint256 private constant NUM_SLOTS = 3;
    
    // Slot machine parameters
    uint256 public tokenBurnAmount = 100 * 10**18; // 100 tokens
    uint256 public subscriptionId; // Will be set in setUp
    uint32 public callbackGasLimit = 1000000; // mock gas limit

    // Mainnet RPC URL environment variable name
    string constant MAINNET_RPC_URL = "MAINNET_RPC_URL";
    
    // Block number to fork from - you might want to adjust this
    uint256 constant FORK_BLOCK_NUMBER = 21961311; // 2nd March 2025 block number

    //VRF variables and shit from mainnet //      bytes32 gasLane,uint256 subscriptionId,uint32 callbackGasLimit,
    VRFCoordinatorV2_5Mock public vrfCoordinator;
    bytes32 public gasLane = 0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae;

    //Game token
    PoolPartyToken public token;
    
    function setUp() public {
        // Create and select the fork
        vm.createSelectFork(vm.envString(MAINNET_RPC_URL), FORK_BLOCK_NUMBER);

        // Fund our users.
        //vm.deal(deployer, 10 ether);

        // Set up accounts
        vm.startPrank(deployer);

            // Deploy the VRF coordinator mock
            vrfCoordinator = new VRFCoordinatorV2_5Mock(100000000000000000, 1000000000,7331922193189670);
            
            // Deploy the token contract
            token = new PoolPartyToken(deployer);
            
            // Create subscription for VRF
            subscriptionId = vrfCoordinator.createSubscription();

            // Deploy the slot machine implementation using UUPS proxy
            slotMachine_proxy = Upgrades.deployUUPSProxy(
                "SlotMachine.sol",
                abi.encodeCall(SlotMachine.initialize, 
                (
                    address(vrfCoordinator), 
                    gasLane, 
                    subscriptionId, 
                    callbackGasLimit, 
                    address(token), 
                    tokenBurnAmount, 
                    deployer))
            );

            slotMachine = SlotMachine(payable(slotMachine_proxy));
            
            // Add slot machine as consumer to VRF subscription
            vrfCoordinator.addConsumer(subscriptionId, address(slotMachine));

            // Fund the subscription with 100 ether
            vrfCoordinator.fundSubscription(subscriptionId, 100 ether);

            //check if the subscription is funded
            console2.log("VRF subscription id", subscriptionId);
            (uint96 balance, uint96 nativeBalance, uint64 reqCount, address owner, ) = vrfCoordinator.getSubscription(subscriptionId);
            console2.log("VRF balance", balance);
            console2.log("VRF nativeBalance", nativeBalance);
            console2.log("VRF reqCount", reqCount);
            console2.log("VRF owner", owner);
            
            // Mint tokens to player
            token.mint(player, 1000 * 10**18); // Mint 1000 tokens to player
            token.addHooker(address(slotMachine));

            //assertTrue for all the variables
            assertTrue(slotMachine.poolPartyToken() == token);
            assertTrue(slotMachine.tokenBurnAmount() == tokenBurnAmount);
            
        vm.stopPrank();

    }
    
    // Test basic slot machine play with random results
    function testBasicPlay() public {

        //log player tokens
        console2.log("Player tokens:", token.balanceOf(player));
        console2.log("Slot machine tokens:", token.balanceOf(address(slotMachine)));
        vm.startPrank(player);
            
            // Approve tokens for burning
            token.approve(address(slotMachine), tokenBurnAmount);
            
            // Initial balance
            uint256 initialBalance = token.balanceOf(player);
            
            // Play the slot
            uint256 requestId = slotMachine.playSlot();
            console2.log("Request Game ID:", requestId);
            // Check if tokens were burned
            assertEq(token.balanceOf(player), initialBalance - tokenBurnAmount, "Tokens should be burned");
            
        vm.stopPrank();

        vrfCoordinator.fulfillRandomWords(requestId, address(slotMachine));

        //show slot results
        (uint256[NUM_SLOTS] memory results, bool ready) = slotMachine.getSlotResults(player);
        console2.log("Slot results:", results[0], results[1], results[2]);
        console2.log("Slot results ready:", ready);
    }

    function testJackpot777() public {
        // Create a test mock for VRF fulfillment that will produce 7-7-7
        uint256[] memory rigged = new uint256[](3);
        
        // Formula: For any value % x to equal y, use (x*k + y) where k is any non-negative integer
        rigged[0] = 12 * 1000 + 7;  // Will give 7 when % 12
        rigged[1] = 13 * 1000 + 7;  // Will give 7 when % 13
        rigged[2] = 14 * 1000 + 7;  // Will give 7 when % 14
    
        //log player tokens
        console2.log("Player tokens:", token.balanceOf(player));
        console2.log("Slot machine tokens:", token.balanceOf(address(slotMachine)));
        vm.startPrank(player);
            
            // Approve tokens for burning
            token.approve(address(slotMachine), tokenBurnAmount);
            
            // Initial balance
            uint256 initialBalance = token.balanceOf(player);
            
            // Play the slot
            uint256 requestId = slotMachine.playSlot();
            console2.log("Request Game ID:", requestId);
            // Check if tokens were burned
            assertEq(token.balanceOf(player), initialBalance - tokenBurnAmount, "Tokens should be burned");
            
        vm.stopPrank();

        vrfCoordinator.fulfillRandomWordsWithOverride(requestId, address(slotMachine), rigged);

        //show slot results
        (uint256[NUM_SLOTS] memory results, bool ready) = slotMachine.getSlotResults(player);
        console2.log("Slot results:", results[0], results[1], results[2]);
        console2.log("Slot results ready:", ready);

        //check if the player has a free spin
        assertEq(slotMachine.checkFreeSpin(player), true, "Player should have a free spin");

        vm.startPrank(player);
            
            // Play the slot
            requestId = slotMachine.playSlot();
            console2.log("Request Game ID:", requestId);
            // Check if tokens were burned
            assertEq(token.balanceOf(player), initialBalance - tokenBurnAmount, "Tokens should not be burned");
            
        vm.stopPrank();

        rigged[0] = 12 * 1000 + 4;  // Will give 4 when % 12
        rigged[1] = 13 * 1000 + 2;  // Will give 2 when % 13
        rigged[2] = 14 * 1000 + 0;  // Will give 0 when % 14

        vrfCoordinator.fulfillRandomWordsWithOverride(requestId, address(slotMachine), rigged);

        //show slot results
        (results, ready) = slotMachine.getSlotResults(player);
        console2.log("Slot results:", results[0], results[1], results[2]);
        console2.log("Slot results ready:", ready);

        //check if the player does not have a free spin
        assertEq(slotMachine.checkFreeSpin(player), false, "Player should not have a free spin");

    }
} 