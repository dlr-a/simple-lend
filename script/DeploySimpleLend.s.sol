//SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {SimpleLend} from "../src/SimpleLend.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";
import {SToken} from "../src/SToken.sol";

contract DeploySimpleLend is Script {
    SimpleLend simpleLend;

    uint8 public constant DECIMALS = 8;
    uint256 public constant INITIAL_BALANCE = 1000 ether;
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

    function run()
        external
        returns (
            SimpleLend,
            ERC20Mock,
            ERC20Mock,
            ERC20Mock,
            MockV3Aggregator,
            MockV3Aggregator,
            address,
            address
        )
    {
        vm.startBroadcast(owner);
        token1 = new ERC20Mock("TOKEN1", "TKN");

        token2 = new ERC20Mock("TOKEN2", "TKN");
        unallowedToken = new ERC20Mock("unallowedToken", "UNTKN");

        token1PriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        token2PriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        tokenAddresses = [address(token1), address(token2)];
        priceFeedAddresses = [
            address(token1PriceFeed),
            address(token2PriceFeed)
        ];
        simpleLend = new SimpleLend(tokenAddresses, priceFeedAddresses);

        token1.mint(user, INITIAL_BALANCE);
        token1.mint(address(simpleLend), INITIAL_BALANCE);
        token1.mint(liquidator, INITIAL_BALANCE);

        token2.mint(user, INITIAL_BALANCE);
        token2.mint(address(simpleLend), INITIAL_BALANCE);
        token2.mint(liquidator, INITIAL_BALANCE);

        sToken1 = simpleLend.deploySToken(
            address(token1),
            address(token1PriceFeed),
            "TKN",
            "TOKEN1"
        );

        sToken2 = simpleLend.deploySToken(
            address(token2),
            address(token2PriceFeed),
            "TKN",
            "TOKEN2"
        );
        vm.stopBroadcast();

        return (
            simpleLend,
            token1,
            token2,
            unallowedToken,
            token1PriceFeed,
            token2PriceFeed,
            sToken1,
            sToken2
        );
    }
}
