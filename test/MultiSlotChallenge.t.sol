// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
 
import "forge-std/Test.sol";
import "../src/MultiSlotChallenge.sol";
import "../src/MockUSDC.sol";
 
contract MultiSlotChallengeTest is Test {
    MultiSlotChallenge challenge;
    MockUSDC usdc;
 
    address owner;
    uint256 ownerKey;
 
    address user;
    uint256 userKey;
 
    address user2;
    uint256 user2Key;
 
    uint256 constant FEE = 10_000_000; // $10 USDC (6 decimals)
    uint256 constant REWARD = 50_000_000; // $50 USDC
    uint256 constant DURATION = 1 days;
    uint256 constant MIN_REMAINING = 1_000_000; // $1 USDC
 
    function setUp() public {
        // deterministic test keys
        ownerKey = 0xA11CE;
        userKey = 0xB0B;
        user2Key = 0xCAFE;
 
        owner = vm.addr(ownerKey);
        user = vm.addr(userKey);
        user2 = vm.addr(user2Key);
 
        // deploy mock token as owner
        vm.startPrank(owner);
        usdc = new MockUSDC();
 
        challenge = new MultiSlotChallenge(
            address(usdc),
            owner,   // fee recipient
            FEE,
            REWARD,
            DURATION
        );
        vm.stopPrank();
    }
 
    function _mintAndFundPool(uint256 poolAmount) internal {
        vm.startPrank(owner);
        usdc.mint(owner, poolAmount);
        usdc.approve(address(challenge), poolAmount);
        challenge.topUpRewards(poolAmount);
        vm.stopPrank();
    }
 
    function _whitelist(address trader) internal {
        vm.prank(owner);
        challenge.setAllowed(trader, true);
    }
 
    function _mintToUser(address trader, uint256 amount) internal {
        vm.prank(owner);
        usdc.mint(trader, amount);
    }
 
    function _approveFee(address trader) internal {
        vm.prank(trader);
        usdc.approve(address(challenge), FEE);
    }
 
    function _startChallenge(address trader) internal {
        vm.prank(trader);
        challenge.startChallenge();
    }
 
    function testHappyPath_StartAndClaimReward() public {
        // fund enough rewards
        _mintAndFundPool(500_000_000); // 500 USDC
 
        // whitelist user
        _whitelist(user);
 
        // user starts with 100 USDC
        _mintToUser(user, 100_000_000);
 
        // user approves fee and starts challenge
        _approveFee(user);
        _startChallenge(user);
 
        // After paying 10 fee from 100, user should have 90 remaining
        (
            address player,
            uint256 startBalanceAfterFee,
            uint256 startTime,
            bool active,
            uint256 rewardSnap,
            uint256 durationSnap
        ) = challenge.challenges(1);
 
        assertEq(player, user);
        assertEq(startBalanceAfterFee, 90_000_000);
        assertTrue(active);
        assertEq(rewardSnap, REWARD);
        assertEq(durationSnap, DURATION);
        assertGt(startTime, 0);
 
        // pass target should be double remaining = 180 USDC
        uint256 target = challenge.passTarget(1);
        assertEq(target, 180_000_000);
 
        // Give user another 90 USDC so they can pass
        _mintToUser(user, 90_000_000);
 
        uint256 userBalanceBefore = usdc.balanceOf(user);
        uint256 rewardPoolBefore = challenge.rewardPool();
        uint256 reservedBefore = challenge.activeRewardReserved();
 
        // claim reward
        vm.prank(user);
        challenge.claimReward(1);
 
        uint256 userBalanceAfter = usdc.balanceOf(user);
        uint256 rewardPoolAfter = challenge.rewardPool();
        uint256 reservedAfter = challenge.activeRewardReserved();
 
        // user gets REWARD added
        assertEq(userBalanceAfter, userBalanceBefore + REWARD);
 
        // pool reduced by reward
        assertEq(rewardPoolAfter, rewardPoolBefore - REWARD);
 
        // reserved released
        assertEq(reservedAfter, reservedBefore - REWARD);
 
        // challenge should be reset
        (
            address playerAfter,
            uint256 startBalanceAfterFeeAfter,
            uint256 startTimeAfter,
            bool activeAfter,
            uint256 rewardSnapAfter,
            uint256 durationSnapAfter
        ) = challenge.challenges(1);
 
        assertEq(playerAfter, address(0));
        assertEq(startBalanceAfterFeeAfter, 0);
        assertEq(startTimeAfter, 0);
        assertFalse(activeAfter);
        assertEq(rewardSnapAfter, 0);
        assertEq(durationSnapAfter, 0);
    }
 
    function testNonWhitelistedUserCannotStart() public {
        _mintAndFundPool(500_000_000);
        _mintToUser(user, 100_000_000);
 
        vm.prank(user);
        usdc.approve(address(challenge), FEE);
 
        vm.prank(user);
        vm.expectRevert("not whitelisted");
        challenge.startChallenge();
    }
 
    function testUserNeedsAtLeastOneDollarLeftAfterFee() public {
        _mintAndFundPool(500_000_000);
        _whitelist(user);
 
        // exactly fee, leaving 0 after fee
        _mintToUser(user, FEE);
 
        vm.prank(user);
        usdc.approve(address(challenge), FEE);
 
        vm.prank(user);
        vm.expectRevert("must have at least $1 remaining");
        challenge.startChallenge();
    }
 
    function testCannotStartWithoutEnoughRewardPool() public {
        // no pool funding
        _whitelist(user);
        _mintToUser(user, 100_000_000);
 
        vm.prank(user);
        usdc.approve(address(challenge), FEE);
 
        vm.prank(user);
        vm.expectRevert("insufficient rewards");
        challenge.startChallenge();
    }
 
    function testMaxThreeChallengesPerWallet() public {
        // enough pool for many challenges
        _mintAndFundPool(500_000_000);
        _whitelist(user);
 
        // user needs enough balance to pay fee 3 times and still have >= $1 after each
        _mintToUser(user, 100_000_000);
 
        // first
        vm.prank(user);
        usdc.approve(address(challenge), type(uint256).max);
 
        vm.prank(user);
        challenge.startChallenge();
 
        // manually expire and finalize first so user can start again
        vm.warp(block.timestamp + DURATION + 1);
        challenge.finalizeIfExpired(1);
 
        // second
        vm.prank(user);
        challenge.startChallenge();
 
        vm.warp(block.timestamp + DURATION + 1);
        challenge.finalizeIfExpired(2);
 
        // third
        vm.prank(user);
        challenge.startChallenge();
 
        vm.warp(block.timestamp + DURATION + 1);
        challenge.finalizeIfExpired(3);
 
        // fourth should fail regardless of active status, because max started is 3
        vm.prank(user);
        vm.expectRevert("max challenges reached");
        challenge.startChallenge();
    }
 
    function testClaimFailsIfTargetNotMet() public {
        _mintAndFundPool(500_000_000);
        _whitelist(user);
        _mintToUser(user, 100_000_000);
 
        _approveFee(user);
        _startChallenge(user);
 
        vm.prank(user);
        vm.expectRevert("target not met");
        challenge.claimReward(1);
    }
 
    function testClaimFailsIfExpired() public {
        _mintAndFundPool(500_000_000);
        _whitelist(user);
        _mintToUser(user, 200_000_000);
 
        _approveFee(user);
        _startChallenge(user);
 
        // even if we top user up enough, expiry should block claim
        _mintToUser(user, 200_000_000);
 
        vm.warp(block.timestamp + DURATION + 1);
 
        vm.prank(user);
        vm.expectRevert("expired");
        challenge.claimReward(1);
    }
 
    function testFinalizeExpiredReleasesReservedReward() public {
        _mintAndFundPool(500_000_000);
        _whitelist(user);
        _mintToUser(user, 100_000_000);
 
        _approveFee(user);
        _startChallenge(user);
 
        uint256 reservedBefore = challenge.activeRewardReserved();
        assertEq(reservedBefore, REWARD);
 
        vm.warp(block.timestamp + DURATION + 1);
        challenge.finalizeIfExpired(1);
 
        uint256 reservedAfter = challenge.activeRewardReserved();
        assertEq(reservedAfter, 0);
 
        (, , , bool activeAfter, , ) = challenge.challenges(1);
        assertFalse(activeAfter);
    }
 
    function testOnlyOwnerCanWhitelistAndFund() public {
        // non-owner cannot whitelist
        vm.prank(user);
        vm.expectRevert("not owner");
        challenge.setAllowed(user, true);
 
        // non-owner cannot top up
        _mintToUser(user, 100_000_000);
 
        vm.prank(user);
        usdc.approve(address(challenge), 100_000_000);
 
        vm.prank(user);
        vm.expectRevert("not owner");
        challenge.topUpRewards(100_000_000);
    }
 
    function testAvailableRewardPoolTracksReservations() public {
        _mintAndFundPool(500_000_000);
        _whitelist(user);
        _whitelist(user2);
 
        _mintToUser(user, 100_000_000);
        _mintToUser(user2, 100_000_000);
 
        _approveFee(user);
        _startChallenge(user);
 
        assertEq(challenge.rewardPool(), 500_000_000);
        assertEq(challenge.activeRewardReserved(), 50_000_000);
        assertEq(challenge.availableRewardPool(), 450_000_000);
 
        _approveFee(user2);
        _startChallenge(user2);
 
        assertEq(challenge.activeRewardReserved(), 100_000_000);
        assertEq(challenge.availableRewardPool(), 400_000_000);
    }

    function testFinalizeIfFailed() public {
     
	_mintToUser(owner, 500_000_000);
        // Fund reward pool
        vm.startPrank(owner);
        usdc.approve(address(challenge), 500_000_000);
        challenge.topUpRewards(500_000_000);
        vm.stopPrank();
     
        // Whitelist user
        vm.prank(owner);
        challenge.setAllowed(user, true);
     
        // Give trader USDC
        _mintToUser(user, 100_000_000);
     
        // Approve fee
        vm.prank(user);
        usdc.approve(address(challenge), 10_000_000);
     
        // Start challenge
        vm.prank(user);
        uint256 id = challenge.startChallenge();
     
        // Verify reward reserved
        assertEq(challenge.activeRewardReserved(), 50_000_000);
     
        // Trader loses $5
        vm.prank(user);
        usdc.transfer(user2, 5_000_000);
     
        // Finalize failure
        challenge.finalizeIfFailed(id);
     
        // Reserved reward released
        assertEq(challenge.activeRewardReserved(), 0);
     
        // Challenge inactive
        (
            address player,
            ,
            ,
            bool active,
            ,
     
        ) = challenge.challenges(id);
     
        assertEq(player, address(0));
        assertFalse(active);
     
        // Trader can start another challenge
        _mintToUser(user, 20_000_000);
     
        vm.prank(user);
        usdc.approve(address(challenge), 10_000_000);
     
        vm.prank(user);
        challenge.startChallenge();
    }

}
