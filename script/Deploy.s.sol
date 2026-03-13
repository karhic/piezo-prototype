// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
 
import "forge-std/Script.sol";
import "../src/MultiSlotChallenge.sol";
 
contract Deploy is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
 
        vm.startBroadcast(pk);
 
        new MultiSlotChallenge(
            address(0x123),
            vm.addr(pk),
            10_000_000,
            50_000_000,
            86400
        );
 
        vm.stopBroadcast();
    }
}

