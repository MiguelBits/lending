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
            console2.log("VRF subscription id", subscriptionId);

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
            console2.log("VRFsubscription id", subscriptionId);
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
            
            vrfCoordinator.fulfillRandomWords(subscriptionId, address(slotMachine));

        vm.stopPrank();

        
        //TODO : fulfillRandomWordsWithOverride allows the user to pass in their own random words.
    }
    
} 