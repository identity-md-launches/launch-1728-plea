// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PLEA} from "../src/PLEA.sol";

/// @dev Local fixture modeling only the token movements made by the launch factory.
///      It does not implement pool accounting or Merkle proof verification.
contract TokenLaunchHarness {
    PLEA public immutable token;
    address private immutable controller = msg.sender;

    constructor() {
        token = new PLEA{salt: keccak256("PLEA launch test")}();
    }

    function distribute(address distributor, address pool, address rewards) external {
        require(msg.sender == controller, "test controller only");
        uint256 supply = token.totalSupply();
        require(token.transfer(distributor, supply * 1000 / 10_000));
        require(token.transfer(pool, supply * 8700 / 10_000));
        require(token.transfer(rewards, supply * 300 / 10_000));
    }

    function tryCall(bytes calldata data) external returns (bool success) {
        require(msg.sender == controller, "test controller only");
        (success,) = address(token).call(data);
    }
}

contract RejectingReceiver {
    fallback() external {
        revert("ERC20 transfers must not call the receiver");
    }
}

contract PLEALaunchTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000e18;
    TokenLaunchHarness internal factory;
    PLEA internal token;
    address internal distributor;
    address internal pool;
    address internal rewards;
    address internal claimant;
    address internal trader;

    function setUp() public {
        factory = new TokenLaunchHarness();
        token = factory.token();
        distributor = makeAddr("Merkle distributor fixture");
        pool = makeAddr("pool manager fixture");
        rewards = makeAddr("season rewards fixture");
        claimant = makeAddr("claimant");
        trader = makeAddr("trader");
    }

    function test_Create2MintsEntireSupplyToFactory() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(factory)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(pool), 0);
        assertEq(token.balanceOf(rewards), 0);
    }

    function test_ConstructorUsesImmediateDeployerRegardlessOfOrigin() public {
        vm.prank(trader, claimant);
        TokenLaunchHarness anotherFactory = new TokenLaunchHarness();
        PLEA anotherToken = anotherFactory.token();
        assertEq(anotherToken.balanceOf(address(anotherFactory)), SUPPLY);
        assertEq(anotherToken.balanceOf(trader), 0);
        assertEq(anotherToken.balanceOf(claimant), 0);
    }

    function test_DistributionArrivesExactlyAndEmptiesFactory() public {
        factory.distribute(distributor, pool, rewards);
        assertEq(token.balanceOf(distributor), 100_000_000e18);
        assertEq(token.balanceOf(pool), 870_000_000e18);
        assertEq(token.balanceOf(rewards), 30_000_000e18);
        assertEq(token.balanceOf(address(factory)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ClaimAndPoolTransfersArriveWholeInBothDirections() public {
        factory.distribute(distributor, pool, rewards);
        vm.prank(distributor);
        assertTrue(token.transfer(claimant, 100_000_000e18));
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.balanceOf(claimant), 100_000_000e18);

        vm.prank(pool);
        assertTrue(token.transfer(trader, 25e18));
        assertEq(token.balanceOf(trader), 25e18);
        assertEq(token.balanceOf(pool), 870_000_000e18 - 25e18);
        vm.prank(trader);
        assertTrue(token.transfer(pool, 25e18));
        assertEq(token.balanceOf(trader), 0);
        assertEq(token.balanceOf(pool), 870_000_000e18);

        vm.prank(rewards);
        assertTrue(token.transfer(claimant, 30_000_000e18));
        assertEq(token.balanceOf(rewards), 0);
        assertEq(token.balanceOf(claimant), 130_000_000e18);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_FactoryCannotSpendHolderFundsWithoutApproval() public {
        factory.distribute(distributor, pool, rewards);
        assertFalse(factory.tryCall(abi.encodeCall(token.transferFrom, (rewards, address(factory), 1))));
        assertEq(token.balanceOf(rewards), 30_000_000e18);
        assertEq(token.balanceOf(address(factory)), 0);
        vm.prank(rewards);
        token.transfer(claimant, 1);
        assertEq(token.balanceOf(claimant), 1);
    }

    function test_NoMintBurnFreezeOwnershipOrUpgradeEntryPoints() public {
        factory.distribute(distributor, pool, rewards);
        bytes[] memory calls = new bytes[](21);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", trader, SUPPLY);
        calls[1] = abi.encodeWithSignature("mint(uint256)", SUPPLY);
        calls[2] = abi.encodeWithSignature("mint()");
        calls[3] = abi.encodeWithSignature("issue(uint256)", SUPPLY);
        calls[4] = abi.encodeWithSignature("initialize(address)", trader);
        calls[5] = abi.encodeWithSignature("initialize()");
        calls[6] = abi.encodeWithSignature("setMinter(address)", trader);
        calls[7] = abi.encodeWithSignature("burn(uint256)", 1);
        calls[8] = abi.encodeWithSignature("burnFrom(address,uint256)", rewards, 1);
        calls[9] = abi.encodeWithSignature("pause()");
        calls[10] = abi.encodeWithSignature("unpause()");
        calls[11] = abi.encodeWithSignature("blacklist(address)", rewards);
        calls[12] = abi.encodeWithSignature("freeze(address)", rewards);
        calls[13] = abi.encodeWithSignature("setBlacklist(address,bool)", rewards, true);
        calls[14] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        calls[15] = abi.encodeWithSignature("seize(address)", rewards);
        calls[16] = abi.encodeWithSignature("setOwner(address)", trader);
        calls[17] = abi.encodeWithSignature("transferOwnership(address)", trader);
        calls[18] = abi.encodeWithSignature("upgradeTo(address)", trader);
        calls[19] = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", trader, bytes(""));
        calls[20] = abi.encodeWithSignature("owner()");
        for (uint256 i; i < calls.length; ++i) {
            assertFalse(factory.tryCall(calls[i]), "deployer reached an unexpected entry point");
            vm.prank(trader);
            (bool success,) = address(token).call(calls[i]);
            assertFalse(success, "stranger reached an unexpected entry point");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(rewards), 30_000_000e18);
            assertEq(token.balanceOf(trader), 0);
        }
        vm.prank(rewards);
        assertTrue(token.transfer(claimant, 30_000_000e18));
        assertEq(token.balanceOf(claimant), 30_000_000e18);
    }

    function test_TransfersDoNotCallReceiverCode() public {
        RejectingReceiver receiver = new RejectingReceiver();
        factory.distribute(distributor, pool, rewards);
        vm.prank(rewards);
        assertTrue(token.transfer(address(receiver), 1e18));
        assertEq(token.balanceOf(address(receiver)), 1e18);
    }

    function test_RuntimeHasNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden runtime opcode");
        }
    }
}
