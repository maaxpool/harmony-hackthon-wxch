// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;


interface MembersInterface {
    function setCustodian(address _custodian) external returns (bool);
    function addBroker(address broker) external returns (bool);
    function removeBroker(address broker) external returns (bool);
    function isCustodian(address addr) external view returns (bool);
    function isBroker(address addr) external view returns (bool);
}
