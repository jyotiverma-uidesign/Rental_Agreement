// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Import OpenZeppelin contracts for security and access control
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";


contract RentalAgreement is ReentrancyGuard, Ownable, Pausable {
    // Struct representing a rental agreement
    struct Agreement {
        address landlord;
        address tenant;
        uint256 monthlyRent;
        uint256 securityDeposit;
        uint256 agreementStart;
        uint256 agreementEnd;
        bool isActive;
        bool depositPaid;
        uint256 lastRentPayment;
        string propertyAddress;
        uint256 lateFeesOwed;
        uint256 maintenanceReserve;
        bool autoRenewal;
        uint256 renewalDuration;
        uint256 totalRentPaid;
        uint256 utilitiesDeposit;
        bool utilitiesIncluded;
        uint256 petDeposit;
        bool petsAllowed;
        uint256 earlyTerminationFee;
        string[] amenities;
        uint256 gracePeriodDays;
    }

    // Struct for maintenance requests
    struct MaintenanceRequest {
        uint256 agreementId;
        address requester;
        string description;
        uint256 estimatedCost;
        bool isApproved;
        bool isCompleted;
        uint256 actualCost;
        uint256 timestamp;
        bool isUrgent;
        string[] imageHashes;
        address assignedContractor;
    }

    // Struct for reviews by users
    struct Review {
        address reviewer;
        address reviewee;
        uint256 rating;
        string comment;
        uint256 timestamp;
        bool isLandlordReview;
    }

    // Struct for property inspections
    struct Inspection {
        uint256 agreementId;
        address inspector;
        string inspectionType;
        string reportHash;
        uint256 timestamp;
        bool tenantAcknowledged;
        string[] issuesFound;
        uint256[] estimatedRepairCosts;
    }

    // Struct for rent payment plans
    struct PaymentPlan {
        uint256 agreementId;
        uint256 totalAmount;
        uint256 installments;
        uint256 paidInstallments;
        uint256 installmentAmount;
        uint256 nextPaymentDue;
        bool isActive;
        string reason;
    }

    // Struct for proposing a rent increase
    struct RentIncrease {
        uint256 agreementId;
        uint256 newRent;
        uint256 effectiveDate;
        uint256 noticeDate;
        bool tenantAccepted;
        string reason;
        uint256 currentRent;
    }

    // Struct for documents (e.g., lease agreements, reports)
    struct Document {
        string documentHash;
        string documentType;
        uint256 timestamp;
        address uploader;
        bool isPublic;
    }

    // Struct for emergency contacts
    struct EmergencyContact {
        string name;
        string phoneNumber;
        string relationship;
        address walletAddress;
    }

    // Mappings for storing data related to agreements, reviews, maintenance, etc.
    mapping(uint256 => Agreement) public agreements;
    mapping(address => uint256[]) public landlordAgreements;
    mapping(address => uint256[]) public tenantAgreements;
    mapping(uint256 => MaintenanceRequest) public maintenanceRequests;
    mapping(address => Review[]) public userReviews;
    mapping(address => uint256) public userRatings;
    mapping(address => uint256) public userReviewCount;
    mapping(uint256 => uint256[]) public agreementMaintenanceRequests;
    mapping(address => bool) public verifiedUsers;
    mapping(address => uint256) public userSecurityScores;

    mapping(uint256 => Inspection[]) public agreementInspections;
    mapping(uint256 => PaymentPlan[]) public agreementPaymentPlans;
    mapping(uint256 => RentIncrease[]) public agreementRentIncreases;
    mapping(uint256 => Document[]) public agreementDocuments;
    mapping(address => EmergencyContact[]) public userEmergencyContacts;
    mapping(address => bool) public verifiedContractors;
    mapping(address => string[]) public contractorSkills;
    mapping(uint256 => uint256) public inspectionCounter;
    mapping(uint256 => uint256) public paymentPlanCounter;
    mapping(uint256 => uint256) public rentIncreaseCounter;
    mapping(uint256 => bool) public agreementInsured;
    mapping(address => uint256) public userEscrowBalance;
    mapping(uint256 => uint256) public agreementUtilityUsage;
    mapping(address => string) public userKYCHash;

    // Global counters
    uint256 public agreementCounter;
    uint256 public maintenanceRequestCounter;
    uint256 public globalInspectionCounter;
    uint256 public globalPaymentPlanCounter;
    uint256 public globalRentIncreaseCounter;

    // Constants for fees and rules
    uint256 public constant LATE_FEE_PERCENTAGE = 5;
    uint256 public constant SECONDS_IN_MONTH = 30 days;
    uint256 public constant MAINTENANCE_RESERVE_PERCENTAGE = 2;
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 1;
    uint256 public constant MAX_LATE_FEE_MULTIPLIER = 3;
    uint256 public constant RENT_INCREASE_NOTICE_DAYS = 30;
    uint256 public constant MAX_RENT_INCREASE_PERCENTAGE = 20;
    uint256 public constant INSPECTION_REMINDER_DAYS = 7;

    uint256 public totalPlatformFees;

    // Events emitted for various actions
    event InspectionScheduled(uint256 indexed agreementId, uint256 indexed inspectionId, string inspectionType, uint256 scheduledDate);
    event InspectionCompleted(uint256 indexed agreementId, uint256 indexed inspectionId, string[] issues);
    event PaymentPlanCreated(uint256 indexed agreementId, uint256 indexed planId, uint256 totalAmount, uint256 installments);
    event PaymentPlanInstallmentPaid(uint256 indexed agreementId, uint256 indexed planId, uint256 installmentNumber, uint256 amount);
    event RentIncreaseProposed(uint256 indexed agreementId, uint256 indexed increaseId, uint256 oldRent, uint256 newRent, uint256 effectiveDate);
    event RentIncreaseAccepted(uint256 indexed agreementId, uint256 indexed increaseId);
    event DocumentUploaded(uint256 indexed agreementId, string documentType, string documentHash);
    event EmergencyContactAdded(address indexed user, string name, string phoneNumber);
    event ContractorVerified(address indexed contractor, string[] skills);
    event InsuranceClaimed(uint256 indexed agreementId, uint256 claimAmount, string reason);
    event EscrowDeposit(address indexed user, uint256 amount);
    event EscrowWithdraw(address indexed user, uint256 amount);
    event UtilityUsageRecorded(uint256 indexed agreementId, uint256 usage, uint256 cost);
    event AutoPaymentSetup(uint256 indexed agreementId, address indexed tenant, bool enabled);

    event AgreementCreated(uint256 indexed agreementId, address indexed landlord, address indexed tenant, uint256 monthlyRent, uint256 securityDeposit, string propertyAddress);
    event RentPaid(uint256 indexed agreementId, address indexed tenant, uint256 amount, uint256 lateFee, uint256 timestamp);
    event AgreementTerminated(uint256 indexed agreementId, address indexed initiator, uint256 timestamp);
    event DepositReturned(uint256 indexed agreementId, address indexed tenant, uint256 amount);
    event MaintenanceRequestCreated(uint256 indexed requestId, uint256 indexed agreementId, address indexed requester, string description, uint256 estimatedCost, bool isUrgent);
    event MaintenanceRequestApproved(uint256 indexed requestId, uint256 approvedCost);
    event MaintenanceRequestCompleted(uint256 indexed requestId, uint256 actualCost);
    event ReviewSubmitted(address indexed reviewer, address indexed reviewee, uint256 rating, string comment, bool isLandlordReview);
    event AgreementRenewed(uint256 indexed agreementId, uint256 newEndDate, uint256 newRent);
    event UserVerified(address indexed user, uint256 securityScore);

    // Modifiers to restrict access
    modifier onlyLandlord(uint256 _agreementId) {
        require(agreements[_agreementId].landlord == msg.sender, "Only landlord can perform this action");
        _;
    }

    modifier onlyTenant(uint256 _agreementId) {
        require(agreements[_agreementId].tenant == msg.sender, "Only tenant can perform this action");
        _;
    }

    modifier agreementExists(uint256 _agreementId) {
        require(_agreementId < agreementCounter, "Agreement does not exist");
        _;
    }

    modifier onlyAgreementParties(uint256 _agreementId) {
        require(
            agreements[_agreementId].landlord == msg.sender || 
            agreements[_agreementId].tenant == msg.sender,
            "Only agreement parties can perform this action"
        );
        _;
    }

    modifier onlyVerifiedContractor() {
        require(verifiedContractors[msg.sender], "Only verified contractors can perform this action");
        _;
    }

    // Constructor sets the contract deployer as the owner
    constructor() Ownable(msg.sender) {}

    /// @notice Creates a new rental agreement with extended features
    function createAgreementEnhanced(
        address _tenant,
        uint256 _monthlyRent,
        uint256 _securityDeposit,
        uint256 _durationInMonths,
        string memory _propertyAddress,
        bool _autoRenewal,
        uint256 _renewalDuration,
        uint256 _utilitiesDeposit,
        bool _utilitiesIncluded,
        uint256 _petDeposit,
        bool _petsAllowed,
        uint256 _earlyTerminationFee,
        string[] memory _amenities,
        uint256 _gracePeriodDays
    ) external nonReentrant whenNotPaused {
        require(_tenant != address(0), "Invalid tenant address");
        require(_tenant != msg.sender, "Landlord cannot be tenant");
        require(_monthlyRent > 0, "Monthly rent must be greater than 0");
        require(_securityDeposit > 0, "Security deposit must be greater than 0");
        require(_durationInMonths > 0, "Duration must be greater than 0");
        require(bytes(_propertyAddress).length > 0, "Property address required");
        require(_gracePeriodDays <= 10, "Grace period cannot exceed 10 days");

        uint256 agreementId = agreementCounter++;
        uint256 maintenanceReserve = (_monthlyRent * MAINTENANCE_RESERVE_PERCENTAGE) / 100;

        // Create and initialize the agreement
        Agreement storage agreement = agreements[agreementId];
        agreement.landlord = msg.sender;
        agreement.tenant = _tenant;
        agreement.monthlyRent = _monthlyRent;
        agreement.securityDeposit = _securityDeposit;
        agreement.agreementStart = block.timestamp;
        agreement.agreementEnd = block.timestamp + (_durationInMonths * SECONDS_IN_MONTH);
        agreement.isActive = true;
        agreement.depositPaid = false;
        agreement.lastRentPayment = 0;
        agreement.propertyAddress = _propertyAddress;
        agreement.lateFeesOwed = 0;
        agreement.maintenanceReserve = maintenanceReserve;
        agreement.autoRenewal = _autoRenewal;
        agreement.renewalDuration = _renewalDuration;
        agreement.totalRentPaid = 0;
        agreement.utilitiesDeposit = _utilitiesDeposit;
        agreement.utilitiesIncluded = _utilitiesIncluded;
        agreement.petDeposit = _petDeposit;
        agreement.petsAllowed = _petsAllowed;
        agreement.earlyTerminationFee = _earlyTerminationFee;
        agreement.amenities = _amenities;
        agreement.gracePeriodDays = _gracePeriodDays;

        // Track agreement IDs for landlord and tenant
        landlordAgreements[msg.sender].push(agreementId);
        tenantAgreements[_tenant].push(agreementId);

        emit AgreementCreated(agreementId, msg.sender, _tenant, _monthlyRent, _securityDeposit, _propertyAddress);
    }

    /// @notice Schedule a property inspection by the landlord
    function scheduleInspection(
        uint256 _agreementId,
        string memory _inspectionType,
        string[] memory _issuesFound,
        uint256[] memory _estimatedRepairCosts,
        string memory _reportHash
    ) external nonReentrant whenNotPaused agreementExists(_agreementId) onlyLandlord(_agreementId) {
        require(agreements[_agreementId].isActive, "Agreement is not active");
        require(bytes(_inspectionType).length > 0, "Inspection type required");
        require(_issuesFound.length == _estimatedRepairCosts.length, "Issues and costs arrays must match");

        uint256 inspectionId = globalInspectionCounter++;

        // Create a new inspection record
        Inspection memory newInspection = Inspection({
            agreementId: _agreementId,
            inspector: msg.sender,
            inspectionType: _inspectionType,
            reportHash: _reportHash,
            timestamp: block.timestamp,
            tenantAcknowledged: false,
            issuesFound: _issuesFound,
            estimatedRepairCosts: _estimatedRepairCosts
        });

        agreementInspections[_agreementId].push(newInspection);
        inspectionCounter[_agreementId]++;

        emit InspectionScheduled(_agreementId, inspectionId, _inspectionType, block.timestamp);
        emit InspectionCompleted(_agreementId, inspectionId, _issuesFound);
    }

    /// @notice Tenant acknowledges the completion of an inspection
    function acknowledgeInspection(uint256 _agreementId, uint256 _inspectionIndex) 
        external 
        nonReentrant 
        whenNotPaused 
        agreementExists(_agreementId) 
        onlyTenant(_agreementId) 
    {
        require(_inspectionIndex < agreementInspections[_agreementId].length, "Invalid inspection index");

        // Mark tenant acknowledgment
        agreementInspections[_agreementId][_inspectionIndex].tenantAcknowledged = true;
    }
}
