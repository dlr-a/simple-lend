//SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {SimpleLend} from "../../../src/SimpleLend.sol";
import {SToken} from "../../../src/SToken.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";

contract ContinueOnRevertHandler is Test {
    uint256 public totalCollateralValue;
    uint256 public totalBorrowedValue;
    mapping(address token => uint256 amount) public totalSupply;

    uint256 public constant INITIAL_BALANCE = 1000 ether;

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
        simpleLend.setTokenCollateralRatio(address(token1), 80);
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

        // amount = bound(amount, 1, token.balanceOf(msg.sender));
        vm.startPrank(msg.sender);
        // token.approve(address(simpleLend), amount);
        simpleLend.supply(address(token), amount);
        vm.stopPrank();
        totalSupply[address(token)] += amount;
    }

    function withdraw(uint256 amount, uint256 tokenSeed) public {
        ERC20Mock token = _getTokenFromSeed(tokenSeed);

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
    ) public {
        ERC20Mock tokenCollateral = _getTokenFromSeed(tokenSeedCollateral);
        ERC20Mock tokenBorrow = _getTokenFromSeed(tokenSeedBorrow);

        totalCollateralValue += collateralAmount;
        totalBorrowedValue -= borrowAmount;

        simpleLend.borrow(
            address(tokenBorrow),
            borrowAmount,
            address(tokenCollateral),
            collateralAmount
        );
    }

    function repay(
        uint256 tokenSeedCollateral,
        uint256 tokenSeedBorrow
    ) public {
        ERC20Mock tokenCollateral = _getTokenFromSeed(tokenSeedCollateral);
        ERC20Mock tokenBorrow = _getTokenFromSeed(tokenSeedBorrow);

        simpleLend.repay(address(tokenCollateral), address(tokenBorrow));
    }

    function withdrawCollateral(
        uint256 collateralAmount,
        uint256 tokenSeedCollateral,
        uint256 tokenSeedBorrow
    ) public {
        ERC20Mock tokenCollateral = _getTokenFromSeed(tokenSeedCollateral);
        ERC20Mock tokenBorrow = _getTokenFromSeed(tokenSeedBorrow);

        simpleLend.withdrawCollateral(
            address(tokenCollateral),
            address(tokenBorrow),
            collateralAmount
        );
    }

    function addCollateralForBorrow(
        uint256 collateralAmount,
        uint256 tokenSeedCollateral,
        uint256 tokenSeedBorrow
    ) public {
        ERC20Mock tokenCollateral = _getTokenFromSeed(tokenSeedCollateral);
        ERC20Mock tokenBorrow = _getTokenFromSeed(tokenSeedBorrow);

        simpleLend.addCollateralForBorrow(
            address(tokenCollateral),
            address(tokenBorrow),
            collateralAmount
        );
    }

    function switchSupplyToCollateral(
        uint256 collateralAmount,
        uint256 tokenSeedCollateral,
        uint256 tokenSeedBorrow
    ) public {
        ERC20Mock tokenCollateral = _getTokenFromSeed(tokenSeedCollateral);
        ERC20Mock tokenBorrow = _getTokenFromSeed(tokenSeedBorrow);

        simpleLend.switchSupplyToCollateral(
            address(tokenCollateral),
            address(tokenBorrow),
            collateralAmount
        );
    }

    function borrowMore(
        uint256 borrowAmount,
        uint256 tokenSeedCollateral,
        uint256 tokenSeedBorrow
    ) public {
        ERC20Mock tokenCollateral = _getTokenFromSeed(tokenSeedCollateral);
        ERC20Mock tokenBorrow = _getTokenFromSeed(tokenSeedBorrow);

        simpleLend.borrowMore(
            address(tokenBorrow),
            borrowAmount,
            address(tokenCollateral)
        );
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

    function _getTokenFromSeed(
        uint256 tokenSeed
    ) private view returns (ERC20Mock) {
        if (tokenSeed % 2 == 0) {
            return token1;
        } else {
            return token2;
        }
    }
}
