// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolModifyLiquidityTestNoChecks} from "v4-core/src/test/PoolModifyLiquidityTestNoChecks.sol";
import {PoolDonateTest} from "v4-core/src/test/PoolDonateTest.sol";
import {PoolTakeTest} from "v4-core/src/test/PoolTakeTest.sol";
import {PoolClaimsTest} from "v4-core/src/test/PoolClaimsTest.sol";
import {PoolNestedActionsTest} from "v4-core/src/test/PoolNestedActionsTest.sol";
import {ActionsRouter} from "v4-core/src/test/ActionsRouter.sol";
import {Counter} from "../src/Counter.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";

contract UniswapV4Test is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Counter hook;
    PoolId poolId;
    uint128 addedLiquidity; // Store the liquidity amount we added

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    // Test addresses
    address alice;

    // Mainnet deployed addresses
    address constant POOL_MANAGER_ADDRESS = address(0x000000000004444c5dc75cB358380D2e3dE08A90);
    address constant POSITION_MANAGER_ADDRESS = address(0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e);
    address constant WSTETH = address(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    uint256 constant WHALE_AMOUNT_ETH = 10 ether;
    address constant BOLD = address(0xb01dd87B29d187F3E3a4Bf6cdAebfb97F3D9aB98);
    uint256 constant WHALE_AMOUNT_BOLD = 3000 ether;

    
    // Mainnet RPC URL environment variable name
    string constant MAINNET_RPC_URL = "MAINNET_RPC_URL";
    
    // Block number to fork from - you might want to adjust this
    uint256 constant FORK_BLOCK_NUMBER = 21961311; // 2nd March 2025 block number

    // Price constants
    uint160 constant SQRT_PRICE_ETH_3000_X96 = 1771845774611271086;  // sqrt(3000) * 2^96
    
    // Interface for wstETH
    IERC20 constant wsteth = IERC20(WSTETH);

    function setUp() public {
        // Create and select the fork
        vm.createSelectFork(vm.envString(MAINNET_RPC_URL), FORK_BLOCK_NUMBER);

        // Setup test addresses
        alice = makeAddr("alice");
        
        // Use the deployed PoolManager
        manager = IPoolManager(POOL_MANAGER_ADDRESS);
        
        // Initialize test routers with the real manager
        swapRouter = new PoolSwapTest(manager);
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        modifyLiquidityNoChecks = new PoolModifyLiquidityTestNoChecks(manager);
        donateRouter = new PoolDonateTest(manager);
        takeRouter = new PoolTakeTest(manager);
        claimsRouter = new PoolClaimsTest(manager);
        nestedActionRouter = new PoolNestedActionsTest(manager);
        feeController = makeAddr("feeController");
        actionsRouter = new ActionsRouter(manager);

        // Setup tokens (ensure they're ordered)
        if (WSTETH < BOLD) {
            currency0 = Currency.wrap(WSTETH);
            currency1 = Currency.wrap(BOLD);

            console.log("WSTETH is currency0");
            deal(Currency.unwrap(currency0), alice, WHALE_AMOUNT_ETH);
            deal(Currency.unwrap(currency1), alice, WHALE_AMOUNT_BOLD);
        } else {
            currency0 = Currency.wrap(BOLD);
            currency1 = Currency.wrap(WSTETH);

            console.log("BOLD is currency0");
            deal(Currency.unwrap(currency0), alice, WHALE_AMOUNT_BOLD);
            deal(Currency.unwrap(currency1), alice, WHALE_AMOUNT_ETH);
        }

        console.log("currency0 balance before:", IERC20(Currency.unwrap(currency0)).balanceOf(alice));
        console.log("currency1 balance before:", IERC20(Currency.unwrap(currency1)).balanceOf(alice));
        
        console.log("currency0 balance after deal:", IERC20(Currency.unwrap(currency0)).balanceOf(alice));
        console.log("currency1 balance after deal:", IERC20(Currency.unwrap(currency1)).balanceOf(alice));

        // Use the deployed PositionManager
        posm = IPositionManager(POSITION_MANAGER_ADDRESS);

        // Setup approvals for PositionManager (as Alice)
        vm.startPrank(alice);
            etchPermit2();
            IERC20(Currency.unwrap(currency0)).approve(address(permit2), type(uint256).max);
            IERC20(Currency.unwrap(currency1)).approve(address(permit2), type(uint256).max);
            permit2.approve(Currency.unwrap(currency0), address(posm), type(uint160).max, type(uint48).max);
            permit2.approve(Currency.unwrap(currency1), address(posm), type(uint160).max, type(uint48).max);
            // Add approvals for swap router
            IERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
            IERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
        vm.stopPrank();

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                    | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager); //Add all the necessary constructor arguments from the hook
        deployCodeTo("Counter.sol:Counter", constructorArgs, flags);
        hook = Counter(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        // Initialize at ETH = 3000
        uint160 initSqrtPriceX96;
        if (Currency.unwrap(currency0) == WSTETH) {
            // If ETH is token0, price = token1/token0 = 3000
            initSqrtPriceX96 = SQRT_PRICE_ETH_3000_X96;
        } else {
            // If ETH is token1, price = token0/token1 = 1/3000
            initSqrtPriceX96 = uint160(4295128739) / SQRT_PRICE_ETH_3000_X96;
        }
        manager.initialize(key, initSqrtPriceX96);

        // Provide concentrated liquidity around current price
        tickLower = TickMath.minUsableTick(60); // Use wider range for more liquidity
        tickUpper = TickMath.maxUsableTick(60);

        // Calculate liquidity amount from our desired token amounts (1 WSTETH and 3000 BOLD)
        uint256 amount0Desired;
        uint256 amount1Desired;
        if (Currency.unwrap(currency0) == WSTETH) {
            amount0Desired = 1 ether;     // 1 WSTETH
            amount1Desired = 3000 ether;  // 3000 BOLD
        } else {
            amount0Desired = 3000 ether;  // 3000 BOLD
            amount1Desired = 1 ether;     // 1 WSTETH
        }

        uint128 liquidityAmount = LiquidityAmounts.getLiquidityForAmounts(
            initSqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Desired,
            amount1Desired
        );
        addedLiquidity = liquidityAmount; // Store for later use

        console.log("Calculated liquidity amount:", liquidityAmount);
        console.log("Adding liquidity:");
        if (Currency.unwrap(currency0) == WSTETH) {
            console.log("WSTETH amount:", amount0Desired);
            console.log("BOLD amount:", amount1Desired);
        } else {
            console.log("BOLD amount:", amount0Desired);
            console.log("WSTETH amount:", amount1Desired);
        }

        // Make sure we have enough tokens
        require(amount0Desired <= (Currency.unwrap(currency0) == WSTETH ? WHALE_AMOUNT_ETH : WHALE_AMOUNT_BOLD), "Not enough token0");
        require(amount1Desired <= (Currency.unwrap(currency1) == WSTETH ? WHALE_AMOUNT_ETH : WHALE_AMOUNT_BOLD), "Not enough token1");

        // Mint position as Alice
        vm.startPrank(alice);
            (tokenId,) = posm.mint(
                key,
                tickLower,
                tickUpper,
                liquidityAmount,
                amount0Desired * 101 / 100, // Add 1% slippage tolerance
                amount1Desired * 101 / 100, // Add 1% slippage tolerance
                alice,
                block.timestamp,
                ZERO_BYTES
            );
        vm.stopPrank();
    }

    function testCounterHooks() public {
        // positions were created in setup()
        assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 0);

        assertEq(hook.beforeSwapCount(poolId), 0);
        assertEq(hook.afterSwapCount(poolId), 0);

        // Perform a test swap //
        bool zeroForOne = true;
        int256 amountSpecified = -1 ether; // negative number indicates exact input swap!
        vm.startPrank(alice);
            BalanceDelta swapDelta = swapRouter.swap(
                key,
                IPoolManager.SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: amountSpecified,
                    sqrtPriceLimitX96: zeroForOne ? MIN_PRICE_LIMIT : MAX_PRICE_LIMIT
                }),
                PoolSwapTest.TestSettings({takeClaims: true, settleUsingBurn: false}),
                ZERO_BYTES
            );
        vm.stopPrank();
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);

        assertEq(hook.beforeSwapCount(poolId), 1);
        assertEq(hook.afterSwapCount(poolId), 1);
    }

    function testLiquidityHooks() public {
        // positions were created in setup()
        assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 0);

        vm.startPrank(alice);
            // remove liquidity - use the same amount we added
            posm.decreaseLiquidity(
                tokenId,
                addedLiquidity,
                MAX_SLIPPAGE_REMOVE_LIQUIDITY,
                MAX_SLIPPAGE_REMOVE_LIQUIDITY,
                alice,
                block.timestamp,
                ZERO_BYTES
            );
        vm.stopPrank();

        assertEq(hook.beforeAddLiquidityCount(poolId), 1);
        assertEq(hook.beforeRemoveLiquidityCount(poolId), 1);

        console.log("currency0 balance after remove liquidity:", IERC20(Currency.unwrap(currency0)).balanceOf(alice));
        console.log("currency1 balance after remove liquidity:", IERC20(Currency.unwrap(currency1)).balanceOf(alice));
    }

    function testWstETHSwap() public {
        // Log initial balances
        console.log("Initial currency0 balance:", IERC20(Currency.unwrap(currency0)).balanceOf(alice));
        console.log("Initial currency1 balance:", IERC20(Currency.unwrap(currency1)).balanceOf(alice));

        vm.startPrank(alice);
            // Approve tokens for the swap router
            IERC20(Currency.unwrap(currency0)).approve(address(swapRouter), type(uint256).max);
            IERC20(Currency.unwrap(currency1)).approve(address(swapRouter), type(uint256).max);
            
            // Always swap from currency0 to currency1 for consistency
            bool zeroForOne = true;
            int256 amountSpecified = -1 ether; // negative means exact input
            BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);

            console.log("Swap delta amount0:", int256(swapDelta.amount0()));
            console.log("Swap delta amount1:", int256(swapDelta.amount1()));
        vm.stopPrank();
        
        // Log final balances
        console.log("Final currency0 balance:", IERC20(Currency.unwrap(currency0)).balanceOf(alice));
        console.log("Final currency1 balance:", IERC20(Currency.unwrap(currency1)).balanceOf(alice));

        // Verify the swap occurred
        assertEq(int256(swapDelta.amount0()), amountSpecified);
        assertLt(IERC20(Currency.unwrap(currency1)).balanceOf(alice), WHALE_AMOUNT_BOLD); // Should have spent some currency1
    }
}
