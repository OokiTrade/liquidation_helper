pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/// SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/UpgradeableProxy.sol";

contract BzxLiquidateProxy is UpgradeableProxy, Ownable {
    constructor(address initialImplementation, bytes memory data)
        public
        UpgradeableProxy(initialImplementation, data)
    {}
}
