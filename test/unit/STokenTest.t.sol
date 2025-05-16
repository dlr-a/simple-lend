//SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {SimpleLend} from "../../src/SimpleLend.sol";
import {SToken} from "../../src/SToken.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract STokenTest is Test {
    SToken sToken;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() external {
        vm.startBroadcast(owner);
        sToken = new SToken(address(1), "STOKEN", "STKN");
        vm.stopBroadcast();
    }

    function test__onlyOwnerCanBurnAndMint() external {
        vm.startPrank(owner);
        sToken.mint(owner, 1000 ether);

        assertEq(sToken.totalSupply(), 1000 ether);
        sToken.burn(1000 ether);
        assertEq(sToken.totalSupply(), 0);
    }

    function test__CantMintAndBurnZeroOrLessThanZero() external {
        vm.startPrank(owner);
        vm.expectRevert();
        sToken.mint(owner, 0);

        vm.expectRevert();
        sToken.burn(1000 ether);
    }

    function test__CantMintToAddressZero() external {
        vm.startPrank(owner);
        vm.expectRevert();
        sToken.mint(address(0), 100 ether);
    }

    function test__CantBurnMoreThanBalance() external {
        vm.startPrank(owner);
        sToken.mint(owner, 100 ether);

        uint256 userBalance = sToken.balanceOf(owner);

        vm.expectRevert();
        sToken.burn(userBalance + 1 ether);
    }

    function test__usersCantBurnAndMint() external {
        vm.startPrank(user);

        vm.expectRevert();
        sToken.mint(owner, 1000 ether);
        vm.expectRevert();
        sToken.burn(1000 ether);
    }

    function test__onlyOwnerCanBurnFrom() external {
        vm.startPrank(owner);
        sToken.mint(user, 1000 ether);

        assertEq(sToken.balanceOf(user), 1000 ether);

        sToken.burnFrom(user, 1000 ether);
        assertEq(sToken.balanceOf(user), 0);
    }
}
