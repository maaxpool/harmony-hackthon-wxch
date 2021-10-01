// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "../bridge/MembersInterface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract Members is MembersInterface, Ownable {

    address public custodian;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet internal brokers;

    constructor(address _owner) public {
        require(_owner != address(0), "invalid _owner address");
        transferOwnership(_owner);
    }

    event CustodianSet(address indexed custodian);

    function setCustodian(address _custodian) external override onlyOwner returns (bool) {
        require(_custodian != address(0), "invalid custodian address");
        custodian = _custodian;

        emit CustodianSet(_custodian);
        return true;
    }

    event BrokerAdd(address indexed broker);

    function addBroker(address broker) external override onlyOwner returns (bool) {
        require(broker != address(0), "invalid broker address");
        require(brokers.add(broker), "broker add failed");

        emit BrokerAdd(broker);
        return true;
    } 

    event BrokerRemove(address indexed broker);

    function removeBroker(address broker) external override onlyOwner returns (bool) {
        require(broker != address(0), "invalid broker address");
        require(brokers.remove(broker), "broker remove failed");

        emit BrokerRemove(broker);
        return true;
    }

    function isCustodian(address addr) external override view returns (bool) {
        return (addr == custodian);
    }

    function isBroker(address addr) external override view returns (bool) {
        return brokers.contains(addr);
    }

    function getBroker(uint index) external view returns (address) {
        return brokers.at(index);
    }

    function getBrokersCount() external view returns (uint) {
        return brokers.length();
    }
}
