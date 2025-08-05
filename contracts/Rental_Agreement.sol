// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract RentalAgreement is ReentrancyGuard, Pausable {
    address public admin;

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

    uint256 public totalPlatformFees;

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

    function acceptRentChange(uint256 _agreementId) external nonReentrant whenNotPaused agreementExists(_agreementId) onlyTenant(_agreementId) {
        uint256 newRent = pendingRentChanges[_agreementId];
        require(newRent > 0, "No proposed rent change");
        agreements[_agreementId].monthlyRent = newRent;
        delete pendingRentChanges[_agreementId];
        emit RentChangeAccepted(_agreementId, newRent);
    }

    function withdrawEscrow() external nonReentrant whenNotPaused {
        uint256 balance = userEscrowBalance[msg.sender];
        require(balance > 0, "No balance to withdraw");

        bool hasActive = false;
        for (uint256 i = 0; i < 100; i++) {
            if (agreements[i].tenant == msg.sender && agreements[i].isActive) {
                hasActive = true;
                break;
            }
        }

        require(!hasActive, "Active agreement exists");
        userEscrowBalance[msg.sender] = 0;
        payable(msg.sender).transfer(balance);
        emit EscrowWithdrawn(msg.sender, balance);
    }

    function resolveEmergency(uint256 _requestId) external onlyAdmin {
        require(_requestId < emergencyRequests.length, "Invalid request ID");
        EmergencyMaintenance storage request = emergencyRequests[_requestId];
        require(!request.resolved, "Already resolved");
        request.resolved = true;
        emit EmergencyMaintenanceResolved(_requestId);
    }

    function emergencyPause() external onlyAdmin {
        _pause();
        emit EmergencyPaused();
    }

    function resume() external onlyAdmin {
        _unpause();
        emit EmergencyResumed();
    }

    function depositSecurity(uint256 _agreementId) external payable whenNotPaused {
        Agreement memory a = agreements[_agreementId];
        require(msg.sender == a.landlord, "Only landlord");
        require(msg.value > 0, "No deposit amount");

        userEscrowBalance[a.tenant] += msg.value;
        emit SecurityDepositAdded(_agreementId, msg.sender, msg.value);
    }

    function getContractorAverageRating(address _contractor) external view returns (uint256) {
        uint8[] memory ratings = contractorRatings[_contractor];
        require(ratings.length > 0, "No ratings");
        uint256 total;
        for (uint256 i = 0; i < ratings.length; i++) {
            total += ratings[i];
        }
        return total / ratings.length;
    }

    function getEmergencyRequestsByAgreement(uint256 _agreementId) external view returns (EmergencyMaintenance[] memory) {
        uint256 count;
        for (uint256 i = 0; i < emergencyRequests.length; i++) {
            if (emergencyRequests[i].agreementId == _agreementId) count++;
        }

        EmergencyMaintenance[] memory result = new EmergencyMaintenance[](count);
        uint256 idx;
        for (uint256 i = 0; i < emergencyRequests.length; i++) {
            if (emergencyRequests[i].agreementId == _agreementId) {
                result[idx++] = emergencyRequests[i];
            }
        }
        return result;
    }


    function raiseDispute(uint256 _agreementId, string memory _reason) external agreementExists(_agreementId) onlyAgreementParties(_agreementId) {
        disputes.push(Dispute({
            agreementId: _agreementId,
            raisedBy: msg.sender,
            reason: _reason,
            resolved: false,
            resolutionNote: ""
        }));
        emit DisputeRaised(disputes.length - 1, _agreementId, msg.sender, _reason);
    }

    function resolveDispute(uint256 _disputeId, string memory _resolutionNote) external onlyAdmin {
        require(_disputeId < disputes.length, "Invalid dispute ID");
        Dispute storage d = disputes[_disputeId];
        require(!d.resolved, "Already resolved");
        d.resolved = true;
        d.resolutionNote = _resolutionNote;
        emit DisputeResolved(_disputeId, _resolutionNote);
    }

    // --- New Functionality: Tenant Contractor Rating ---
    function rateContractor(address _contractor, uint8 _rating) external {
        require(_rating >= 1 && _rating <= 5, "Rating must be between 1 and 5");

        bool isParty = false;
        for (uint256 i = 0; i < maintenanceRequests.length; i++) {
            if (
                maintenanceRequests[i].assignedContractor == _contractor &&
                agreements[maintenanceRequests[i].agreementId].tenant == msg.sender
            ) {
                isParty = true;
                break;
            }
        }

        require(isParty, "You can't rate this contractor");

        contractorRatings[_contractor].push(_rating);
        emit ContractorRated(_contractor, _rating);
    }
}


