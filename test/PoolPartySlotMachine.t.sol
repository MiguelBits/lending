// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {PoolPartyToken} from "../src/PoolPartyToken.sol";
import {PoolPartySlotMachine} from "../src/PoolPartySlotMachine.sol";
import {Upgrades} from "@openzeppelin-foundry-upgrades/Upgrades.sol";
import {VRFCoordinatorV2Mock} from "./utils/VRFCoordinatorV2Mock.sol";

contract PoolPartySlotMachineTest is Test {
    PoolPartyToken public token;
    address public slotMachine_proxy; // proxy instance
    PoolPartySlotMachine public slotMachine; // implementation instance
    VRFCoordinatorV2Mock public vrfCoordinator;

    // Test addresses
    address public deployer = address(0x1);
    address public player = address(0x2);
    
    // Slot machine constants
    uint256 private constant SLOT_A_MAX_VALUE = 11; // Slot A: 0-11
    uint256 private constant SLOT_B_MAX_VALUE = 12; // Slot B: 0-12
    uint256 private constant SLOT_C_MAX_VALUE = 13; // Slot C: 0-13
    
    // Slot machine parameters
    uint256 public tokenBurnAmount = 100 * 10**18; // 100 tokens
    bytes32 public gasLane = bytes32(uint256(1)); // just a mock value
    uint64 public subscriptionId = 1; // mock subscription id
    uint32 public callbackGasLimit = 1000000; // mock gas limit
    
    function setUp() public {
        // Set up accounts
        vm.startPrank(deployer);
        
        // Deploy the token contract
        token = new PoolPartyToken(deployer);
        
        // Deploy VRF mock
        vrfCoordinator = new VRFCoordinatorV2Mock(
            uint96(0.0001 ether), // base fee
            uint96(0.0001 ether) // gas price link
        );

        // Deploy the slot machine implementation

        //Upgrades proxy
        slotMachine_proxy = Upgrades.deployUUPSProxy(
            "PoolPartySlotMachine.sol",
            abi.encodeCall(PoolPartySlotMachine.initialize, (address(vrfCoordinator), gasLane, subscriptionId, callbackGasLimit, address(token), tokenBurnAmount, deployer))
        );

        slotMachine = PoolPartySlotMachine(payable(slotMachine_proxy));
        
        // Add slot machine as a hooker to mint tokens
        token.mint(player, 1000 * 10**18); // Mint 1000 tokens to player
        
        vm.stopPrank();
    }
    
} 