//SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {SimpleLend} from "../../../src/SimpleLend.sol";
import {SToken} from "../../../src/SToken.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";

contract FailOnRevertHandler is Test {
    uint256 public totalCollateralValue;
    uint256 public totalBorrowedValue;
    mapping(address token => uint256 amount) public totalSupply;

    uint256 public constant INITIAL_BALANCE = 1000 ether;
    uint256 public constant HEALTH_FACTOR = 1e18;

    address public owner = makeAddr("owner");

    SimpleLend simpleLend;

    ERC20Mock token1;
    address sToken1;
    ERC20Mock token2;
    address sToken2;
    ERC20Mock unallowedToken;
    MockV3Aggregator token1PriceFeed;
    MockV3Aggregator token2PriceFeed;

    modifier createSTokenAndMintToUser() {
        vm.startPrank(owner);
        sToken1 = simpleLend.deploySToken(
            address(token1),
            address(token1PriceFeed),
            "TKN",
            "TOKEN1"
        );
        vm.stopPrank();
        _;
    }

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

        simpleLend.setAllowedCollateralToken(
            address(token2),
            address(token2PriceFeed),
            true
        );
        simpleLend.setAllowedBorrowToken(
            address(token1),
            address(token1PriceFeed),
            true
        );
        simpleLend.setTokenCollateralRatio(address(token1), 80);
        simpleLend.setTokenCollateralRatio(address(token2), 80);
        vm.stopPrank();
        _;
    }

    constructor(
        SimpleLend _simpleLend,
        ERC20Mock _token1,
        ERC20Mock _token2,
        ERC20Mock _unallowedToken,
        MockV3Aggregator _token1PriceFeed,
        MockV3Aggregator _token2PriceFeed,
        address _sToken1,
        address _sToken2
    ) {
        simpleLend = _simpleLend;
        token1 = _token1;
        token2 = _token2;
        unallowedToken = _unallowedToken;
        token1PriceFeed = _token1PriceFeed;
        token2PriceFeed = _token2PriceFeed;
        sToken1 = _sToken1;
        sToken2 = _sToken2;
    }

    function supply(uint256 amount, uint256 tokenSeed) public {
        ERC20Mock token = _getTokenFromSeed(tokenSeed);

        if (token.balanceOf(msg.sender) < INITIAL_BALANCE) {
            vm.startPrank(owner);
            token.mint(msg.sender, INITIAL_BALANCE);
            vm.stopPrank();
        }
        amount = bound(amount, 1, token.balanceOf(msg.sender));

        vm.startPrank(msg.sender);
        token.approve(address(simpleLend), amount);
        simpleLend.supply(address(token), amount);
        vm.stopPrank();

        totalSupply[address(token)] += amount;
    }

    function withdraw(uint256 amount, uint256 tokenSeed) public {
        ERC20Mock token = _getTokenFromSeed(tokenSeed);
        if (token.balanceOf(address(simpleLend)) < INITIAL_BALANCE) {
            vm.startPrank(owner);
            token.mint(address(simpleLend), INITIAL_BALANCE);
            vm.stopPrank();
        }
        address sToken = simpleLend.s_tokenToSToken(address(token));
        uint256 balance = SToken(sToken).balanceOf(msg.sender);
        if (balance == 0) return;

        amount = bound(amount, 1, balance);

        vm.prank(msg.sender);
        simpleLend.withdraw(address(token), amount);
        totalSupply[address(token)] -= amount;
    }

    function liquidate(
        address user,
        uint256 tokenSeedCollateral,
        uint256 tokenSeedBorrow
    ) public {
        ERC20Mock tokenCollateral = _getTokenFromSeed(tokenSeedCollateral);
        ERC20Mock tokenBorrow = _getTokenFromSeed(tokenSeedBorrow);

        if (simpleLend.s_userBorrows(user, address(tokenBorrow)) == 0) return;

        address userBorrowAddress = simpleLend
            .s_userCollateralTokenToBorrowToken(user, address(tokenCollateral));

        if (address(tokenBorrow) != userBorrowAddress) return;

        uint256 userBorrowAmount = simpleLend.s_userBorrows(
            user,
            address(tokenBorrow)
        );

        uint256 collateralAmount = simpleLend.s_collateralInUse(
            user,
            address(tokenCollateral)
        );

        uint256 borrowAmountInUsd = simpleLend.getPriceFeedInUsd(
            address(tokenBorrow),
            userBorrowAmount
        );

        uint256 collateralInUsd = simpleLend.getPriceFeedInUsd(
            address(tokenCollateral),
            collateralAmount
        );

        uint256 healthFactor = simpleLend.calculateHealthFactor(
            address(tokenCollateral),
            collateralInUsd,
            borrowAmountInUsd
        );

        if (healthFactor > HEALTH_FACTOR) return;

        if (collateralInUsd < borrowAmountInUsd) return;

        simpleLend.liquidate(
            user,
            address(tokenCollateral),
            address(tokenBorrow)
        );
    }

    function borrow(
        uint256 collateralAmount,
        uint256 borrowAmount,
        uint256 tokenSeedCollateral,
        uint256 tokenSeedBorrow
    ) public allowBorrowAndCollateral {
        ERC20Mock tokenCollateral = _getTokenFromSeed(tokenSeedCollateral);
        ERC20Mock tokenBorrow = _getTokenFromSeed(tokenSeedBorrow);

        if (tokenCollateral.balanceOf(msg.sender) < INITIAL_BALANCE) {
            vm.startPrank(owner);
            tokenCollateral.mint(msg.sender, INITIAL_BALANCE);
            vm.stopPrank();
        }

        if (tokenBorrow.balanceOf(address(simpleLend)) < INITIAL_BALANCE) {
            vm.startPrank(owner);
            tokenBorrow.mint(address(simpleLend), INITIAL_BALANCE);
            vm.stopPrank();
        }

        if (
            simpleLend.s_userCollateralTokenToBorrowToken(
                msg.sender,
                address(tokenCollateral)
            ) != address(0)
        ) return;

        if (
            simpleLend.s_collateralInUse(
                msg.sender,
                address(tokenCollateral)
            ) != 0
        ) return;

        collateralAmount = bound(
            collateralAmount,
            1,
            tokenCollateral.balanceOf(msg.sender)
        );

        borrowAmount = bound(
            borrowAmount,
            1,
            tokenBorrow.balanceOf(address(simpleLend))
        );

        uint256 borrowAmountInUsd = simpleLend.getPriceFeedInUsd(
            address(tokenBorrow),
            borrowAmount
        );

        uint256 collateralInUsd = simpleLend.getPriceFeedInUsd(
            address(tokenCollateral),
            collateralAmount
        );

        uint256 healthFactor = simpleLend.calculateHealthFactor(
            address(tokenCollateral),
            collateralInUsd,
            borrowAmountInUsd
        );

        if (healthFactor < HEALTH_FACTOR) return;

        totalCollateralValue += collateralAmount;
        totalBorrowedValue += borrowAmount;

        vm.startPrank(msg.sender);
        tokenCollateral.approve(address(simpleLend), collateralAmount);
        simpleLend.borrow(
            address(tokenBorrow),
            borrowAmount,
            address(tokenCollateral),
            collateralAmount
        );
        vm.stopPrank();
    }

    function repay(
        uint256 tokenSeedCollateral,
        uint256 tokenSeedBorrow
    ) public {
        ERC20Mock tokenCollateral = _getTokenFromSeed(tokenSeedCollateral);
        ERC20Mock tokenBorrow = _getTokenFromSeed(tokenSeedBorrow);

        uint256 userBorrowAmount = simpleLend.s_userBorrows(
            msg.sender,
            address(tokenBorrow)
        );

        uint256 userCollateral = simpleLend.s_collateralInUse(
            msg.sender,
            address(tokenCollateral)
        );

        if (userBorrowAmount == 0 || userCollateral == 0) return;

        address userBorrowAddress = simpleLend
            .s_userCollateralTokenToBorrowToken(
                msg.sender,
                address(tokenCollateral)
            );

        if (
            address(tokenBorrow) != userBorrowAddress ||
            userBorrowAddress == address(0)
        ) return;

        if (tokenCollateral.balanceOf(address(simpleLend)) < INITIAL_BALANCE) {
            vm.startPrank(owner);
            tokenCollateral.mint(address(simpleLend), INITIAL_BALANCE);
            vm.stopPrank();
        }

        if (tokenBorrow.balanceOf(msg.sender) < INITIAL_BALANCE) {
            vm.startPrank(owner);
            tokenBorrow.mint(msg.sender, INITIAL_BALANCE);
            vm.stopPrank();
        }

        vm.startPrank(msg.sender);
        tokenBorrow.approve(address(simpleLend), type(uint256).max);
        simpleLend.repay(address(tokenCollateral), address(tokenBorrow));
        vm.stopPrank();
    }

    function withdrawCollateral(
        uint256 collateralAmount,
        uint256 tokenSeedCollateral,
        uint256 tokenSeedBorrow
    ) public {
        ERC20Mock tokenCollateral = _getTokenFromSeed(tokenSeedCollateral);
        ERC20Mock tokenBorrow = _getTokenFromSeed(tokenSeedBorrow);

        uint256 userBorrowAmount = simpleLend.s_userBorrows(
            msg.sender,
            address(tokenBorrow)
        );

        if (userBorrowAmount == 0) return;

        address userBorrowAddress = simpleLend
            .s_userCollateralTokenToBorrowToken(
                msg.sender,
                address(tokenCollateral)
            );

        if (
            address(tokenBorrow) != userBorrowAddress ||
            userBorrowAddress == address(0)
        ) return;

        uint256 totalUserCollateralAmount = simpleLend.s_collateralInUse(
            msg.sender,
            address(tokenCollateral)
        );

        uint256 borrowAmount = simpleLend.s_userBorrows(
            msg.sender,
            address(tokenBorrow)
        );

        uint256 borrowAmountInUsd = simpleLend.getPriceFeedInUsd(
            address(tokenBorrow),
            borrowAmount
        );

        if (totalUserCollateralAmount < collateralAmount) return;

        uint256 collateralInUsd = simpleLend.getPriceFeedInUsd(
            address(tokenCollateral),
            totalUserCollateralAmount - collateralAmount
        );

        uint256 healthFactor = simpleLend.calculateHealthFactor(
            address(tokenCollateral),
            collateralInUsd,
            borrowAmountInUsd
        );

        if (healthFactor < HEALTH_FACTOR) return;

        vm.startPrank(msg.sender);
        simpleLend.withdrawCollateral(
            address(tokenCollateral),
            address(tokenBorrow),
            collateralAmount
        );
        vm.stopPrank();
    }

    function addCollateralForBorrow(
        uint256 collateralAmount,
        uint256 tokenSeedCollateral,
        uint256 tokenSeedBorrow
    ) public {
        ERC20Mock tokenCollateral = _getTokenFromSeed(tokenSeedCollateral);
        ERC20Mock tokenBorrow = _getTokenFromSeed(tokenSeedBorrow);

        uint256 userBorrowAmount = simpleLend.s_userBorrows(
            msg.sender,
            address(tokenBorrow)
        );

        if (userBorrowAmount == 0) return;

        address userBorrowAddress = simpleLend
            .s_userCollateralTokenToBorrowToken(
                msg.sender,
                address(tokenCollateral)
            );

        if (
            address(tokenBorrow) != userBorrowAddress ||
            userBorrowAddress == address(0)
        ) return;

        if (tokenCollateral.balanceOf(msg.sender) < INITIAL_BALANCE) {
            vm.startPrank(owner);
            tokenCollateral.mint(msg.sender, INITIAL_BALANCE);
            vm.stopPrank();
        }

        collateralAmount = bound(
            collateralAmount,
            1,
            tokenCollateral.balanceOf(msg.sender)
        );

        vm.startPrank(msg.sender);
        tokenCollateral.approve(address(simpleLend), type(uint256).max);
        simpleLend.addCollateralForBorrow(
            address(tokenCollateral),
            address(tokenBorrow),
            collateralAmount
        );
        vm.stopPrank();
    }

    function switchSupplyToCollateral(
        uint256 collateralAmountForSwitch,
        uint256 tokenSeedCollateral,
        uint256 tokenSeedBorrow
    ) public {
        ERC20Mock tokenCollateral = _getTokenFromSeed(tokenSeedCollateral);
        ERC20Mock tokenBorrow = _getTokenFromSeed(tokenSeedBorrow);

        address userBorrowAddress = simpleLend
            .s_userCollateralTokenToBorrowToken(
                msg.sender,
                address(tokenCollateral)
            );

        if (
            address(tokenBorrow) != userBorrowAddress ||
            userBorrowAddress == address(0)
        ) return;

        address sToken = simpleLend.s_tokenToSToken(address(tokenCollateral));

        if (SToken(sToken).balanceOf(msg.sender) < collateralAmountForSwitch)
            return;

        vm.startPrank(msg.sender);
        simpleLend.switchSupplyToCollateral(
            address(tokenCollateral),
            address(tokenBorrow),
            collateralAmountForSwitch
        );
        vm.stopPrank();
    }

    function borrowMore(
        address user,
        uint256 moreBorrowAmount,
        uint256 tokenSeedCollateral,
        uint256 tokenSeedBorrow
    ) public {
        ERC20Mock tokenCollateral = _getTokenFromSeed(tokenSeedCollateral);
        ERC20Mock tokenBorrow = _getTokenFromSeed(tokenSeedBorrow);

        uint256 userBorrowAmount = simpleLend.s_userBorrows(
            user,
            address(tokenBorrow)
        );

        uint256 collateralAmount = simpleLend.s_collateralInUse(
            user,
            address(tokenCollateral)
        );

        if (userBorrowAmount == 0) return;

        address userBorrowAddress = simpleLend
            .s_userCollateralTokenToBorrowToken(user, address(tokenCollateral));

        if (
            address(tokenBorrow) != userBorrowAddress ||
            userBorrowAddress == address(0)
        ) return;

        uint256 borrowAmount = simpleLend.s_userBorrows(
            user,
            address(tokenBorrow)
        );

        moreBorrowAmount = bound(moreBorrowAmount, 1, 1e30);

        uint256 healthFactor = simpleLend.getHealthFactorWithAmounts(
            address(tokenCollateral),
            collateralAmount,
            address(tokenBorrow),
            borrowAmount + moreBorrowAmount
        );

        if (healthFactor < HEALTH_FACTOR) return;

        vm.startPrank(user);
        simpleLend.borrowMore(
            address(tokenBorrow),
            moreBorrowAmount,
            address(tokenCollateral)
        );
        vm.stopPrank();
    }

    function _getTokenFromSeed(
        uint256 tokenSeed
    ) private view returns (ERC20Mock) {
        if (tokenSeed % 2 == 0) {
            return token1;
        } else {
            return token2;
        }
    }

    function getTokenPriceFeed(
        ERC20Mock token
    ) public view returns (MockV3Aggregator) {
        if (token == token1) {
            return token1PriceFeed;
        } else {
            return token1PriceFeed;
        }
    }
}
