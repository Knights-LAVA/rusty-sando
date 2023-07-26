// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "foundry-huff/HuffDeployer.sol";
import "forge-std/Script.sol";

contract SandoDeploy is Script {
    
    // serachers
    function setUp() public {
    }
    function run() public{
        address addr = HuffDeployer.broadcast("sando");
        console.log(address(addr));
    }
}

//forge script ./script/DeploySandwich.s.sol --rpc-url http://127.0.0.1:8545 --broadcast --private-key PRIVATE_KEY