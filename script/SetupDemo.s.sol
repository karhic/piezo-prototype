// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/MultiSlotChallenge.sol";
import "../src/MockUSDC.sol";

contract SetupDemo is Script {
    uint256 constant POOL_AMOUNT = 500_000_000; // 500 USDC
    uint256 constant USER_AMOUNT = 100_000_000; // 100 USDC

    function run() external {
        uint256 ownerKey = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(ownerKey);

        uint256 userKey = vm.envUint("USER_KEY");
        address user = vm.addr(userKey);

        address usdcAddr = vm.envAddress("MOCK_USDC");
        address challengeAddr = vm.envAddress("CHALLENGE");

        MockUSDC usdc = MockUSDC(usdcAddr);
        MultiSlotChallenge challenge = MultiSlotChallenge(challengeAddr);

        vm.startBroadcast(ownerKey);

        // Mint owner tokens and fund reward pool
        usdc.mint(owner, POOL_AMOUNT);
        usdc.approve(address(challenge), POOL_AMOUNT);
        challenge.topUpRewards(POOL_AMOUNT);

        // Whitelist user
        challenge.setAllowed(user, true);

        // Give user starting balance
        usdc.mint(user, USER_AMOUNT);

        vm.stopBroadcast();

        console2.log("Owner:", owner);
        console2.log("User:", user);
        console2.log("Reward pool:", challenge.rewardPool());
        console2.log("User balance:", usdc.balanceOf(user));
    }
}
