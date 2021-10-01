// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "./WrappedToken.sol";


contract WXCH is WrappedToken ("Wrapped XCH", "WXCH") {
    function decimals() public view override returns (uint8) {
        return 12;
    }
}