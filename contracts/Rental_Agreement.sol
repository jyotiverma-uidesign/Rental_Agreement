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

    mapping(uint256 => Agreement) public agreements;
    mapping(address => uint256) public userEscrowBalance;
    mapping(address => string) public userKYCHash;
    mapping(address => uint8[]) public contractorRatings;
    mapping(address => string[]) public contractorSkills;
    mapping(address => bool) public verifiedContractors;
    mapping(uint256 => uint256) public pendingRentChanges;
    mapping(uint256 => bool) public agreementLocked;

    EmergencyMaintenance[] public emergencyRequests;

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
    event EmergencyMaintenanceRaised(uint256 requestId, uint256 agreementId, address tenant, string description);
    event ContractorRated(address contractor, uint8 rating);
    event AgreementLocked(uint256 indexed agreementId, bool isLocked);

    function terminateAgreementEarly(uint256 _agreementId) external nonReentrant whenNotPaused agreementExists(_agreementId) onlyTenant(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.isActive, "Agreement is already inactive");

        uint256 fee = agreement.earlyTerminationFee;
        require(userEscrowBalance[msg.sender] >= fee, "Insufficient escrow balance");

        userEscrowBalance[msg.sender] -= fee;
        totalPlatformFees += fee;
        agreement.isActive = false;
        agreement.agreementEnd = block.timestamp;

        emit AgreementTerminated(_agreementId, msg.sender, block.timestamp);
    }

    function toggleAutoRenewal(uint256 _agreementId, bool _status) external nonReentrant whenNotPaused agreementExists(_agreementId) onlyAgreementParties(_agreementId) {
        agreements[_agreementId].autoRenewal = _status;
        emit AutoPaymentSetup(_agreementId, msg.sender, _status);
    }

    function uploadKYC(string calldata _kycHash) external {
        require(bytes(_kycHash).length > 0, "Invalid hash");
        userKYCHash[msg.sender] = _kycHash;
        emit UserVerified(msg.sender, 0);
    }

    function assignMaintenanceToContractor(uint256 _requestId, address _contractor) external nonReentrant whenNotPaused {
        MaintenanceRequest storage request = maintenanceRequests[_requestId];
        require(agreements[request.agreementId].landlord == msg.sender, "Not landlord");
        require(verifiedContractors[_contractor], "Contractor not verified");
        require(request.isApproved, "Request not approved");

        request.assignedContractor = _contractor;
    }

    function submitContractorSkills(string[] calldata _skills) external {
        require(_skills.length > 0, "No skills submitted");
        contractorSkills[msg.sender] = _skills;
        verifiedContractors[msg.sender] = true;
        emit ContractorVerified(msg.sender, _skills);
    }

    function payRent(uint256 _agreementId) external payable nonReentrant whenNotPaused agreementExists(_agreementId) onlyTenant(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.isActive, "Inactive agreement");

        uint256 dueDate = agreement.lastRentPayment + SECONDS_IN_MONTH;
        uint256 amountDue = agreement.monthlyRent;
        uint256 lateFee = 0;

        if (block.timestamp > dueDate + (agreement.gracePeriodDays * 1 days)) {
            lateFee = (amountDue * LATE_FEE_PERCENTAGE) / 100;
            uint256 maxLate = (amountDue * MAX_LATE_FEE_MULTIPLIER) / 100;
            if (lateFee > maxLate) lateFee = maxLate;
        }

        require(msg.value >= amountDue + lateFee, "Insufficient payment");

        payable(agreement.landlord).transfer(amountDue);
        totalPlatformFees += (msg.value * PLATFORM_FEE_PERCENTAGE) / 100;

        agreement.lastRentPayment = block.timestamp;
        agreement.totalRentPaid += amountDue;
        agreement.lateFeesOwed = lateFee;

        emit RentPaid(_agreementId, msg.sender, amountDue, lateFee, block.timestamp);
    }

    function requestDocumentAccess(uint256 _agreementId, string calldata _documentType) external {
        emit DocumentAccessRequested(_agreementId, msg.sender, _documentType);
    }

    function renewAgreement(uint256 _agreementId, uint256 _days) external nonReentrant whenNotPaused agreementExists(_agreementId) onlyAgreementParties(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.isActive, "Agreement is not active");
        agreement.agreementEnd += _days * 1 days;
        emit AgreementRenewed(_agreementId, msg.sender, agreement.agreementEnd);
    }

    function proposeRentChange(uint256 _agreementId, uint256 _newRent) external nonReentrant whenNotPaused agreementExists(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(msg.sender == agreement.landlord, "Only landlord can propose");
        require(_newRent > 0, "Invalid rent amount");
        pendingRentChanges[_agreementId] = _newRent;
        emit RentChangeProposed(_agreementId, msg.sender, _newRent);
    }

    function raiseEmergencyMaintenance(uint256 _agreementId, string calldata _desc) external nonReentrant whenNotPaused agreementExists(_agreementId) onlyTenant(_agreementId) {
        emergencyRequests.push(EmergencyMaintenance({
            agreementId: _agreementId,
            raisedBy: msg.sender,
            description: _desc,
            timestamp: block.timestamp,
            resolved: false
        }));
        emit EmergencyMaintenanceRaised(emergencyRequests.length - 1, _agreementId, msg.sender, _desc);
    }

    function rateContractor(address _contractor, uint8 _rating) external {
        require(_rating >= 1 && _rating <= 5, "Rating should be 1 to 5");
        require(verifiedContractors[_contractor], "Contractor not verified");
        contractorRatings[_contractor].push(_rating);
        emit ContractorRated(_contractor, _rating);
    }

    function setAgreementLock(uint256 _agreementId, bool _lock) external onlyAdmin {
        agreementLocked[_agreementId] = _lock;
        emit AgreementLocked(_agreementId, _lock);
    }

    MaintenanceRequest[] public maintenanceRequests;
}
