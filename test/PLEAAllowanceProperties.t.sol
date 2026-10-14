// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {PLEA} from "src/PLEA.sol";

/// @dev Complements the existing token tests with authorization boundaries and multi-step properties.
/// forge-config: default.fuzz.runs = 1000
contract PLEAAllowancePropertiesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000e18;
    PLEA internal token;
    address internal alice;
    address internal bob;
    address internal spender;
    address internal otherSpender;

    function setUp() public {
        token = new PLEA();
        alice = makeAddr("allowance owner A");
        bob = makeAddr("allowance owner B");
        spender = makeAddr("allowance spender A");
        otherSpender = makeAddr("allowance spender B");
    }

    function test_LargestFiniteApprovalReplacesInfiniteAndDecreases() public {
        assertTrue(token.approve(spender, type(uint256).max));
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalCanBeRevokedAfterUse() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertTrue(token.approve(spender, 0));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
    }

    function test_HolderCanGrantAndSpendSelfApproval() public {
        assertTrue(token.approve(address(this), 2));
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), address(this)), 1);
        assertEq(token.balanceOf(alice), 1);

        assertTrue(token.transferFrom(address(this), address(this), 1));
        assertEq(token.allowance(address(this), address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApprovalBeforeFundingSurvivesEmptyBalanceAndRefill() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 3));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 3);

        token.transfer(alice, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 2));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(alice, spender), 1);

        token.transfer(alice, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY - 3);
    }

    function test_ApprovalDoesNotAuthorizeTheSpendersSpender() public {
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(spender, 10);
        vm.prank(spender);
        token.approve(otherSpender, 10);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, otherSpender, 0, 1));
        vm.prank(otherSpender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.allowance(spender, otherSpender), 10);
        assertEq(token.allowance(alice, otherSpender), 0);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_SpentApprovalCannotBeReplayedAfterTokensReturn() public {
        token.approve(spender, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_DelegatedSelfTransferCannotExceedBalanceEvenWithInfiniteApproval() public {
        token.transfer(alice, 1);
        uint256[2] memory approvals = [type(uint256).max - 1, type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            vm.prank(alice);
            token.approve(spender, approvals[i]);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
            vm.prank(spender);
            token.transferFrom(alice, alice, 2);
            assertEq(token.allowance(alice, spender), approvals[i]);
            assertEq(token.balanceOf(alice), 1);
            assertEq(token.totalSupply(), SUPPLY);
        }
    }

    function test_MaximumTransferCannotOverflowBalancesOrBurnSupply() public {
        bytes memory expected = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(expected);
        token.transfer(alice, type(uint256).max);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(expected);
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);

        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
    }

    function test_ZeroDelegatedTransferToZeroRevertsForFiniteAndInfiniteApproval() public {
        uint256[3] memory approvals = [uint256(0), uint256(1), type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            token.approve(spender, approvals[i]);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(address(this), address(0), 0);
            assertEq(token.allowance(address(this), spender), approvals[i]);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroApprovalToZeroSpenderStillReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function testFuzz_LargeFiniteAllowanceSpendsExactly(uint256 allowanceSeed, uint256 amountSeed) public {
        uint256 approved = bound(allowanceSeed, SUPPLY + 1, type(uint256).max - 1);
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));

        assertEq(token.allowance(address(this), spender), approved - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_InsufficientBalanceRestoresAnySufficientAllowance(
        uint256 balanceSeed,
        uint256 amountSeed,
        uint256 allowanceSeed
    ) public {
        uint256 balance = bound(balanceSeed, 0, SUPPLY);
        uint256 amount = bound(amountSeed, balance + 1, type(uint256).max);
        uint256 approved = bound(allowanceSeed, amount, type(uint256).max);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY - balance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedDestinationPreservesApprovalForValidRetry(uint256 amountSeed, uint256 allowanceSeed)
        public
    {
        uint256 amount = bound(amountSeed, 1, SUPPLY);
        uint256 approved = bound(allowanceSeed, amount, type(uint256).max);
        token.approve(spender, approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
    }

    function testFuzz_SpendingDoesNotChangeOtherOwnersOrSpendersApprovals(
        uint256 amountSeed,
        uint256 approvalA,
        uint256 approvalB
    ) public {
        uint256 amount = bound(amountSeed, 1, SUPPLY / 2);
        token.transfer(alice, SUPPLY / 2);
        token.transfer(bob, SUPPLY / 2);
        vm.startPrank(alice);
        token.approve(spender, amount);
        token.approve(otherSpender, approvalA);
        vm.stopPrank();
        vm.startPrank(bob);
        token.approve(spender, approvalB);
        token.approve(otherSpender, type(uint256).max);
        vm.stopPrank();

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.allowance(alice, otherSpender), approvalA);
        assertEq(token.allowance(bob, spender), approvalB);
        assertEq(token.allowance(bob, otherSpender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY / 2 - amount);
        assertEq(token.balanceOf(bob), SUPPLY / 2 + amount);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// @dev Splitting the same authorized movement must neither create fees nor change total authorization spent.
    function testFuzz_SplitAndSingleDelegatedTransfersAgree(
        uint256 amountSeed,
        uint256 splitSeed,
        uint256 allowanceSeed
    ) public {
        uint256 amount = bound(amountSeed, 0, SUPPLY);
        uint256 first = bound(splitSeed, 0, amount);
        uint256 approved = bound(allowanceSeed, amount, type(uint256).max);
        PLEA single = new PLEA();
        token.approve(spender, approved);
        single.approve(spender, approved);

        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));
        assertTrue(token.transferFrom(address(this), alice, amount - first));
        assertTrue(single.transferFrom(address(this), alice, amount));
        vm.stopPrank();

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(alice), single.balanceOf(alice));
        assertEq(token.balanceOf(address(this)), single.balanceOf(address(this)));
        assertEq(token.allowance(address(this), spender), single.allowance(address(this), spender));
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(single.totalSupply(), SUPPLY);
    }
}
