// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
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
        // Approval is authorization, not a reservation: it can exceed the entire supply.
        uint256 amount = unlimited ? type(uint256).max : amountSeed;
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

    /// @dev Reach positive delegated transfers even when random approvals and balances rarely overlap.
    function spendApprovedBalance(uint256 ownerSeed, uint256 spenderSeed, bool unlimited) external {
        uint256 ownerIndex = _fundedActorIndex(ownerSeed);
        address owner = actors[ownerIndex];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[(ownerIndex + 1) % actors.length];
        uint256 amount = expectedBalance[owner];
        uint256 approved = unlimited ? type(uint256).max : amount;

        vm.prank(owner);
        assertTrue(token.approve(spender, approved));
        expectedAllowance[owner][spender] = approved;
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] = 0;
        expectedBalance[to] += amount;
        expectedAllowance[owner][spender] = unlimited ? type(uint256).max : 0;
    }

    function revokeAndRejectSpend(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[_fundedActorIndex(ownerSeed)];
        address spender = actors[spenderSeed % actors.length];
        vm.startPrank(owner);
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, 0));
        vm.stopPrank();
        expectedAllowance[owner][spender] = 0;

        vm.prank(spender);
        (bool success, bytes memory result) =
            address(token).call(abi.encodeCall(token.transferFrom, (owner, spender, 1)));
        assertFalse(success, "revoked spender moved tokens");
        assertEq(result, abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
    }

    /// @dev Rejected calls must preserve every balance and allowance in the independent model.
    function rejectZeroAddress(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, uint8 action) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        bytes memory data;
        bytes memory expectedError;
        address caller = owner;
        if (action % 3 == 0) {
            data = abi.encodeCall(token.transfer, (address(0), amountSeed));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        } else if (action % 3 == 1) {
            data = abi.encodeCall(token.approve, (address(0), amountSeed));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0));
        } else {
            uint256 approved = expectedAllowance[owner][spender];
            uint256 balance = expectedBalance[owner];
            uint256 amount = bound(amountSeed, 0, approved < balance ? approved : balance);
            data = abi.encodeCall(token.transferFrom, (owner, address(0), amount));
            expectedError = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
            caller = spender;
        }
        vm.prank(caller);
        (bool success, bytes memory result) = address(token).call(data);
        assertFalse(success, "zero address accepted");
        assertEq(result, expectedError, "unexpected failure reason");
    }

    /// @dev A positive round trip must restore both balances without changing any approval.
    function roundTrip(uint256 ownerSeed, uint256 amountSeed) external {
        uint256 ownerIndex = _fundedActorIndex(ownerSeed);
        address owner = actors[ownerIndex];
        address other = actors[(ownerIndex + 1) % actors.length];
        uint256 amount = bound(amountSeed, 1, expectedBalance[owner]);

        vm.prank(owner);
        assertTrue(token.transfer(other, amount));
        assertEq(token.balanceOf(owner), expectedBalance[owner] - amount);
        assertEq(token.balanceOf(other), expectedBalance[other] + amount);
        vm.prank(other);
        assertTrue(token.transfer(owner, amount));
        // No model changes: the invariant must find the exact starting balances and allowances.
    }

    function _fundedActorIndex(uint256 seed) internal view returns (uint256) {
        uint256 start = seed % actors.length;
        for (uint256 i; i < actors.length; ++i) {
            uint256 index = (start + i) % actors.length;
            if (expectedBalance[actors[index]] > 0) return index;
        }
        revert("model lost the fixed supply");
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
contract PLEAInvariantTest is Test {
    PLEA internal token;
    PLEAHandler internal handler;

    function setUp() public {
        token = new PLEA();
        handler = new PLEAHandler(token);
        token.transfer(handler.actors(0), 1_000_000_000e18);
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = PLEAHandler.transfer.selector;
        selectors[1] = PLEAHandler.approve.selector;
        selectors[2] = PLEAHandler.transferFrom.selector;
        selectors[3] = PLEAHandler.spendApprovedBalance.selector;
        selectors[4] = PLEAHandler.revokeAndRejectSpend.selector;
        selectors[5] = PLEAHandler.rejectZeroAddress.selector;
        selectors[6] = PLEAHandler.roundTrip.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    function invariant_ExactAccountingAndFixedSupply() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor), "holder balance differs from model");
            assertEq(token.allowance(actor, address(0)), 0, "zero spender acquired an allowance");
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

    /// @dev Each random sequence ends with every holder able to transfer its whole remaining balance.
    function afterInvariant() public {
        address recipient = makeAddr("post-sequence recipient");
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = handler.expectedBalance(actor);
            vm.prank(actor);
            assertTrue(token.transfer(recipient, balance));
            assertEq(token.balanceOf(actor), 0, "holder could not empty its account");
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.expectedAllowance(actor, spender));
            }
        }
        assertEq(token.balanceOf(recipient), 1_000_000_000e18);
        assertEq(token.totalSupply(), 1_000_000_000e18);
    }
}
