// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface ControllerInterface {
    function mint(address to, uint amount) external returns (bool);
    function burn(uint value) external returns (bool);
    function isCustodian(address addr) external view returns (bool);
    function isBroker(address addr) external view returns (bool);
    function getToken() external view returns (ERC20);
}
