// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PLEA} from "../src/PLEA.sol";

/// @dev Stateful model checks exact accounting, including failed operations and self-transfers.
contract PLEAHandler is Test {
    PLEA public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(PLEA token_) {
        token = token_;
        actors = [makeAddr("holder A"), makeAddr("holder B"), makeAddr("holder C"), makeAddr("holder D")];
        expectedBalance[actors[0]] = 1_000_000_000e18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed, bool exceedBalance) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = exceedBalance ? balance + 1 : bound(amountSeed, 0, balance);
        vm.prank(from);
        (bool success, bytes memory result) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        assertEq(success, !exceedBalance, "transfer success differs from model");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool unlimited) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 amount = unlimited ? type(uint256).max : bound(amountSeed, 0, 1_000_000_000e18);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed, bool exceedLimit)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        uint256 limit = approved < balance ? approved : balance;
        uint256 amount = exceedLimit ? limit + 1 : bound(amountSeed, 0, limit);
        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, to, amount)));
        assertEq(success, !exceedLimit, "transferFrom success differs from model");
        if (success) {
            assertTrue(abi.decode(result, (bool)));
            if (approved != type(uint256).max) expectedAllowance[owner][spender] -= amount;
            expectedBalance[owner] -= amount;
            expectedBalance[to] += amount;
        }
    }
}

contract PLEAInvariantTest is Test {
    PLEA internal token;
    PLEAHandler internal handler;

    function setUp() public {
        token = new PLEA();
        handler = new PLEAHandler(token);
        token.transfer(handler.actors(0), 1_000_000_000e18);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = PLEAHandler.transfer.selector;
        selectors[1] = PLEAHandler.approve.selector;
        selectors[2] = PLEAHandler.transferFrom.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_ExactAccountingAndFixedSupply() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor), "holder balance differs from model");
            sum += balance;
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(
                    token.allowance(actor, spender),
                    handler.expectedAllowance(actor, spender),
                    "allowance differs from model"
                );
            }
        }
        assertEq(sum, 1_000_000_000e18);
        assertEq(token.totalSupply(), 1_000_000_000e18);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
