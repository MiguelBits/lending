// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISlotMachine {
    function donate(uint256 amount) external;
}

contract PartyHook is BaseHook {
    using PoolIdLibrary for PoolKey;

    error AddLiquidityThroughHook();
    error RemoveLiquidityThroughHook();
    struct CallbackData {
        uint256 amountEth;
        address sender;
    }

    address public ethToken; // this token is not currency0 or currency1
    ISlotMachine public slotMachine;

    constructor(IPoolManager _poolManager, address _ethToken, ISlotMachine _slotMachine) BaseHook(_poolManager) {
        ethToken = _ethToken;
        slotMachine = _slotMachine;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // Custom add liquidity function, only deposit eth
    function addLeverageToken(uint256 amount) external {
        IERC20(ethToken).transferFrom(tx.origin, address(this), amount);
        //TODO:open trove
    }

    function withdrawLeverageToken(uint256 amount) external {
        IERC20(ethToken).transfer(tx.origin, amount);
        //TODO: close trove
    }
    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function _beforeSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata swap, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        //TODO:

        //if poolparty token for bold, play slot machine
        //if bold token for poolparty, donate to slot machine
        if (swap.zeroForOne) {
            //TODO: 
        } else {
            //TODO:
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        //TODO:
        return (BaseHook.afterSwap.selector, 0);
    }
}
