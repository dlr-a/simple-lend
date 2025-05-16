//SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Test, console} from "forge-std/Test.sol";
import {SimpleLend} from "../../../src/SimpleLend.sol";
import {SToken} from "../../../src/SToken.sol";
import {ERC20Mock} from "../../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../../mocks/MockV3Aggregator.sol";
import {FailOnRevertHandler} from "./FailOnRevertHandler.t.sol";
import {DeploySimpleLend} from "../../../script/DeploySimpleLend.s.sol";

contract FailOnRevertInvariant is StdInvariant, Test {
    FailOnRevertHandler public handler;

    uint8 public constant DECIMALS = 8;
    uint256 public constant INITIAL_BALANCE = 1000 ether;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public liquidator = makeAddr("liquidator");

    SimpleLend simpleLend;
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
        handler = new FailOnRevertHandler(
            simpleLend,
            token1,
            token2,
            unallowedToken,
            token1PriceFeed,
            token2PriceFeed,
            sToken1,
            sToken2
        );
        targetContract(address(handler));
    }

    function invariant__userSupplyWorksCorrectWithSToken() public view {
        uint256 totalUserSupplies = SToken(sToken1).totalSupply();
        uint256 protocolBalance = handler.totalSupply(address(token1));

        uint256 totalUserSupplies2 = SToken(sToken2).totalSupply();
        uint256 protocolBalance2 = handler.totalSupply(address(token2));

        uint256 totalBorrowAmount = handler.totalBorrowedValue();
        (, int256 borrowPrice, , , ) = token2PriceFeed.latestRoundData();

        uint256 totalBorrowInUsd = totalBorrowAmount * uint256(borrowPrice);

        uint256 totalCollateralAmount = handler.totalCollateralValue();
        (, int256 CollateralPrice, , , ) = token1PriceFeed.latestRoundData();

        uint256 totalCollateralInUsd = totalCollateralAmount *
            uint256(CollateralPrice);

        assertGe(totalCollateralInUsd, totalBorrowInUsd);
        assertGe(protocolBalance, totalUserSupplies);
        assertGe(protocolBalance2, totalUserSupplies2);
    }
}
