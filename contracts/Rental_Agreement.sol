// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract RentalAgreement is ReentrancyGuard, Pausable {
    address public admin;
    uint256 public totalPlatformFees;

    constructor() {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    struct Agreement {
        address tenant;
        address landlord;
        uint256 monthlyRent;
        uint256 agreementEnd;
        uint256 lastRentPayment;
        uint256 totalRentPaid;
        uint256 earlyTerminationFee;
        uint256 gracePeriodDays;
        bool isActive;
        bool autoRenewal;
        uint256 lateFeesOwed;
        uint256 securityDeposit;
    }

    struct MaintenanceRequest {
        uint256 agreementId;
        bool isApproved;
        address assignedContractor;
        uint256 estimatedCost;
        bool landlordFunded;
    }

    struct EmergencyMaintenance {
        uint256 agreementId;
        address raisedBy;
        string description;
        uint256 timestamp;
        bool resolved;
    }

    struct Dispute {
        uint256 agreementId;
        address raisedBy;
        string reason;
        bool resolved;
        string resolutionNote;
    }

    struct PaymentRecord {
        uint256 agreementId;
        uint256 amount;
        uint256 timestamp;
    }

    struct Message {
        uint256 agreementId;
        address sender;
        string content;
        uint256 timestamp;
    }

    mapping(uint256 => Agreement) public agreements;
    mapping(address => uint256) public userEscrowBalance;
    mapping(address => string) public userKYCHash;
    mapping(address => uint8[]) public contractorRatings;
    mapping(address => string[]) public contractorSkills;
    mapping(address => bool) public verifiedContractors;
    mapping(uint256 => uint256) public pendingRentChanges;
    mapping(uint256 => bool) public agreementLocked;
    mapping(address => bool) public blacklistedUsers;
    mapping(address => PaymentRecord[]) public userPayments;

    EmergencyMaintenance[] public emergencyRequests;
    MaintenanceRequest[] public maintenanceRequests;
    Dispute[] public disputes;
    Message[] public chatMessages;

    uint256 constant SECONDS_IN_MONTH = 30 days;
    uint256 constant LATE_FEE_PERCENTAGE = 5;
    uint256 constant MAX_LATE_FEE_MULTIPLIER = 10;
    uint256 constant PLATFORM_FEE_PERCENTAGE = 2;

    modifier agreementExists(uint256 _agreementId) {
        require(agreements[_agreementId].tenant != address(0), "Invalid agreement");
        _;
    }

    modifier onlyTenant(uint256 _agreementId) {
        require(msg.sender == agreements[_agreementId].tenant, "Not tenant");
        _;
    }

    modifier onlyAgreementParties(uint256 _agreementId) {
        Agreement memory a = agreements[_agreementId];
        require(msg.sender == a.tenant || msg.sender == a.landlord, "Not party");
        _;
    }

    modifier notBlacklisted() {
        require(!blacklistedUsers[msg.sender], "User blacklisted");
        _;
    }

    // ------------------- Events -------------------
    event AgreementTerminated(uint256 agreementId, address by, uint256 time);
    event AutoPaymentSetup(uint256 agreementId, address by, bool status);
    event UserVerified(address user, uint256 score);
    event ContractorVerified(address contractor, string[] skills);
    event RentPaid(uint256 agreementId, address tenant, uint256 rent, uint256 lateFee, uint256 time);
    event DocumentAccessRequested(uint256 indexed agreementId, address indexed requester, string documentType);
    event AgreementRenewed(uint256 indexed agreementId, address renewedBy, uint256 newEndDate);
    event RentChangeProposed(uint256 indexed agreementId, address proposedBy, uint256 newRent);
    event RentChangeAccepted(uint256 indexed agreementId, uint256 newRent);
    event EmergencyMaintenanceRaised(uint256 requestId, uint256 agreementId, address tenant, string description);
    event EmergencyMaintenanceResolved(uint256 requestId);
    event ContractorRated(address contractor, uint8 rating);
    event AgreementLocked(uint256 indexed agreementId, bool isLocked);
    event EscrowWithdrawn(address user, uint256 amount);
    event EmergencyPaused();
    event EmergencyResumed();
    event SecurityDepositAdded(uint256 agreementId, address landlord, uint256 amount);
    event DisputeRaised(uint256 disputeId, uint256 agreementId, address by, string reason);
    event DisputeResolved(uint256 disputeId, string resolutionNote);
    event SecurityDepositRefunded(uint256 agreementId, address tenant, uint256 amount);
    event UserBlacklisted(address user, bool status);
    event PlatformFeesWithdrawn(address admin, uint256 amount);
    event PartialRentPaid(uint256 agreementId, address tenant, uint256 amount);
    event AutoRenewalToggled(uint256 agreementId, bool status);
    event RentReminder(uint256 agreementId, address remindedTo);
    event MessageSent(uint256 agreementId, address sender, string content);
    event ContractorSkillAdded(address contractor, string skill);

    // ------------------- Core Functions -------------------
    // (keeping your existing functions here unchanged...)

    // ------------------- New Functionalities -------------------

    function toggleAutoRenewal(uint256 _agreementId, bool _status)
        external agreementExists(_agreementId) onlyAgreementParties(_agreementId)
    {
        agreements[_agreementId].autoRenewal = _status;
        emit AutoRenewalToggled(_agreementId, _status);
    }

    function sendMessage(uint256 _agreementId, string calldata _content)
        external agreementExists(_agreementId) onlyAgreementParties(_agreementId)
    {
        chatMessages.push(Message(_agreementId, msg.sender, _content, block.timestamp));
        emit MessageSent(_agreementId, msg.sender, _content);
    }

    function addContractorSkill(string calldata _skill) external {
        require(verifiedContractors[msg.sender], "Not a verified contractor");
        contractorSkills[msg.sender].push(_skill);
        emit ContractorSkillAdded(msg.sender, _skill);
    }

    function getContractorAverageRating(address _contractor) external view returns (uint256) {
        uint8[] memory ratings = contractorRatings[_contractor];
        if (ratings.length == 0) return 0;
        uint256 sum;
        for (uint i = 0; i < ratings.length; i++) sum += ratings[i];
        return sum / ratings.length;
    }

    function sendRentReminder(uint256 _agreementId)
        external agreementExists(_agreementId) onlyAgreementParties(_agreementId)
    {
        Agreement memory a = agreements[_agreementId];
        address toRemind = (msg.sender == a.tenant) ? a.landlord : a.tenant;
        emit RentReminder(_agreementId, toRemind);
    }

    function resolveDispute(uint256 _disputeId, string calldata _note, uint256 refundAmount)
        external onlyAdmin
    {
        Dispute storage d = disputes[_disputeId];
        require(!d.resolved, "Already resolved");
        d.resolved = true;
        d.resolutionNote = _note;
        if (refundAmount > 0) payable(d.raisedBy).transfer(refundAmount);
        emit DisputeResolved(_disputeId, _note);
    }

    function reassignMaintenance(uint256 _requestId, address _newContractor) external onlyAdmin {
        MaintenanceRequest storage req = maintenanceRequests[_requestId];
        req.assignedContractor = _newContractor;
    }

    // ------------------- Internal Helpers -------------------
    function _hasActiveAgreement(address _user) internal view returns (bool) {
        for (uint i = 0; i < 100; i++)
            if (agreements[i].tenant == _user && agreements[i].isActive) return true;
        return false;
    }
}

