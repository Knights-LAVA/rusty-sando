// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "foundry-huff/HuffDeployer.sol";
import "forge-std/Script.sol";

contract Deployer is Script {
    
    // serachers
    function setUp() public {
    }
    function run() public{
        address addr = HuffDeployer.deploy("sando");
        console.log(address(addr));
    }
}