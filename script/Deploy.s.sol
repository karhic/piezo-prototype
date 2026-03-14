// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
 
import "forge-std/Script.sol";
import "forge-std/console2.sol";
import "../src/MultiSlotChallenge.sol";
import "../src/MockUSDC.sol";
 
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address owner = vm.addr(pk);
 
        vm.startBroadcast(pk);
 
        MockUSDC usdc = new MockUSDC();
 
        MultiSlotChallenge challenge = new MultiSlotChallenge(
            address(usdc),
            owner,
            10_000_000, // $10 fee
            50_000_000, // $50 reward
            86400       // 1 day
        );
 
        vm.stopBroadcast();
 
        console2.log("MockUSDC:", address(usdc));
        console2.log("MultiSlotChallenge:", address(challenge));
        console2.log("Owner:", owner);
    }
}
