// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/MultiSlotChallenge.sol";
import "../src/MockUSDC.sol";

contract HappyPath is Script {
    uint256 constant FEE = 10_000_000; // 10 USDC
    uint256 constant TOP_UP_TO_PASS = 90_000_000; // 90 USDC

    function run() external {
        uint256 ownerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerKey);

        uint256 userKey = vm.envUint("USER_KEY");
        address user = vm.addr(userKey);

        address usdcAddr = vm.envAddress("MOCK_USDC");
        address challengeAddr = vm.envAddress("CHALLENGE");

        MockUSDC usdc = MockUSDC(usdcAddr);
        MultiSlotChallenge challenge = MultiSlotChallenge(challengeAddr);

        // User approves and starts challenge
        vm.startBroadcast(userKey);

        usdc.approve(address(challenge), FEE);
        challenge.startChallenge();

        vm.stopBroadcast();

        // Owner tops user up to pass target
        vm.startBroadcast(ownerKey);

        usdc.mint(user, TOP_UP_TO_PASS);

        vm.stopBroadcast();

        // User claims reward
        vm.startBroadcast(userKey);

        challenge.claimReward(1);

        vm.stopBroadcast();

        console2.log("User:", user);
        console2.log("Final user balance:", usdc.balanceOf(user));
        console2.log("Reward pool:", challenge.rewardPool());
        console2.log("Reserved:", challenge.activeRewardReserved());
    }
}

