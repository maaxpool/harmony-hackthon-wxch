// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "../controller/ControllerInterface.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Bridge is Ownable {

    enum RequestStatus {PENDING, CANCELED, APPROVED, REJECTED}

    struct Request {
        address requester; // sender of the request.
        uint amount; // amount of token to mint/burn.
        string depositAddress; // custodian's asset address in mint, broker's asset address in burn.
        string txid; // asset txid for sending/redeeming asset in the mint/burn process.
        uint nonce; // serial number allocated for each request.
        uint timestamp; // time of the request creation.
        RequestStatus status; // status of the request.
    }

    ControllerInterface public controller;

    // mapping between broker to the corresponding custodian deposit address, used in the minting process.
    // by using a different deposit address per broker the custodian can identify which broker deposited.
    mapping(address=>string) public custodianDepositAddress;

    // mapping between broker to the its deposit address where the asset should be moved to, used in the burning process.
    mapping(address=>string) public brokerDepositAddress;

    // mapping between a mint request hash and the corresponding request nonce. 
    mapping(bytes32=>uint) public mintRequestNonce;

    // mapping between a burn request hash and the corresponding request nonce.
    mapping(bytes32=>uint) public burnRequestNonce;

    Request[] public mintRequests;
    Request[] public burnRequests;

    constructor(address _controller) {
        require(_controller != address(0), "invalid _controller address");
        controller = ControllerInterface(_controller);
        transferOwnership(_controller);
    }

    modifier onlyBroker() {
        require(controller.isBroker(msg.sender), "sender not a broker.");
        _;
    }

    modifier onlyCustodian() {
        require(controller.isCustodian(msg.sender), "sender not a custodian.");
        _;
    }

    event CustodianDepositAddressSet(address indexed broker, address indexed sender, string depositAddress);

    function setCustodianDepositAddress(
        address broker,
        string memory depositAddress
    )
        external
        onlyCustodian
        returns (bool) 
    {
        require(broker != address(0), "invalid broker address");
        require(controller.isBroker(broker), "broker address is not a real broker.");
        require(!isEmptyString(depositAddress), "invalid asset deposit address");

        custodianDepositAddress[broker] = depositAddress;
        emit CustodianDepositAddressSet(broker, msg.sender, depositAddress);
        return true;
    }

    event BrokerDepositAddressSet(address indexed broker, string depositAddress);

    function setBrokerDepositAddress(string memory depositAddress) external onlyBroker returns (bool) {
        require(!isEmptyString(depositAddress), "invalid asset deposit address");

        brokerDepositAddress[msg.sender] = depositAddress;
        emit BrokerDepositAddressSet(msg.sender, depositAddress);
        return true; 
    }

    event MintRequestAdd(
        uint indexed nonce,
        address indexed requester,
        uint amount,
        string depositAddress,
        string txid,
        uint timestamp,
        bytes32 requestHash
    );

    function addMintRequest(
        uint amount,
        string memory txid,
        string memory depositAddress
    )
        external
        onlyBroker
        returns (bool)
    {
        require(!isEmptyString(depositAddress), "invalid asset deposit address"); 
        require(compareStrings(depositAddress, custodianDepositAddress[msg.sender]), "wrong asset deposit address");

        uint nonce = mintRequests.length;
        uint timestamp = getTimestamp();

        Request memory request = Request({
            requester: msg.sender,
            amount: amount,
            depositAddress: depositAddress,
            txid: txid,
            nonce: nonce,
            timestamp: timestamp,
            status: RequestStatus.PENDING
        });

        bytes32 requestHash = calcRequestHash(request);
        mintRequestNonce[requestHash] = nonce; 
        mintRequests.push(request);

        emit MintRequestAdd(nonce, msg.sender, amount, depositAddress, txid, timestamp, requestHash);
        return true;
    }

    event MintRequestCancel(uint indexed nonce, address indexed requester, bytes32 requestHash);

    function cancelMintRequest(bytes32 requestHash) external onlyBroker returns (bool) {
        uint nonce;
        Request memory request;

        (nonce, request) = getPendingMintRequest(requestHash);

        require(msg.sender == request.requester, "cancel sender is different than pending request initiator");
        mintRequests[nonce].status = RequestStatus.CANCELED;

        emit MintRequestCancel(nonce, msg.sender, requestHash);
        return true;
    }

    event MintConfirmed(
        uint indexed nonce,
        address indexed requester,
        uint amount,
        string depositAddress,
        string txid,
        uint timestamp,
        bytes32 requestHash
    );

    function confirmMintRequest(bytes32 requestHash) external onlyCustodian returns (bool) {
        uint nonce;
        Request memory request;

        (nonce, request) = getPendingMintRequest(requestHash);

        mintRequests[nonce].status = RequestStatus.APPROVED;
        require(controller.mint(request.requester, request.amount), "mint failed");

        emit MintConfirmed(
            request.nonce,
            request.requester,
            request.amount,
            request.depositAddress,
            request.txid,
            request.timestamp,
            requestHash
        );
        return true;
    }

    event MintRejected(
        uint indexed nonce,
        address indexed requester,
        uint amount,
        string depositAddress,
        string txid,
        uint timestamp,
        bytes32 requestHash
    );

    function rejectMintRequest(bytes32 requestHash) external onlyCustodian returns (bool) {
        uint nonce;
        Request memory request;

        (nonce, request) = getPendingMintRequest(requestHash);

        mintRequests[nonce].status = RequestStatus.REJECTED;

        emit MintRejected(
            request.nonce,
            request.requester,
            request.amount,
            request.depositAddress,
            request.txid,
            request.timestamp,
            requestHash
        );
        return true;
    }

    event Burned(
        uint indexed nonce,
        address indexed requester,
        uint amount,
        string depositAddress,
        uint timestamp,
        bytes32 requestHash
    );

    function burn(uint amount) external onlyBroker returns (bool) {
        string memory depositAddress = brokerDepositAddress[msg.sender];
        require(!isEmptyString(depositAddress), "broker asset deposit address was not set");

        uint nonce = burnRequests.length;
        uint timestamp = getTimestamp();

        // set txid as empty since it is not known yet.
        string memory txid = "";
        Request memory request = Request({
            requester: msg.sender,
            amount: amount,
            depositAddress: depositAddress,
            txid: txid,
            nonce: nonce,
            timestamp: timestamp,
            status: RequestStatus.PENDING
        });

        bytes32 requestHash = calcRequestHash(request);
        burnRequestNonce[requestHash] = nonce; 
        burnRequests.push(request);

        require(controller.getToken().transferFrom(msg.sender, address(controller), amount), "transfer tokens to burn failed");
        require(controller.burn(amount), "burn failed");

        emit Burned(nonce, msg.sender, amount, depositAddress, timestamp, requestHash);
        return true;
    }

    event BurnConfirmed(
        uint indexed nonce,
        address indexed requester,
        uint amount,
        string depositAddress,
        string txid,
        uint timestamp,
        bytes32 inputRequestHash
    );

    function confirmBurnRequest(bytes32 requestHash, string memory txid) external onlyCustodian returns (bool) {
        uint nonce;
        Request memory request;

        (nonce, request) = getPendingBurnRequest(requestHash);

        burnRequests[nonce].txid = txid;
        burnRequests[nonce].status = RequestStatus.APPROVED;
        burnRequestNonce[calcRequestHash(burnRequests[nonce])] = nonce;

        emit BurnConfirmed(
            request.nonce,
            request.requester,
            request.amount,
            request.depositAddress,
            txid,
            request.timestamp,
            requestHash
        );
        return true;
    }

    function getMintRequest(uint nonce)
        external
        view
        returns (
            uint requestNonce,
            address requester,
            uint amount,
            string memory depositAddress,
            string memory txid,
            uint timestamp,
            string memory status,
            bytes32 requestHash
        )
    {
        Request memory request = mintRequests[nonce];
        string memory statusString = getStatusString(request.status); 

        requestNonce = request.nonce;
        requester = request.requester;
        amount = request.amount;
        depositAddress = request.depositAddress;
        txid = request.txid;
        timestamp = request.timestamp;
        status = statusString;
        requestHash = calcRequestHash(request);
    }

    function getMintRequestsLength() external view returns (uint length) {
        return mintRequests.length;
    }

    function getBurnRequest(uint nonce)
        external
        view
        returns (
            uint requestNonce,
            address requester,
            uint amount,
            string memory depositAddress,
            string memory txid,
            uint timestamp,
            string memory status,
            bytes32 requestHash
        )
    {
        Request storage request = burnRequests[nonce];
        string memory statusString = getStatusString(request.status); 

        requestNonce = request.nonce;
        requester = request.requester;
        amount = request.amount;
        depositAddress = request.depositAddress;
        txid = request.txid;
        timestamp = request.timestamp;
        status = statusString;
        requestHash = calcRequestHash(request);
    }

    function getBurnRequestsLength() external view returns (uint length) {
        return burnRequests.length;
    }

    function getTimestamp() internal view returns (uint) {
        // timestamp is only used for data maintaining purpose, it is not relied on for critical logic.
        return block.timestamp; // solhint-disable-line not-rely-on-time
    }

    function getPendingMintRequest(bytes32 requestHash) internal view returns (uint nonce, Request memory request) {
        require(requestHash != 0, "request hash is 0");
        nonce = mintRequestNonce[requestHash];
        request = mintRequests[nonce];
        validatePendingRequest(request, requestHash);
    }

    function getPendingBurnRequest(bytes32 requestHash) internal view returns (uint nonce, Request memory request) {
        require(requestHash != 0, "request hash is 0");
        nonce = burnRequestNonce[requestHash];
        request = burnRequests[nonce];
        validatePendingRequest(request, requestHash);
    }

    function validatePendingRequest(Request memory request, bytes32 requestHash) internal pure {
        require(request.status == RequestStatus.PENDING, "request is not pending");
        require(requestHash == calcRequestHash(request), "given request hash does not match a pending request");
    }

    function calcRequestHash(Request memory request) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            request.requester,
            request.amount,
            request.depositAddress,
            request.txid,
            request.nonce,
            request.timestamp
        ));
    }

    function compareStrings (string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)));
    }

    function isEmptyString (string memory a) internal pure returns (bool) {
        return (compareStrings(a, ""));
    }

    function getStatusString(RequestStatus status) internal pure returns (string memory) {
        if (status == RequestStatus.PENDING) {
            return "pending";
        } else if (status == RequestStatus.CANCELED) {
            return "canceled";
        } else if (status == RequestStatus.APPROVED) {
            return "approved";
        } else if (status == RequestStatus.REJECTED) {
            return "rejected";
        } else {
            // this fallback can never be reached.
            return "unknown";
        }
    }
}
