// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/TokenVestingVault.sol";

contract MockERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount);
        require(allowance[from][msg.sender] >= amount);
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract TokenVestingVaultTest is Test {
    TokenVestingVault vault;
    MockERC20 token;

    address owner       = makeAddr("owner");
    address beneficiary = makeAddr("beneficiary");
    address stranger    = makeAddr("stranger");

    uint256 constant TOTAL    = 1000;
    uint256 constant DURATION = 365 days;
    uint256 constant CLIFF    = 90 days;

    uint256 start;
    uint256 scheduleId;

    function setUp() public {
        vm.prank(owner);
        vault = new TokenVestingVault();

        token = new MockERC20();
        token.mint(owner, 10000);

        start = block.timestamp;

        vm.startPrank(owner);
        token.approve(address(vault), 10000);
        scheduleId = vault.createSchedule(
            address(token),
            beneficiary,
            TOTAL,
            start,
            CLIFF,
            DURATION,
            true
        );
        vm.stopPrank();
    }

    function test_nothingVestedBeforeCliff() public {
        vm.warp(start + CLIFF - 1);
        assertEq(vault.claimable(scheduleId), 0);
    }

    function test_partialVestingAfterCliff() public {
        vm.warp(start + CLIFF);

        uint256 claimableAmount = vault.claimable(scheduleId);
        assertGt(claimableAmount, 0);
        assertLt(claimableAmount, TOTAL);
    }

    function test_claimPartialVesting() public {
        vm.warp(start + 180 days);

        uint256 claimableAmount = vault.claimable(scheduleId);

        vm.prank(beneficiary);
        vault.claim(scheduleId);

        assertEq(token.balanceOf(beneficiary), claimableAmount);
    }

    function test_fullVestingAfterDuration() public {
        vm.warp(start + DURATION);

        assertEq(vault.claimable(scheduleId), TOTAL);

        vm.prank(beneficiary);
        vault.claim(scheduleId);

        assertEq(token.balanceOf(beneficiary), TOTAL);
    }

    function test_rejectDoubleClaim() public {
        vm.warp(start + DURATION);

        vm.prank(beneficiary);
        vault.claim(scheduleId);

        vm.prank(beneficiary);
        vm.expectRevert(TokenVestingVault.NothingToClaim.selector);
        vault.claim(scheduleId);
    }

    function test_rejectClaimBeforeCliff() public {
        vm.warp(start + CLIFF - 1);

        vm.prank(beneficiary);
        vm.expectRevert(TokenVestingVault.NothingToClaim.selector);
        vault.claim(scheduleId);
    }

    function test_rejectUnauthorizedClaim() public {
        vm.warp(start + DURATION);

        vm.prank(stranger);
        vm.expectRevert(TokenVestingVault.NotBeneficiary.selector);
        vault.claim(scheduleId);
    }

    function test_revokePreservesVestedTokens() public {
        vm.warp(start + 180 days);

        uint256 vestedBefore = vault.claimable(scheduleId);

        vm.prank(owner);
        vault.revoke(scheduleId);

        assertEq(token.balanceOf(beneficiary), vestedBefore);
        assertGt(token.balanceOf(owner), 0);
    }

    function test_rejectClaimAfterRevoke() public {
        vm.warp(start + 180 days);

        vm.prank(owner);
        vault.revoke(scheduleId);

        vm.prank(beneficiary);
        vm.expectRevert(TokenVestingVault.AlreadyRevoked.selector);
        vault.claim(scheduleId);
    }

    function test_rejectNonRevocableRevoke() public {
        vm.startPrank(owner);
        uint256 nonRevocableId = vault.createSchedule(
            address(token),
            beneficiary,
            500,
            start,
            CLIFF,
            DURATION,
            false
        );

        vm.expectRevert(TokenVestingVault.NotRevocable.selector);
        vault.revoke(nonRevocableId);
        vm.stopPrank();
    }

    function test_rejectInvalidSchedule() public {
        vm.prank(owner);
        vm.expectRevert(TokenVestingVault.InvalidSchedule.selector);
        vault.createSchedule(
            address(token),
            beneficiary,
            500,
            start,
            DURATION + 1,
            DURATION,
            true
        );
    }
}
