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
    }

    struct MaintenanceRequest {
        uint256 agreementId;
        bool isApproved;
        address assignedContractor;
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

    mapping(uint256 => Agreement) public agreements;
    mapping(address => uint256) public userEscrowBalance;
    mapping(address => string) public userKYCHash;
    mapping(address => uint8[]) public contractorRatings;
    mapping(address => string[]) public contractorSkills;
    mapping(address => bool) public verifiedContractors;
    mapping(uint256 => uint256) public pendingRentChanges;
    mapping(uint256 => bool) public agreementLocked;

    EmergencyMaintenance[] public emergencyRequests;
    MaintenanceRequest[] public maintenanceRequests;
    Dispute[] public disputes;

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

    // ------------------- Core Functions -------------------

    function acceptRentChange(uint256 _agreementId) 
        external nonReentrant whenNotPaused agreementExists(_agreementId) onlyTenant(_agreementId) 
    {
        uint256 newRent = pendingRentChanges[_agreementId];
        require(newRent > 0, "No proposed rent change");
        agreements[_agreementId].monthlyRent = newRent;
        delete pendingRentChanges[_agreementId];
        emit RentChangeAccepted(_agreementId, newRent);
    }

    function withdrawEscrow() external nonReentrant whenNotPaused {
        require(userEscrowBalance[msg.sender] > 0, "No balance to withdraw");
        require(!_hasActiveAgreement(msg.sender), "Active agreement exists");

        uint256 balance = userEscrowBalance[msg.sender];
        userEscrowBalance[msg.sender] = 0;
        payable(msg.sender).transfer(balance);
        emit EscrowWithdrawn(msg.sender, balance);
    }

    function depositSecurity(uint256 _agreementId) external payable whenNotPaused {
        Agreement storage a = agreements[_agreementId];
        require(msg.sender == a.landlord, "Only landlord");
        require(msg.value > 0, "No deposit amount");

        userEscrowBalance[a.tenant] += msg.value;
        emit SecurityDepositAdded(_agreementId, msg.sender, msg.value);
    }

    function resolveEmergency(uint256 _requestId) external onlyAdmin {
        EmergencyMaintenance storage request = emergencyRequests[_requestId];
        require(!request.resolved, "Already resolved");
        request.resolved = true;
        emit EmergencyMaintenanceResolved(_requestId);
    }

    function emergencyPause() external onlyAdmin { _pause(); emit EmergencyPaused(); }
    function resume() external onlyAdmin { _unpause(); emit EmergencyResumed(); }

    function raiseDispute(uint256 _agreementId, string memory _reason) 
        external agreementExists(_agreementId) onlyAgreementParties(_agreementId) 
    {
        disputes.push(Dispute(_agreementId, msg.sender, _reason, false, ""));
        emit DisputeRaised(disputes.length - 1, _agreementId, msg.sender, _reason);
    }

    function resolveDispute(uint256 _disputeId, string memory _resolutionNote) external onlyAdmin {
        Dispute storage d = disputes[_disputeId];
        require(!d.resolved, "Already resolved");
        d.resolved = true;
        d.resolutionNote = _resolutionNote;
        emit DisputeResolved(_disputeId, _resolutionNote);
    }

    function rateContractor(address _contractor, uint8 _rating) external {
        require(_rating >= 1 && _rating <= 5, "Rating 1-5 required");
        require(_hasTenantWorkedWithContractor(msg.sender, _contractor), "Not authorized");
        contractorRatings[_contractor].push(_rating);
        emit ContractorRated(_contractor, _rating);
    }

    // ------------------- New Features -------------------

    function toggleAutoRenewal(uint256 _agreementId) external onlyTenant(_agreementId) {
        Agreement storage a = agreements[_agreementId];
        a.autoRenewal = !a.autoRenewal;
        emit AutoPaymentSetup(_agreementId, msg.sender, a.autoRenewal);
    }

    function lockAgreement(uint256 _agreementId, bool _lock) external onlyAdmin {
        agreementLocked[_agreementId] = _lock;
        emit AgreementLocked(_agreementId, _lock);
    }

    function getDisputesByAgreement(uint256 _agreementId) external view returns (Dispute[] memory) {
        uint256 count;
        for (uint i = 0; i < disputes.length; i++) if (disputes[i].agreementId == _agreementId) count++;
        Dispute[] memory result = new Dispute[](count);
        uint256 idx;
        for (uint i = 0; i < disputes.length; i++) if (disputes[i].agreementId == _agreementId) result[idx++] = disputes[i];
        return result;
    }

    function getActiveAgreementsByUser(address _user) external view returns (Agreement[] memory) {
        uint256 count;
        for (uint i = 0; i < 100; i++) 
            if ((agreements[i].tenant == _user || agreements[i].landlord == _user) && agreements[i].isActive) count++;

        Agreement[] memory result = new Agreement[](count);
        uint256 idx;
        for (uint i = 0; i < 100; i++)
            if ((agreements[i].tenant == _user || agreements[i].landlord == _user) && agreements[i].isActive)
                result[idx++] = agreements[i];
        return result;
    }

    function getUserEscrow(address _user) external view returns (uint256) {
        return userEscrowBalance[_user];
    }

    function getContractorAverageRating(address _contractor) external view returns (uint256) {
        uint8[] memory ratings = contractorRatings[_contractor];
        require(ratings.length > 0, "No ratings");
        uint256 total;
        for (uint i = 0; i < ratings.length; i++) total += ratings[i];
        return total / ratings.length;
    }

    function getEmergencyRequestsByAgreement(uint256 _agreementId) external view returns (EmergencyMaintenance[] memory) {
        uint256 count;
        for (uint i = 0; i < emergencyRequests.length; i++) if (emergencyRequests[i].agreementId == _agreementId) count++;
        EmergencyMaintenance[] memory result = new EmergencyMaintenance[](count);
        uint256 idx;
        for (uint i = 0; i < emergencyRequests.length; i++) if (emergencyRequests[i].agreementId == _agreementId) result[idx++] = emergencyRequests[i];
        return result;
    }

    // ------------------- Internal Helpers -------------------
    function _hasActiveAgreement(address _user) internal view returns (bool) {
        for (uint i = 0; i < 100; i++) 
            if (agreements[i].tenant == _user && agreements[i].isActive) return true;
        return false;
    }

    function _hasTenantWorkedWithContractor(address _tenant, address _contractor) internal view returns (bool) {
        for (uint i = 0; i < maintenanceRequests.length; i++)
            if (maintenanceRequests[i].assignedContractor == _contractor &&
                agreements[maintenanceRequests[i].agreementId].tenant == _tenant) return true;
        return false;
    }
}
