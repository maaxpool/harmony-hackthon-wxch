// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "./ControllerInterface.sol";
import "../bridge/MembersInterface.sol";
import "../token/WrappedToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Controller is ControllerInterface, Ownable {

    WrappedToken public token;
    MembersInterface public members;
    address public bridge;

    constructor(WrappedToken _token) {
        require(_token != WrappedToken(address(0)), "invalid _token address");
        token = _token;
    }

    modifier onlyBridge() {
        require(msg.sender == bridge, "sender not authorized for minting or burning.");
        _;
    }

    // setters
    event MembersSet(MembersInterface indexed members);

    function setMembers(MembersInterface _members) external onlyOwner returns (bool) {
        require(_members != MembersInterface(address(0)), "invalid _members address");
        members = _members;
        emit MembersSet(members);
        return true;
    }

    event BridgeSet(address indexed bridge);

    function setBridge(address _bridge) external onlyOwner returns (bool) {
        require(_bridge != address(0), "invalid _bridge address");
        bridge = _bridge;
        emit BridgeSet(bridge);
        return true;
    }

    // only owner actions on token
    event Paused();

    function pause() external onlyOwner returns (bool) {
        token.pause();
        emit Paused();
        return true;
    }

    event Unpaused();

    function unpause() external onlyOwner returns (bool) {
        token.unpause();
        emit Unpaused();
        return true;
    }

    // only bridge actions on token
    function mint(address to, uint amount) external override onlyBridge returns (bool) {
        require(to != address(0), "invalid to address");
        require(!token.paused(), "token is paused.");
        token.mint(to, amount);
        return true;
    }

    function burn(uint value) external override onlyBridge returns (bool) {
        require(!token.paused(), "token is paused.");
        token.burn(value);
        return true;
    }

    // all accessible
    function isCustodian(address addr) external override view returns (bool) {
        return members.isCustodian(addr);
    }

    function isBroker(address addr) external override view returns (bool) {
        return members.isBroker(addr);
    }

    function getToken() external override view returns (ERC20) {
        return token;
    }

    // overriding
    function renounceOwnership() public override onlyOwner {
        revert("renouncing ownership is blocked.");
    }
}
