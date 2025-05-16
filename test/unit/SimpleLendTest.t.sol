//SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {SimpleLend} from "../../src/SimpleLend.sol";
import {SToken} from "../../src/SToken.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {DeploySimpleLend} from "../../script/DeploySimpleLend.s.sol";

contract SimpleLendTest is Test {
    SimpleLend simpleLend;

    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant DEPOSIT_AMOUNT = 100 ether;
    uint256 public constant BORROW_AMOUNT = 10 ether;
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public liquidator = makeAddr("liquidator");

    ERC20Mock token1;
    address sToken1;
    ERC20Mock token2;
    address sToken2;
    ERC20Mock unallowedToken;
    MockV3Aggregator token1PriceFeed;
    MockV3Aggregator token2PriceFeed;

    function setUp() external {
        DeploySimpleLend deployer = new DeploySimpleLend();

        (
            simpleLend,
            token1,
            token2,
            unallowedToken,
            token1PriceFeed,
            token2PriceFeed,
            sToken1,
            sToken2
        ) = deployer.run();
    }

    // modifier createSTokenAndMintToUser() {
    //     vm.startPrank(owner);
    //     // sToken1 = simpleLend.deploySToken(
    //     //     address(token1),
    //     //     address(token1PriceFeed),
    //     //     "TKN",
    //     //     "TOKEN1"
    //     // );
    //     vm.stopPrank();
    //     _;
    // }

    modifier allowBorrowAndCollateral() {
        vm.startPrank(owner);
        simpleLend.setAllowedCollateralToken(
            address(token1),
            address(token1PriceFeed),
            true
        );
        simpleLend.setAllowedBorrowToken(
            address(token2),
            address(token2PriceFeed),
            true
        );
        simpleLend.setTokenCollateralRatio(address(token1), 80);
        vm.stopPrank();
        _;
    }

    function test__supplyWorksCorrectly() external {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        simpleLend.supply(address(token1), DEPOSIT_AMOUNT);
        uint256 userStokenBalance = SToken(sToken1).balanceOf(user);
        assertEq(userStokenBalance, DEPOSIT_AMOUNT);
    }

    function test__switchSupplyWorksCorrectly()
        external
        allowBorrowAndCollateral
    {
        vm.startPrank(user);
        token1.approve(address(simpleLend), 200 ether);
        simpleLend.supply(address(token1), DEPOSIT_AMOUNT);
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            DEPOSIT_AMOUNT
        );
        simpleLend.switchSupplyToCollateral(
            address(token1),
            address(token2),
            BORROW_AMOUNT
        );

        uint256 userStokenBalance = SToken(sToken1).balanceOf(user);
        assertEq(userStokenBalance, DEPOSIT_AMOUNT - BORROW_AMOUNT);
        assertEq(
            simpleLend.s_collateralInUse(user, address(token1)),
            DEPOSIT_AMOUNT + BORROW_AMOUNT
        );
    }

    function test__withdrawWorksCorrectly() external {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        simpleLend.supply(address(token1), DEPOSIT_AMOUNT);
        simpleLend.withdraw(address(token1), DEPOSIT_AMOUNT);
        uint256 userStokenBalance = SToken(sToken1).balanceOf(user);
        assertEq(userStokenBalance, 0);
    }

    function test__withdrawWithInterest() external {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        simpleLend.supply(address(token1), DEPOSIT_AMOUNT);
        uint256 twoDays = 2 * 1 days;
        vm.warp(block.timestamp + twoDays);

        uint256 userInterest = simpleLend.getInterestRateForSupply(
            user,
            address(token1)
        );

        simpleLend.withdraw(address(token1), type(uint256).max);
        uint256 userStokenBalance = SToken(sToken1).balanceOf(user);
        uint256 userTokenBalance = token1.balanceOf(user);
        assertEq(userStokenBalance, 0);
        assertEq(userTokenBalance, 1000 ether + userInterest);
    }

    function test__borrowWorksCorrectly() external allowBorrowAndCollateral {
        vm.startPrank(user);
        token1.approve(address(simpleLend), 200 ether);
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            DEPOSIT_AMOUNT
        );

        uint256 balanceOfContract = token1.balanceOf(address(simpleLend));
        uint256 balanceOfUser = token1.balanceOf(user);

        uint256 balanceOfContract2 = token2.balanceOf(address(simpleLend));
        uint256 balanceOfUser2 = token2.balanceOf(user);

        assertEq(balanceOfContract, INITIAL_BALANCE + DEPOSIT_AMOUNT);
        assertEq(balanceOfUser, INITIAL_BALANCE - DEPOSIT_AMOUNT);

        assertEq(balanceOfContract2, INITIAL_BALANCE - BORROW_AMOUNT);
        assertEq(balanceOfUser2, INITIAL_BALANCE + BORROW_AMOUNT);
    }

    function test__repayWorksCorrectly() external allowBorrowAndCollateral {
        vm.startPrank(user);
        token1.approve(address(simpleLend), 200 ether);
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            DEPOSIT_AMOUNT
        );

        uint256 borrowAmount = simpleLend.getInterestRateForBorrow(
            user,
            address(token2)
        );
        token2.approve(address(simpleLend), BORROW_AMOUNT + borrowAmount);
        simpleLend.repay(address(token1), address(token2));

        uint256 balanceOfContract = token1.balanceOf(address(simpleLend));
        uint256 balanceOfUser = token1.balanceOf(user);

        uint256 balanceOfContract2 = token2.balanceOf(address(simpleLend));
        uint256 balanceOfUser2 = token2.balanceOf(user);

        assertEq(balanceOfContract, INITIAL_BALANCE);
        assertEq(balanceOfUser, INITIAL_BALANCE);

        assertEq(balanceOfContract2, INITIAL_BALANCE + borrowAmount);
        assertEq(balanceOfUser2, INITIAL_BALANCE - borrowAmount);
    }

    function test__liquidationWorksCorrectly()
        external
        allowBorrowAndCollateral
    {
        vm.startPrank(user);
        token1.approve(address(simpleLend), 200 ether);
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            23 ether
        );

        token1PriceFeed.updateAnswer(1000e8);

        vm.stopPrank();
        vm.startPrank(liquidator);
        token2.approve(address(simpleLend), BORROW_AMOUNT);
        simpleLend.liquidate(user, address(token1), address(token2));

        assertEq(token1.balanceOf(liquidator), INITIAL_BALANCE + 22 ether);
        assertEq(token2.balanceOf(liquidator), INITIAL_BALANCE - BORROW_AMOUNT);
    }

    function test__addCollateralWorksCorrectly()
        external
        allowBorrowAndCollateral
    {
        vm.startPrank(user);
        token1.approve(address(simpleLend), 200 ether);
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            DEPOSIT_AMOUNT
        );

        simpleLend.addCollateralForBorrow(
            address(token1),
            address(token2),
            BORROW_AMOUNT
        );

        assertEq(
            simpleLend.s_collateralInUse(user, address(token1)),
            DEPOSIT_AMOUNT + BORROW_AMOUNT
        );
    }

    function test__withdrawCollateralWorksCorrectly()
        external
        allowBorrowAndCollateral
    {
        vm.startPrank(user);
        token1.approve(address(simpleLend), 200 ether);
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            DEPOSIT_AMOUNT
        );

        simpleLend.withdrawCollateral(
            address(token1),
            address(token2),
            BORROW_AMOUNT
        );

        assertEq(simpleLend.s_collateralInUse(user, address(token1)), 90 ether);
    }

    function test__borrowMoreWorks() external allowBorrowAndCollateral {
        vm.startPrank(user);
        token1.approve(address(simpleLend), 200 ether);
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            DEPOSIT_AMOUNT
        );

        simpleLend.borrowMore(address(token2), BORROW_AMOUNT, address(token1));

        assertEq(
            simpleLend.s_userBorrows(user, address(token2)),
            BORROW_AMOUNT + BORROW_AMOUNT
        );
    }

    //TEST FAILS
    function test__supplyFailOnUnallowedToken() external {
        vm.startPrank(user);
        unallowedToken.approve(address(simpleLend), DEPOSIT_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleLend.SimpleLend__TokenIsNotSupportedForSupply.selector,
                address(unallowedToken)
            )
        );
        simpleLend.supply(address(unallowedToken), DEPOSIT_AMOUNT);
    }

    function test__supplyFailOnZeroAddress() external {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);

        vm.expectRevert();
        simpleLend.supply(address(0), DEPOSIT_AMOUNT);
    }

    function test__supplyFailWithoutApprove() external {
        vm.startPrank(user);

        vm.expectRevert();
        simpleLend.supply(address(token1), DEPOSIT_AMOUNT);
    }

    function test__withdrawWithNoInterest() external {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        simpleLend.supply(address(token1), DEPOSIT_AMOUNT);
        simpleLend.withdraw(address(token1), type(uint256).max);

        assertEq(token1.balanceOf(user), INITIAL_BALANCE);
    }

    function test__CantWithdrawMoreThanSupply() external {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        simpleLend.supply(address(token1), DEPOSIT_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleLend.SimpleLend__InsufficientBalanceForWithdraw.selector,
                user,
                address(token1),
                SToken(sToken1).balanceOf(user)
            )
        );
        simpleLend.withdraw(address(token1), 10_000 ether);
    }

    function test__CantWithdrawIfContractDoesntHaveBalance() external {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        simpleLend.supply(address(token1), DEPOSIT_AMOUNT);
        vm.stopPrank();

        vm.startPrank(address(simpleLend));
        token1.transfer(liquidator, token1.balanceOf(address(simpleLend)));
        vm.stopPrank();

        vm.startPrank(user);
        vm.expectRevert();
        simpleLend.withdraw(address(token1), type(uint256).max);
    }

    function test__CantWithdrawIfTokenNotSupported() external {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        simpleLend.supply(address(token1), DEPOSIT_AMOUNT);

        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleLend.SimpleLend__TokenIsNotSupportedForSupply.selector,
                address(unallowedToken)
            )
        );
        simpleLend.withdraw(address(unallowedToken), 10_000 ether);
    }

    function test__borrowWillFailForSameCollateral()
        external
        allowBorrowAndCollateral
    {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            DEPOSIT_AMOUNT
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleLend.SimpleLend__CantUseSameCollateral.selector,
                user,
                address(token1)
            )
        );
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            DEPOSIT_AMOUNT
        );
    }

    function test__borrowWillFailOnNotMeetThreshold()
        external
        allowBorrowAndCollateral
    {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        uint256 health = simpleLend.getHealthFactorWithAmounts(
            address(token1),
            BORROW_AMOUNT,
            address(token2),
            BORROW_AMOUNT
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleLend.SimpleLend__InsufficientCollateral.selector,
                user,
                health
            )
        );
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            BORROW_AMOUNT
        );
    }

    function test__cantAddCollateralToAnotherPair()
        external
        allowBorrowAndCollateral
    {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            DEPOSIT_AMOUNT
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleLend
                    .SimpleLend__CollateralAndBorrowTokenMismatch
                    .selector,
                address(token1),
                address(token1)
            )
        );
        simpleLend.addCollateralForBorrow(address(token1), address(token1), 3);
    }

    function test__cantSwitchSupplyToCollateralToAnotherPair()
        external
        allowBorrowAndCollateral
    {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            DEPOSIT_AMOUNT
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleLend
                    .SimpleLend__CollateralAndBorrowTokenMismatch
                    .selector,
                address(token1),
                address(token1)
            )
        );
        simpleLend.switchSupplyToCollateral(
            address(token1),
            address(token1),
            3
        );
    }

    function test__cantRepayWrongPair() external allowBorrowAndCollateral {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            DEPOSIT_AMOUNT
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleLend
                    .SimpleLend__CollateralAndBorrowTokenMismatch
                    .selector,
                address(token1),
                address(token1)
            )
        );
        simpleLend.repay(address(token1), address(token1));
    }

    function test__cantLiquidateWithWrongPair()
        external
        allowBorrowAndCollateral
    {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            DEPOSIT_AMOUNT
        );

        vm.stopPrank();

        vm.startPrank(liquidator);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleLend
                    .SimpleLend__CollateralAndBorrowTokenMismatch
                    .selector,
                address(token1),
                address(token1)
            )
        );
        simpleLend.liquidate(user, address(token1), address(token1));
    }

    function test__cantLiquidateIfUserMeetsThreshold()
        external
        allowBorrowAndCollateral
    {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            DEPOSIT_AMOUNT
        );

        vm.stopPrank();

        uint256 health = simpleLend.getHealthFactorWithAmounts(
            address(token1),
            DEPOSIT_AMOUNT,
            address(token2),
            BORROW_AMOUNT
        );

        vm.startPrank(liquidator);
        vm.expectRevert(
            abi.encodeWithSelector(
                SimpleLend
                    .SimpleLend__LiquidationFailedUsersPositionCantLiquidate
                    .selector,
                user,
                liquidator,
                health
            )
        );
        simpleLend.liquidate(user, address(token1), address(token2));
    }

    function test__cantBorrowWithoutApproveCollateral() external {
        vm.startPrank(user);

        vm.expectRevert();
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            DEPOSIT_AMOUNT
        );
    }

    function test__cantLiquidateWithoutApproveBorrowToken()
        external
        allowBorrowAndCollateral
    {
        vm.startPrank(user);
        token1.approve(address(simpleLend), DEPOSIT_AMOUNT);
        simpleLend.borrow(
            address(token2),
            BORROW_AMOUNT,
            address(token1),
            23 ether
        );

        vm.stopPrank();

        token1PriceFeed.updateAnswer(1000e8);

        vm.startPrank(liquidator);
        vm.expectRevert();
        simpleLend.liquidate(user, address(token1), address(token2));
    }
}
