// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "@bold/src/Interfaces/IBorrowerOperations.sol";
import "@bold/src/Interfaces/IBoldToken.sol";
import "@bold/src/Interfaces/IPriceFeed.sol";
import "@bold/src/Interfaces/IHintHelpers.sol";
import "@bold/src/Zappers/Interfaces/IZapper.sol";

contract LiquityV2Test is Test {
    string constant MAINNET_RPC_URL = "MAINNET_RPC_URL";
    uint256 constant FORK_BLOCK_NUMBER = 21966380;

    // Protocol Constants
    uint256 constant AMOUNT_COLLATERAL = 10 ether;    // 10 wstETH (worth ~29,570 ETH)
    uint256 constant AMOUNT_BOLD = 2500 ether;        // 2000 BOLD (minimum amount)
    uint256 constant INTEREST_RATE = 5e16;    // 5%
    
    // Bold Protocol Addresses
    address constant BOLD_TOKEN = 0xb01dd87B29d187F3E3a4Bf6cdAebfb97F3D9aB98;
    address constant BORROWER_OPERATIONS = 0x94C1610a7373919BD9Cfb09Ded19894601f4a1be;
    address constant TROVE_MANAGER = 0xb47eF60132dEaBc89580Fd40e49C062D93070046;
    address constant PRICE_FEED = 0x4c275608887ad2eB049d9006E6852BC3ee8A00Fa;
    address constant HINT_HELPERS = 0xe3BB97EE79aC4BdFc0c30A95aD82c243c9913aDa;
    
    // Token Addresses
    address constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    uint256 constant COLLATERAL_INDEX = 1;
    address constant BOLD = 0xb01dd87B29d187F3E3a4Bf6cdAebfb97F3D9aB98;
    IERC20 collToken;
    IERC20 boldToken;
    IPriceFeed priceFeed;
    IBorrowerOperations borrowerOperations;
    IHintHelpers hintHelpers;

    // Test addresses
    address user = makeAddr("user");
    
    function setUp() public {
        
        // Fork mainnet
        vm.createSelectFork(vm.envString(MAINNET_RPC_URL), FORK_BLOCK_NUMBER);
        
        // Initialize contract instances
        collToken = IERC20(WSTETH);
        boldToken = IERC20(BOLD_TOKEN);
        priceFeed = IPriceFeed(PRICE_FEED);
        borrowerOperations = IBorrowerOperations(BORROWER_OPERATIONS);
        hintHelpers = IHintHelpers(HINT_HELPERS);

        // Setup user with initial balance
        vm.deal(user, AMOUNT_COLLATERAL);
        
        // Label addresses for better trace output
        vm.label(BOLD_TOKEN, "BOLD");
        vm.label(BORROWER_OPERATIONS, "BorrowerOperations");
        vm.label(TROVE_MANAGER, "TroveManager");
        vm.label(WSTETH, "wstETH");
    }

    function test_OpenTroveWithWstETH() public {
        console2.log("wstETH balance of user before: %s", collToken.balanceOf(user));
        
        // Get wstETH directly (simulating having it)
        deal(address(collToken), user, AMOUNT_COLLATERAL);
        
        console2.log("wstETH balance of user after deal: %s", collToken.balanceOf(user));
        console2.log("BOLD balance before: %s", boldToken.balanceOf(user));
        
        // Get current wstETH price
        (uint256 price,) = priceFeed.fetchPrice();
        console2.log("Current wstETH price: %s", price);
        /*
        // Get hints for trove insertion
        (uint256 hintId,,) = hintHelpers.getApproxHint(
            COLLATERAL_INDEX,
            INTEREST_RATE,
            50,  // number of trials
            42   // random seed
        );
        console2.log("Hint ID: %s", hintId);*/
        
        vm.startPrank(user);
            
            // Approve token spending
            collToken.approve(address(borrowerOperations), type(uint256).max);
            //boldToken.approve(address(borrowerOperations), type(uint256).max);
            
            // Open Trove with wstETH as collateral 
            try borrowerOperations.openTrove(
                user,
                COLLATERAL_INDEX,
                AMOUNT_COLLATERAL,
                AMOUNT_BOLD,
                0, // upper hint
                0, // lower hint
                INTEREST_RATE,
                type(uint256).max,
                address(0),
                address(0),
                user                
            ) {
                console2.log("Success!");
            } catch (bytes memory err) {
                console2.log("Error selector:", uint32(bytes4(err)));
                console2.logBytes(err);
                revert("Trove opening failed");
            }
            
        vm.stopPrank();
        
        // Print final balances
        console2.log("BOLD balance after: %s", boldToken.balanceOf(user));
        console2.log("wstETH balance of user final: %s", collToken.balanceOf(user));
        console2.log("BOLD balance of user final: %s", boldToken.balanceOf(user));
        
        // Verify the transaction worked
        assertGt(boldToken.balanceOf(user), 0, "Should have received BOLD tokens");
        assertLt(collToken.balanceOf(user), AMOUNT_COLLATERAL, "Should have deposited wstETH");
    }

    function test_ErrorSelectors() public pure {
        
        // BorrowerOperations errors
        console2.log("--- BorrowerOperations errors ---");
        console2.log("IsShutDown:", uint32(bytes4(keccak256("IsShutDown()"))));
        console2.log("TCRNotBelowSCR:", uint32(bytes4(keccak256("TCRNotBelowSCR()"))));
        console2.log("ZeroAdjustment:", uint32(bytes4(keccak256("ZeroAdjustment()"))));
        console2.log("NotOwnerNorInterestManager:", uint32(bytes4(keccak256("NotOwnerNorInterestManager()"))));
        console2.log("TroveInBatch:", uint32(bytes4(keccak256("TroveInBatch()"))));
        console2.log("TroveNotInBatch:", uint32(bytes4(keccak256("TroveNotInBatch()"))));
        console2.log("InterestNotInRange:", uint32(bytes4(keccak256("InterestNotInRange()"))));
        console2.log("BatchInterestRateChangePeriodNotPassed:", uint32(bytes4(keccak256("BatchInterestRateChangePeriodNotPassed()"))));
        console2.log("DelegateInterestRateChangePeriodNotPassed:", uint32(bytes4(keccak256("DelegateInterestRateChangePeriodNotPassed()"))));
        console2.log("TroveExists:", uint32(bytes4(keccak256("TroveExists()"))));
        console2.log("TroveNotOpen:", uint32(bytes4(keccak256("TroveNotOpen()"))));
        console2.log("TroveNotActive:", uint32(bytes4(keccak256("TroveNotActive()"))));
        console2.log("TroveNotZombie:", uint32(bytes4(keccak256("TroveNotZombie()"))));
        console2.log("TroveWithZeroDebt:", uint32(bytes4(keccak256("TroveWithZeroDebt()"))));
        console2.log("UpfrontFeeTooHigh:", uint32(bytes4(keccak256("UpfrontFeeTooHigh()"))));
        console2.log("ICRBelowMCR:", uint32(bytes4(keccak256("ICRBelowMCR()"))));
        console2.log("RepaymentNotMatchingCollWithdrawal:", uint32(bytes4(keccak256("RepaymentNotMatchingCollWithdrawal()"))));
        console2.log("TCRBelowCCR:", uint32(bytes4(keccak256("TCRBelowCCR()"))));
        console2.log("DebtBelowMin:", uint32(bytes4(keccak256("DebtBelowMin()"))));
        console2.log("CollWithdrawalTooHigh:", uint32(bytes4(keccak256("CollWithdrawalTooHigh()"))));
        console2.log("NotEnoughBoldBalance:", uint32(bytes4(keccak256("NotEnoughBoldBalance()"))));
        console2.log("InterestRateTooLow:", uint32(bytes4(keccak256("InterestRateTooLow()"))));
        console2.log("InterestRateTooHigh:", uint32(bytes4(keccak256("InterestRateTooHigh()"))));
        console2.log("InterestRateNotNew:", uint32(bytes4(keccak256("InterestRateNotNew()"))));
        console2.log("InvalidInterestBatchManager:", uint32(bytes4(keccak256("InvalidInterestBatchManager()"))));
        console2.log("BatchManagerExists:", uint32(bytes4(keccak256("BatchManagerExists()"))));
        console2.log("BatchManagerNotNew:", uint32(bytes4(keccak256("BatchManagerNotNew()"))));
        console2.log("NewFeeNotLower:", uint32(bytes4(keccak256("NewFeeNotLower()"))));
        console2.log("CallerNotTroveManager:", uint32(bytes4(keccak256("CallerNotTroveManager()"))));
        console2.log("CallerNotPriceFeed:", uint32(bytes4(keccak256("CallerNotPriceFeed()"))));
        console2.log("MinGeMax:", uint32(bytes4(keccak256("MinGeMax()"))));
        console2.log("AnnualManagementFeeTooHigh:", uint32(bytes4(keccak256("AnnualManagementFeeTooHigh()"))));
        console2.log("MinInterestRateChangePeriodTooLow:", uint32(bytes4(keccak256("MinInterestRateChangePeriodTooLow()"))));
        console2.log("NewOracleFailureDetected:", uint32(bytes4(keccak256("NewOracleFailureDetected()"))));

        // TroveManager errors
        console2.log("--- TroveManager errors ---");
        console2.log("EmptyData:", uint32(bytes4(keccak256("EmptyData()"))));
        console2.log("NothingToLiquidate:", uint32(bytes4(keccak256("NothingToLiquidate()"))));
        console2.log("CallerNotBorrowerOperations:", uint32(bytes4(keccak256("CallerNotBorrowerOperations()"))));
        console2.log("CallerNotCollateralRegistry:", uint32(bytes4(keccak256("CallerNotCollateralRegistry()"))));
        console2.log("OnlyOneTroveLeft:", uint32(bytes4(keccak256("OnlyOneTroveLeft()"))));
        console2.log("NotShutDown:", uint32(bytes4(keccak256("NotShutDown()"))));
        console2.log("ZeroAmount:", uint32(bytes4(keccak256("ZeroAmount()"))));
        console2.log("NotEnoughBoldBalance:", uint32(bytes4(keccak256("NotEnoughBoldBalance()"))));
        console2.log("MinCollNotReached:", uint32(bytes4(keccak256("MinCollNotReached(uint256)"))));
        console2.log("BatchSharesRatioTooHigh:", uint32(bytes4(keccak256("BatchSharesRatioTooHigh()"))));
    }

    function test_LeverageZapper() public {
        IZapper zapper = IZapper(0x978D7188ae01881d254Ad7E94874653B0C268004);
        
        user = 0xE419f5c05fd2377F75cdADF87C3529F0C9B59FCb;
        uint256 ethAmount = 2.48797 ether;

        console2.log("User ETH balance before:", user.balance);
        console2.log("User BOLD balance before:", boldToken.balanceOf(user));
        
        IZapper.OpenTroveParams memory params = IZapper.OpenTroveParams({
            owner: user,
            ownerIndex: COLLATERAL_INDEX,
            collAmount: 0,
            boldAmount: 2000000000000000000000,
            upperHint: 62386074531969185725078246434344265590408229732709863705962067810072690566538,
            lowerHint: 42667947703477158473877149252472726582525344946055697950684134446720460075349,
            annualInterestRate: 100000000000000000,
            batchManager: address(0),
            maxUpfrontFee: type(uint256).max,
            addManager: address(0),
            removeManager: address(0),
            receiver: address(0)
        });
        
        vm.startPrank(user);
            
            try zapper.openTroveWithRawETH{value: ethAmount}(params) {
                console2.log("Success!");
            } catch (bytes memory err) {
                console2.log("Failed to open trove");
                console2.log("Error selector (hex):", vm.toString(bytes4(err)));
                console2.log("Error selector (decimal):", uint32(bytes4(err)));
                console2.logBytes(err);
                console2.log("Error length:", err.length);
            }
                
        vm.stopPrank();
        
        console2.log("User ETH balance after:", user.balance);
        console2.log("User BOLD balance after:", boldToken.balanceOf(user));
        
        // Verify the transaction worked
        //assertGt(boldToken.balanceOf(user), 0, "Should have received BOLD tokens");
    }
}