/**
 * Copyright 2017-2020, bZeroX, LLC. All Rights Reserved.
 * Licensed under the Apache License, Version 2.0.
 */

pragma solidity >=0.5.0 <=0.6.12;
pragma experimental ABIEncoderV2;

/// SPDX-License-Identifier: MIT
interface IKeep3rV1 {
    function isKeeper(address) external returns (bool);

    function worked(address keeper) external;
}
