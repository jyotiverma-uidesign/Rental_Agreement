// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract RentalAgreement is ReentrancyGuard, Ownable, Pausable {
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
        uint256 utilityDeposit;
        bool utilitiesIncluded;
        uint256 petDeposit;
        bool petsAllowed;
        uint256 earlyTerminationFee;
        uint256 gracePeriodDays; // Grace period before late fees apply
    }

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
        string category; // e.g., "plumbing", "electrical", "general"
        address assignedContractor;
        uint256 dueDate;
    }

    struct Review {
        address reviewer;
        address reviewee;
        uint256 rating; // 1-5 stars
        string comment;
        uint256 timestamp;
        bool isLandlordReview; // true if landlord reviewing tenant
    }

    // NEW: Rent payment history for better tracking
    struct RentPayment {
        uint256 amount;
        uint256 lateFee;
        uint256 timestamp;
        uint256 month;
        uint256 year;
        bool isPartial;
    }

    // NEW: Property inspection records
    struct Inspection {
        uint256 agreementId;
        address inspector;
        string inspectionType; // "move-in", "move-out", "routine", "maintenance"
        string notes;
        string[] photoHashes; // IPFS hashes for inspection photos
        uint256 timestamp;
        bool tenantPresent;
        bool landlordPresent;
        uint256 overallCondition; // 1-5 rating
    }

    // NEW: Dispute management
    struct Dispute {
        uint256 agreementId;
        address complainant;
        address defendant;
        string disputeType; // "rent", "maintenance", "deposit", "damage", "other"
        string description;
        uint256 timestamp;
        DisputeStatus status;
        address mediator;
        string resolution;
        uint256 resolutionTimestamp;
        uint256 compensationAmount;
    }

    enum DisputeStatus {
        Open,
        UnderReview,
        Mediation,
        Resolved,
        Closed
    }

    // NEW: Property details
    struct PropertyDetails {
        string propertyType; // "apartment", "house", "condo", etc.
        uint256 bedrooms;
        uint256 bathrooms;
        uint256 squareFeet;
        string[] amenities;
        bool furnished;
        uint256 yearBuilt;
        string parkingSpaces;
    }

    // NEW: Notification system
    struct Notification {
        address recipient;
        string message;
        uint256 timestamp;
        bool isRead;
        string notificationType; // "rent_due", "maintenance", "inspection", "dispute", etc.
        uint256 relatedId; // ID of related agreement, request, etc.
    }

    mapping(uint256 => Agreement) public agreements;
    mapping(address => uint256[]) public landlordAgreements;
    mapping(address => uint256[]) public tenantAgreements;
    mapping(uint256 => MaintenanceRequest) public maintenanceRequests;
    mapping(address => Review[]) public userReviews;
    mapping(address => uint256) public userRatings; // Average rating * 100
    mapping(address => uint256) public userReviewCount;
    mapping(uint256 => uint256[]) public agreementMaintenanceRequests;
    
    // NEW: Additional mappings
    mapping(uint256 => RentPayment[]) public rentPaymentHistory;
    mapping(uint256 => Inspection[]) public propertyInspections;
    mapping(uint256 => Dispute) public disputes;
    mapping(uint256 => PropertyDetails) public propertyDetails;
    mapping(address => Notification[]) public userNotifications;
    mapping(address => uint256) public unreadNotificationCount;
    mapping(uint256 => address[]) public agreementWaitlist; // For property waitlists
    mapping(address => bool) public approvedContractors;
    mapping(address => uint256) public contractorRatings;
    mapping(uint256 => uint256[]) public agreementDisputes;
    mapping(address => uint256) public userKYCLevel; // 0 = none, 1 = basic, 2 = full
    
    uint256 public agreementCounter;
    uint256 public maintenanceRequestCounter;
    uint256 public inspectionCounter;
    uint256 public disputeCounter;
    uint256 public notificationCounter;
    
    uint256 public constant LATE_FEE_PERCENTAGE = 5; // 5% late fee
    uint256 public constant SECONDS_IN_MONTH = 30 days;
    uint256 public constant MAINTENANCE_RESERVE_PERCENTAGE = 2; // 2% of monthly rent
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 1; // 1% platform fee
    uint256 public constant MAX_LATE_FEE_MULTIPLIER = 3; // Max 3x late fees
    
    // NEW: Additional constants
    uint256 public constant EARLY_TERMINATION_PENALTY = 200; // 2 months rent equivalent
    uint256 public constant INSPECTION_REQUIRED_DAYS = 7; // Days before move-in/out for inspection
    uint256 public constant DISPUTE_RESOLUTION_DAYS = 30; // Days to resolve dispute
    
    // State variables
    uint256 public totalPlatformFees;
    mapping(address => bool) public verifiedUsers;
    mapping(address => uint256) public userSecurityScores;
    
    // NEW: Additional state variables
    address public disputeMediator;
    mapping(address => bool) public authorizedInspectors;
    uint256 public minimumRentAmount;
    uint256 public maximumLateDays;
    bool public autoNotificationsEnabled;

    // Events
    event AgreementCreated(
        uint256 indexed agreementId,
        address indexed landlord,
        address indexed tenant,
        uint256 monthlyRent,
        uint256 securityDeposit,
        string propertyAddress
    );

    event RentPaid(
        uint256 indexed agreementId,
        address indexed tenant,
        uint256 amount,
        uint256 lateFee,
        uint256 timestamp
    );

    event AgreementTerminated(
        uint256 indexed agreementId,
        address indexed initiator,
        uint256 timestamp
    );

    event DepositReturned(
        uint256 indexed agreementId,
        address indexed tenant,
        uint256 amount
    );

    event MaintenanceRequestCreated(
        uint256 indexed requestId,
        uint256 indexed agreementId,
        address indexed requester,
        string description,
        uint256 estimatedCost,
        bool isUrgent
    );

    event MaintenanceRequestApproved(
        uint256 indexed requestId,
        uint256 approvedCost
    );

    event MaintenanceRequestCompleted(
        uint256 indexed requestId,
        uint256 actualCost
    );

    event ReviewSubmitted(
        address indexed reviewer,
        address indexed reviewee,
        uint256 rating,
        string comment,
        bool isLandlordReview
    );

    event AgreementRenewed(
        uint256 indexed agreementId,
        uint256 newEndDate,
        uint256 newRent
    );

    event UserVerified(
        address indexed user,
        uint256 securityScore
    );

    // NEW: Additional events
    event InspectionScheduled(
        uint256 indexed inspectionId,
        uint256 indexed agreementId,
        address indexed inspector,
        string inspectionType,
        uint256 timestamp
    );

    event InspectionCompleted(
        uint256 indexed inspectionId,
        uint256 overallCondition,
        uint256 timestamp
    );

    event DisputeCreated(
        uint256 indexed disputeId,
        uint256 indexed agreementId,
        address indexed complainant,
        string disputeType
    );

    event DisputeResolved(
        uint256 indexed disputeId,
        uint256 compensationAmount,
        uint256 timestamp
    );

    event NotificationSent(
        address indexed recipient,
        string message,
        string notificationType,
        uint256 relatedId
    );

    event PropertyDetailsSet(
        uint256 indexed agreementId,
        string propertyType,
        uint256 bedrooms,
        uint256 bathrooms
    );

    event ContractorAssigned(
        uint256 indexed requestId,
        address indexed contractor
    );

    event WaitlistJoined(
        uint256 indexed agreementId,
        address indexed user
    );

    event RentReminderSent(
        uint256 indexed agreementId,
        address indexed tenant,
        uint256 dueDate
    );

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

    modifier onlyAuthorizedInspector() {
        require(authorizedInspectors[msg.sender] || msg.sender == owner(), "Not authorized inspector");
        _;
    }

    modifier onlyMediator() {
        require(msg.sender == disputeMediator || msg.sender == owner(), "Not authorized mediator");
        _;
    }

    constructor() Ownable(msg.sender) {
        disputeMediator = msg.sender;
        minimumRentAmount = 0.01 ether; // Minimum rent amount
        maximumLateDays = 90; // Maximum late days before automatic termination
        autoNotificationsEnabled = true;
    }

    /**
     * @dev Creates a new rental agreement with enhanced features
     */
    function createAgreement(
        address _tenant,
        uint256 _monthlyRent,
        uint256 _securityDeposit,
        uint256 _durationInMonths,
        string memory _propertyAddress,
        bool _autoRenewal,
        uint256 _renewalDuration,
        uint256 _utilityDeposit,
        bool _utilitiesIncluded,
        uint256 _petDeposit,
        bool _petsAllowed,
        uint256 _gracePeriodDays
    ) external nonReentrant whenNotPaused {
        require(_tenant != address(0), "Invalid tenant address");
        require(_tenant != msg.sender, "Landlord cannot be tenant");
        require(_monthlyRent >= minimumRentAmount, "Monthly rent below minimum");
        require(_securityDeposit > 0, "Security deposit must be greater than 0");
        require(_durationInMonths > 0, "Duration must be greater than 0");
        require(bytes(_propertyAddress).length > 0, "Property address required");
        require(_gracePeriodDays <= 10, "Grace period too long");

        uint256 agreementId = agreementCounter++;
        uint256 maintenanceReserve = (_monthlyRent * MAINTENANCE_RESERVE_PERCENTAGE) / 100;
        
        agreements[agreementId] = Agreement({
            landlord: msg.sender,
            tenant: _tenant,
            monthlyRent: _monthlyRent,
            securityDeposit: _securityDeposit,
            agreementStart: block.timestamp,
            agreementEnd: block.timestamp + (_durationInMonths * SECONDS_IN_MONTH),
            isActive: true,
            depositPaid: false,
            lastRentPayment: 0,
            propertyAddress: _propertyAddress,
            lateFeesOwed: 0,
            maintenanceReserve: maintenanceReserve,
            autoRenewal: _autoRenewal,
            renewalDuration: _renewalDuration,
            totalRentPaid: 0,
            utilityDeposit: _utilityDeposit,
            utilitiesIncluded: _utilitiesIncluded,
            petDeposit: _petDeposit,
            petsAllowed: _petsAllowed,
            earlyTerminationFee: (_monthlyRent * EARLY_TERMINATION_PENALTY) / 100,
            gracePeriodDays: _gracePeriodDays
        });

        landlordAgreements[msg.sender].push(agreementId);
        tenantAgreements[_tenant].push(agreementId);

        // Send welcome notifications
        if (autoNotificationsEnabled) {
            _sendNotification(_tenant, "Welcome! Your rental agreement has been created.", "agreement_created", agreementId);
            _sendNotification(msg.sender, "New rental agreement created successfully.", "agreement_created", agreementId);
        }

        emit AgreementCreated(agreementId, msg.sender, _tenant, _monthlyRent, _securityDeposit, _propertyAddress);
    }

    /**
     * @dev Enhanced rent payment with automatic calculations and payment history
     */
    function payRent(uint256 _agreementId) external payable nonReentrant whenNotPaused agreementExists(_agreementId) onlyTenant(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.isActive, "Agreement is not active");
        require(block.timestamp <= agreement.agreementEnd, "Agreement has expired");

        uint256 expectedAmount = agreement.monthlyRent;
        uint256 lateFee = 0;
        
        // If deposit not paid, add deposit to expected amount
        if (!agreement.depositPaid) {
            expectedAmount += agreement.securityDeposit;
            if (agreement.utilityDeposit > 0) {
                expectedAmount += agreement.utilityDeposit;
            }
            if (agreement.petDeposit > 0) {
                expectedAmount += agreement.petDeposit;
            }
        }

        // Add maintenance reserve
        expectedAmount += agreement.maintenanceReserve;

        // Calculate late fees with grace period
        uint256 timeSinceLastPayment = agreement.lastRentPayment == 0 
            ? block.timestamp - agreement.agreementStart 
            : block.timestamp - agreement.lastRentPayment;

        uint256 gracePeriodSeconds = agreement.gracePeriodDays * 1 days;
        
        if (timeSinceLastPayment > (SECONDS_IN_MONTH + gracePeriodSeconds) && agreement.lastRentPayment != 0) {
            // Progressive late fee calculation
            uint256 daysLate = (timeSinceLastPayment - SECONDS_IN_MONTH - gracePeriodSeconds) / 1 days;
            lateFee = (agreement.monthlyRent * LATE_FEE_PERCENTAGE * daysLate) / (100 * 30);
            
            // Cap late fees
            uint256 maxLateFee = (agreement.monthlyRent * LATE_FEE_PERCENTAGE * MAX_LATE_FEE_MULTIPLIER) / 100;
            if (lateFee > maxLateFee) {
                lateFee = maxLateFee;
            }
            
            expectedAmount += lateFee;
        }

        // Add any outstanding late fees
        expectedAmount += agreement.lateFeesOwed;

        bool isPartialPayment = msg.value < expectedAmount && msg.value >= (expectedAmount * 50) / 100; // Allow partial payments >= 50%
        
        if (!isPartialPayment) {
            require(msg.value >= expectedAmount, "Insufficient payment amount");
        }

        // Mark deposit as paid if this is the first payment
        if (!agreement.depositPaid) {
            agreement.depositPaid = true;
        }

        agreement.lastRentPayment = block.timestamp;
        
        if (isPartialPayment) {
            agreement.lateFeesOwed = expectedAmount - msg.value;
        } else {
            agreement.lateFeesOwed = 0; // Clear outstanding late fees
        }
        
        agreement.totalRentPaid += (msg.value > agreement.monthlyRent ? agreement.monthlyRent : msg.value);

        // Record payment history
        uint256 currentMonth = (block.timestamp / SECONDS_IN_MONTH) % 12 + 1;
        uint256 currentYear = 1970 + (block.timestamp / (365 * 24 * 60 * 60));
        
        rentPaymentHistory[_agreementId].push(RentPayment({
            amount: msg.value,
            lateFee: lateFee,
            timestamp: block.timestamp,
            month: currentMonth,
            year: currentYear,
            isPartial: isPartialPayment
        }));

        // Calculate platform fee
        uint256 rentPortion = msg.value > agreement.monthlyRent ? agreement.monthlyRent : msg.value;
        uint256 platformFee = (rentPortion * PLATFORM_FEE_PERCENTAGE) / 100;
        totalPlatformFees += platformFee;

        // Transfer amounts
        uint256 landlordAmount = msg.value - platformFee;
        (bool success, ) = agreement.landlord.call{value: landlordAmount}("");
        require(success, "Transfer to landlord failed");

        // Send notifications
        if (autoNotificationsEnabled) {
            string memory message = isPartialPayment ? "Partial rent payment received." : "Rent payment received successfully.";
            _sendNotification(agreement.landlord, message, "rent_paid", _agreementId);
        }

        emit RentPaid(_agreementId, msg.sender, rentPortion, lateFee, block.timestamp);
    }

    /**
     * @dev NEW: Set property details
     */
    function setPropertyDetails(
        uint256 _agreementId,
        string memory _propertyType,
        uint256 _bedrooms,
        uint256 _bathrooms,
        uint256 _squareFeet,
        string[] memory _amenities,
        bool _furnished,
        uint256 _yearBuilt,
        string memory _parkingSpaces
    ) external agreementExists(_agreementId) onlyLandlord(_agreementId) {
        propertyDetails[_agreementId] = PropertyDetails({
            propertyType: _propertyType,
            bedrooms: _bedrooms,
            bathrooms: _bathrooms,
            squareFeet: _squareFeet,
            amenities: _amenities,
            furnished: _furnished,
            yearBuilt: _yearBuilt,
            parkingSpaces: _parkingSpaces
        });

        emit PropertyDetailsSet(_agreementId, _propertyType, _bedrooms, _bathrooms);
    }

    /**
     * @dev NEW: Schedule property inspection
     */
    function scheduleInspection(
        uint256 _agreementId,
        string memory _inspectionType,
        bool _tenantPresent,
        bool _landlordPresent
    ) external nonReentrant whenNotPaused agreementExists(_agreementId) onlyAuthorizedInspector {
        require(bytes(_inspectionType).length > 0, "Inspection type required");

        uint256 inspectionId = inspectionCounter++;
        
        Inspection memory newInspection = Inspection({
            agreementId: _agreementId,
            inspector: msg.sender,
            inspectionType: _inspectionType,
            notes: "",
            photoHashes: new string[](0),
            timestamp: block.timestamp,
            tenantPresent: _tenantPresent,
            landlordPresent: _landlordPresent,
            overallCondition: 0
        });

        propertyInspections[_agreementId].push(newInspection);

        // Send notifications to parties
        if (autoNotificationsEnabled) {
            Agreement memory agreement = agreements[_agreementId];
            _sendNotification(agreement.landlord, "Property inspection scheduled.", "inspection_scheduled", inspectionId);
            _sendNotification(agreement.tenant, "Property inspection scheduled.", "inspection_scheduled", inspectionId);
        }

        emit InspectionScheduled(inspectionId, _agreementId, msg.sender, _inspectionType, block.timestamp);
    }

    /**
     * @dev NEW: Complete inspection with notes and condition rating
     */
    function completeInspection(
        uint256 _agreementId,
        uint256 _inspectionIndex,
        string memory _notes,
        string[] memory _photoHashes,
        uint256 _overallCondition
    ) external nonReentrant whenNotPaused agreementExists(_agreementId) onlyAuthorizedInspector {
        require(_inspectionIndex < propertyInspections[_agreementId].length, "Invalid inspection index");
        require(_overallCondition >= 1 && _overallCondition <= 5, "Condition rating must be 1-5");

        Inspection storage inspection = propertyInspections[_agreementId][_inspectionIndex];
        require(inspection.inspector == msg.sender, "Only assigned inspector can complete");
        require(bytes(inspection.notes).length == 0, "Inspection already completed");

        inspection.notes = _notes;
        inspection.photoHashes = _photoHashes;
        inspection.overallCondition = _overallCondition;

        emit InspectionCompleted(_inspectionIndex, _overallCondition, block.timestamp);
    }

    /**
     * @dev NEW: Create dispute
     */
    function createDispute(
        uint256 _agreementId,
        string memory _disputeType,
        string memory _description
    ) external nonReentrant whenNotPaused agreementExists(_agreementId) onlyAgreementParties(_agreementId) {
        require(bytes(_disputeType).length > 0, "Dispute type required");
        require(bytes(_description).length > 0, "Description required");

        uint256 disputeId = disputeCounter++;
        Agreement memory agreement = agreements[_agreementId];
        
        address defendant = msg.sender == agreement.landlord ? agreement.tenant : agreement.landlord;
        
        disputes[disputeId] = Dispute({
            agreementId: _agreementId,
            complainant: msg.sender,
            defendant: defendant,
            disputeType: _disputeType,
            description: _description,
            timestamp: block.timestamp,
            status: DisputeStatus.Open,
            mediator: address(0),
            resolution: "",
            resolutionTimestamp: 0,
            compensationAmount: 0
        });

        agreementDisputes[_agreementId].push(disputeId);

        // Notify defendant
        if (autoNotificationsEnabled) {
            _sendNotification(defendant, "A dispute has been filed against you.", "dispute_created", disputeId);
        }

        emit DisputeCreated(disputeId, _agreementId, msg.sender, _disputeType);
    }

    /**
     * @dev NEW: Resolve dispute (mediator only)
     */
    function resolveDispute(
        uint256 _disputeId,
        string memory _resolution,
        uint256 _compensationAmount
    ) external payable nonReentrant whenNotPaused onlyMediator {
        Dispute storage dispute = disputes[_disputeId];
        require(dispute.status == DisputeStatus.Open || dispute.status == DisputeStatus.Mediation, "Dispute not open for resolution");
        
        dispute.status = DisputeStatus.Resolved;
        dispute.resolution = _resolution;
        dispute.resolutionTimestamp = block.timestamp;
        dispute.compensationAmount = _compensationAmount;
        dispute.mediator = msg.sender;

        // Handle compensation if required
        if (_compensationAmount > 0) {
            require(msg.value >= _compensationAmount, "Insufficient compensation amount");
            (bool success, ) = dispute.complainant.call{value: _compensationAmount}("");
            require(success, "Compensation transfer failed");
        }

        // Send notifications
        if (autoNotificationsEnabled) {
            _sendNotification(dispute.complainant, "Your dispute has been resolved.", "dispute_resolved", _disputeId);
            _sendNotification(dispute.defendant, "The dispute against you has been resolved.", "dispute_resolved", _disputeId);
        }

        emit DisputeResolved(_disputeId, _compensationAmount, block.timestamp);
    }

    /**
     * @dev NEW: Join property waitlist
     */
    function joinWaitlist(uint256 _agreementId) external nonReentrant whenNotPaused agreementExists(_agreementId) {
        require(msg.sender != agreements[_agreementId].landlord, "Landlord cannot join waitlist");
        require(msg.sender != agreements[_agreementId].tenant, "Current tenant cannot join waitlist");
        
        // Check if already on waitlist
        address[] storage waitlist = agreementWaitlist[_agreementId];
        for (uint256 i = 0; i < waitlist.length; i++) {
            require(waitlist[i] != msg.sender, "Already on waitlist");
        }
        
        waitlist.push(msg.sender);
        
        emit WaitlistJoined(_agreementId, msg.sender);
    }

    /**
     * @dev Enhanced maintenance request with contractor assignment
     */
    function createMaintenanceRequest(
        uint256 _agreementId,
        string memory _description,
        uint256 _estimatedCost,
        bool _isUrgent,
        string memory _category
    ) external nonReentrant whenNotPaused agreementExists(_agreementId) onlyAgreementParties(_agreementId) {
        require(agreements[_agreementId].isActive, "Agreement is not active");
        require(bytes(_description).length > 0, "Description required");
        require(_estimatedCost > 0, "Estimated cost must be greater than 0");
        require(bytes(_category).length > 0, "Category required");

        uint256 requestId = maintenanceRequestCounter++;
        uint256 dueDate = _isUrgent ? block.timestamp + 1 days : block.timestamp + 7 days;
        
        maintenanceRequests[requestId] = MaintenanceRequest({
            agreementId: _agreementId,
            requester: msg.sender,
            description: _description,
            estimatedCost: _estimatedCost,
            isApproved: false,
            isCompleted: false,
            actualCost: 0,
            timestamp: block.timestamp,
            isUrgent: _isUrgent,
            category: _category,
            assignedContractor: address(0),
            dueDate: dueDate
        });

        agreementMaintenanceRequests[_agreementId].push(requestId);

        // Send notification to landlord
        if (autoNotificationsEnabled) {
            address recipient = msg.sender == agreements[_agreementId].landlord 
                ? agreements[_agreementId].tenant 
                : agreements[_agreementId].landlord;
            string memory urgencyText = _isUrgent ? "URGENT: " : "";
            _sendNotification(recipient, string(abi.encodePacked(urgencyText, "New maintenance request created.")), "maintenance_request", requestId);
        }

        emit MaintenanceRequestCreated(requestId, _agreementId, msg.sender, _description, _estimatedCost, _isUrgent);
    }

    /**
     * @dev NEW: Assign contractor to maintenance request
     */
    function assignContractor(uint256 _requestId, address _contractor) external nonReentrant whenNotPaused {
        MaintenanceRequest storage request = maintenanceRequests[_requestId];
        require(agreements[request.agreementId].landlord == msg.sender, "Only landlord can assign contractor");
        require(approvedContractors[_contractor], "Contractor not approved");
        require(request.isApproved, "Request must be approved first");
        require(!request.isCompleted, "Request already completed");

        request.assignedContractor = _contractor;

        // Notify contractor
        if (autoNotificationsEnabled) {
            _sendNotification(_contractor, "You have been assigned a new maintenance job.", "contractor_assigned", _requestId);
        }

        emit ContractorAssigned(_requestId, _contractor);
    }

    /**
     * @dev NEW: Send rent reminder notifications
     */
    function sendRentReminders() external onlyOwner {
        // This function can be called by a cron job or automated system
        for (uint256 i = 0; i < agreementCounter; i++) {
            Agreement storage agreement = agreements[i];
            
            if (!agreement.isActive || !agreement.depositPaid) continue;
            
            uint256 timeSinceLastPayment = agreement.lastRentPayment == 0 
                ? block.timestamp - agreement.agreementStart 
                : block.timestamp - agreement.lastRentPayment;
            
            // Send reminder 3 days before rent is due
            uint256 reminderTime = SECONDS_IN_MONTH - (3 * 1 days);
            
            if (timeSinceLastPayment >= reminderTime && timeSinceLastPayment < SECONDS_IN_MONTH) {
                _sendNotification(agreement.tenant, "Rent payment due in 3 days.", "rent_reminder", i);
                emit RentReminderSent(i, agreement.tenant, block.timestamp + (3 * 1 days));
            }
        }
    }

    /**
     * @dev NEW: Mark notification as read
     */
    function markNotificationAsRead(uint256 _notificationIndex) external {
        require(_notificationIndex < userNotifications[msg.sender].length, "Invalid notification index");
        
        Notification storage notification = userNotifications[msg.sender][_notificationIndex];
        if (!notification.isRead) {
            notification.isRead = true;
            if (unreadNotificationCount[msg.sender] > 0) {
                unreadNotificationCount[msg.sender]--;
            }
        }
    }

    /**
     * @dev NEW: Get rent payment history
     */
    function getRentPaymentHistory(uint256 _agreementId) external view agreementExists(_agreementId) onlyAgreementParties(_agreementId) returns (RentPayment[] memory) {
        return rentPaymentHistory[_agreementId];
    }

    /**
     * @dev NEW: Get property inspections
     */
    function getPropertyInspections(uint256 _agreementId) external view agreementExists(_agreementId) returns (Inspection[] memory) {
        return propertyInspections[_agreementId];
    }

    /**
     * @dev NEW: Get user notifications
     */
    function getUserNotifications(address _user) external view returns (Notification[] memory, uint256 unreadCount) {
        return (userNotifications[_user], unreadNotificationCount[_user]);
    }

    /**
     * @dev NEW: Get agreement disputes
     */
    function getAgreementDisputes(uint256 _agreementId) external view agreementExists(_agreementId) returns (uint256[] memory) {
        return agreementDisputes[_agreementId];
    }

    /**
     * @dev NEW: Get property waitlist
     */
    function getPropertyWaitlist(uint256 _agreementId) external view agreementExists(_agreementId) onlyLandlord(_agreementId) returns (address[] memory) {
        return agreementWaitlist[_agreementId];
    }

    /**
     * @dev NEW: Calculate total outstanding balance for tenant
     */
    function getOutstandingBalance(uint256 _agreementId) external view agreementExists(_agreementId) returns (
        uint256 totalOwed,
        uint256 rentOwed,
        uint256 lateFeesOwed,
        uint256 daysOverdue,
        bool isOverdue
    ) {
        Agreement memory agreement = agreements[_agreementId];
        
        if (!agreement.isActive || !agreement.depositPaid) {
            return (0, 0, 0, 0, false);
        }

        uint256 timeSinceLastPayment = agreement.lastRentPayment == 0 
            ? block.timestamp - agreement.agreementStart 
            : block.timestamp - agreement.lastRentPayment;
        
        uint256 gracePeriodSeconds = agreement.gracePeriodDays * 1 days;
        
        if (timeSinceLastPayment > (SECONDS_IN_MONTH + gracePeriodSeconds)) {
            isOverdue = true;
            daysOverdue = (timeSinceLastPayment - SECONDS_IN_MONTH - gracePeriodSeconds) / 1 days;
            
            rentOwed = agreement.monthlyRent;
            lateFeesOwed = agreement.lateFeesOwed + ((agreement.monthlyRent * LATE_FEE_PERCENTAGE * daysOverdue) / (100 * 30));
            
            // Cap late fees
            uint256 maxLateFee = (agreement.monthlyRent * LATE_FEE_PERCENTAGE * MAX_LATE_FEE_MULTIPLIER) / 100;
            if (lateFeesOwed > maxLateFee) {
                lateFeesOwed = maxLateFee;
            }
            
            totalOwed = rentOwed + lateFeesOwed;
        }
    }

    /**
     * @dev NEW: Get property analytics for landlord
     */
    function getPropertyAnalytics(uint256 _agreementId) external view agreementExists(_agreementId) onlyLandlord(_agreementId) returns (
        uint256 totalRentCollected,
        uint256 totalLateFees,
        uint256 averagePaymentDelay,
        uint256 maintenanceRequestCount,
        uint256 completedMaintenanceCount,
        uint256 averageMaintenanceCost
    ) {
        Agreement memory agreement = agreements[_agreementId];
        totalRentCollected = agreement.totalRentPaid;
        
        RentPayment[] memory payments = rentPaymentHistory[_agreementId];
        uint256 totalDelay = 0;
        
        for (uint256 i = 0; i < payments.length; i++) {
            totalLateFees += payments[i].lateFee;
            
            // Calculate payment delay (simplified)
            uint256 expectedPaymentDate = agreement.agreementStart + (i * SECONDS_IN_MONTH);
            if (payments[i].timestamp > expectedPaymentDate) {
                totalDelay += (payments[i].timestamp - expectedPaymentDate) / 1 days;
            }
        }
        
        if (payments.length > 0) {
            averagePaymentDelay = totalDelay / payments.length;
        }
        
        uint256[] memory maintenanceIds = agreementMaintenanceRequests[_agreementId];
        maintenanceRequestCount = maintenanceIds.length;
        
        uint256 totalMaintenanceCost = 0;
        for (uint256 i = 0; i < maintenanceIds.length; i++) {
            MaintenanceRequest memory request = maintenanceRequests[maintenanceIds[i]];
            if (request.isCompleted) {
                completedMaintenanceCount++;
                totalMaintenanceCost += request.actualCost;
            }
        }
        
        if (completedMaintenanceCount > 0) {
            averageMaintenanceCost = totalMaintenanceCost / completedMaintenanceCount;
        }
    }

    /**
     * @dev NEW: Emergency termination for severe violations
     */
    function emergencyTermination(uint256 _agreementId, string memory _reason) external nonReentrant whenNotPaused agreementExists(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.isActive, "Agreement is already terminated");
        
        bool isAuthorized = false;
        
        // Allow landlord for severe lease violations
        if (msg.sender == agreement.landlord) {
            isAuthorized = true;
        }
        
        // Allow tenant for uninhabitable conditions
        if (msg.sender == agreement.tenant) {
            isAuthorized = true;
        }
        
        // Allow owner for emergency situations
        if (msg.sender == owner()) {
            isAuthorized = true;
        }
        
        require(isAuthorized, "Not authorized for emergency termination");
        require(bytes(_reason).length > 0, "Reason required");
        
        agreement.isActive = false;
        
        // Create automatic dispute for emergency termination
        uint256 disputeId = disputeCounter++;
        disputes[disputeId] = Dispute({
            agreementId: _agreementId,
            complainant: msg.sender,
            defendant: msg.sender == agreement.landlord ? agreement.tenant : agreement.landlord,
            disputeType: "emergency_termination",
            description: _reason,
            timestamp: block.timestamp,
            status: DisputeStatus.Open,
            mediator: address(0),
            resolution: "",
            resolutionTimestamp: 0,
            compensationAmount: 0
        });
        
        agreementDisputes[_agreementId].push(disputeId);
        
        // Send notifications
        if (autoNotificationsEnabled) {
            address otherParty = msg.sender == agreement.landlord ? agreement.tenant : agreement.landlord;
            _sendNotification(otherParty, "EMERGENCY: Your rental agreement has been terminated.", "emergency_termination", _agreementId);
        }
        
        emit AgreementTerminated(_agreementId, msg.sender, block.timestamp);
    }

    /**
     * @dev NEW: Set KYC level for user
     */
    function setUserKYCLevel(address _user, uint256 _kycLevel) external onlyOwner {
        require(_user != address(0), "Invalid user address");
        require(_kycLevel <= 2, "Invalid KYC level");
        
        userKYCLevel[_user] = _kycLevel;
    }

    /**
     * @dev NEW: Approve contractor
     */
    function approveContractor(address _contractor, uint256 _rating) external onlyOwner {
        require(_contractor != address(0), "Invalid contractor address");
        require(_rating <= 500, "Rating too high"); // Rating * 100
        
        approvedContractors[_contractor] = true;
        contractorRatings[_contractor] = _rating;
    }

    /**
     * @dev NEW: Set authorized inspector
     */
    function setAuthorizedInspector(address _inspector, bool _authorized) external onlyOwner {
        authorizedInspectors[_inspector] = _authorized;
    }

    /**
     * @dev NEW: Update contract settings
     */
    function updateSettings(
        uint256 _minimumRentAmount,
        uint256 _maximumLateDays,
        bool _autoNotificationsEnabled,
        address _newMediator
    ) external onlyOwner {
        if (_minimumRentAmount > 0) {
            minimumRentAmount = _minimumRentAmount;
        }
        if (_maximumLateDays > 0) {
            maximumLateDays = _maximumLateDays;
        }
        autoNotificationsEnabled = _autoNotificationsEnabled;
        if (_newMediator != address(0)) {
            disputeMediator = _newMediator;
        }
    }

    /**
     * @dev Internal function to send notifications
     */
    function _sendNotification(address _recipient, string memory _message, string memory _type, uint256 _relatedId) internal {
        uint256 notificationId = notificationCounter++;
        
        userNotifications[_recipient].push(Notification({
            recipient: _recipient,
            message: _message,
            timestamp: block.timestamp,
            isRead: false,
            notificationType: _type,
            relatedId: _relatedId
        }));
        
        unreadNotificationCount[_recipient]++;
        
        emit NotificationSent(_recipient, _message, _type, _relatedId);
    }

    // Override existing functions with enhanced features

    /**
     * @dev Approve maintenance request (landlord only) - Enhanced
     */
    function approveMaintenanceRequest(uint256 _requestId, uint256 _approvedCost) external nonReentrant whenNotPaused {
        MaintenanceRequest storage request = maintenanceRequests[_requestId];
        require(agreements[request.agreementId].landlord == msg.sender, "Only landlord can approve");
        require(!request.isApproved, "Request already approved");
        require(_approvedCost > 0, "Approved cost must be greater than 0");

        request.isApproved = true;
        request.estimatedCost = _approvedCost;

        // Send notification to requester
        if (autoNotificationsEnabled) {
            _sendNotification(request.requester, "Your maintenance request has been approved.", "maintenance_approved", _requestId);
        }

        emit MaintenanceRequestApproved(_requestId, _approvedCost);
    }

    /**
     * @dev Complete maintenance request and pay from reserve - Enhanced
     */
    function completeMaintenanceRequest(uint256 _requestId, uint256 _actualCost) external nonReentrant whenNotPaused {
        MaintenanceRequest storage request = maintenanceRequests[_requestId];
        Agreement storage agreement = agreements[request.agreementId];
        
        require(
            agreement.landlord == msg.sender || request.assignedContractor == msg.sender,
            "Only landlord or assigned contractor can complete"
        );
        require(request.isApproved, "Request not approved");
        require(!request.isCompleted, "Request already completed");
        require(_actualCost > 0, "Actual cost must be greater than 0");

        request.isCompleted = true;
        request.actualCost = _actualCost;

        // Pay from maintenance reserve if sufficient
        if (agreement.maintenanceReserve >= _actualCost) {
            agreement.maintenanceReserve -= _actualCost;
            address payee = request.assignedContractor != address(0) ? request.assignedContractor : agreement.landlord;
            (bool success, ) = payee.call{value: _actualCost}("");
            require(success, "Payment failed");
        }

        // Send notification to requester
        if (autoNotificationsEnabled) {
            _sendNotification(request.requester, "Your maintenance request has been completed.", "maintenance_completed", _requestId);
        }

        emit MaintenanceRequestCompleted(_requestId, _actualCost);
    }

    /**
     * @dev Submit review for landlord or tenant - Enhanced with verification
     */
    function submitReview(
        address _reviewee,
        uint256 _rating,
        string memory _comment,
        bool _isLandlordReview
    ) external nonReentrant whenNotPaused {
        require(_reviewee != msg.sender, "Cannot review yourself");
        require(_rating >= 1 && _rating <= 5, "Rating must be between 1 and 5");
        require(bytes(_comment).length > 0, "Comment required");
        require(userKYCLevel[msg.sender] >= 1, "KYC verification required to submit reviews");

        // Verify reviewer has had agreements with reviewee
        bool hasAgreement = false;
        bool agreementCompleted = false;
        
        if (_isLandlordReview) {
            uint256[] memory landlordAgreementIds = landlordAgreements[msg.sender];
            for (uint256 i = 0; i < landlordAgreementIds.length; i++) {
                Agreement memory agreement = agreements[landlordAgreementIds[i]];
                if (agreement.tenant == _reviewee) {
                    hasAgreement = true;
                    if (!agreement.isActive || block.timestamp > agreement.agreementEnd) {
                        agreementCompleted = true;
                    }
                    break;
                }
            }
        } else {
            uint256[] memory tenantAgreementIds = tenantAgreements[msg.sender];
            for (uint256 i = 0; i < tenantAgreementIds.length; i++) {
                Agreement memory agreement = agreements[tenantAgreementIds[i]];
                if (agreement.landlord == _reviewee) {
                    hasAgreement = true;
                    if (!agreement.isActive || block.timestamp > agreement.agreementEnd) {
                        agreementCompleted = true;
                    }
                    break;
                }
            }
        }
        
        require(hasAgreement, "No agreement history with reviewee");
        require(agreementCompleted, "Can only review after agreement completion");

        Review memory newReview = Review({
            reviewer: msg.sender,
            reviewee: _reviewee,
            rating: _rating,
            comment: _comment,
            timestamp: block.timestamp,
            isLandlordReview: _isLandlordReview
        });

        userReviews[_reviewee].push(newReview);
        
        // Update average rating
        uint256 currentCount = userReviewCount[_reviewee];
        uint256 currentAverage = userRatings[_reviewee];
        uint256 newAverage = ((currentAverage * currentCount) + (_rating * 100)) / (currentCount + 1);
        
        userRatings[_reviewee] = newAverage;
        userReviewCount[_reviewee] = currentCount + 1;

        // Send notification
        if (autoNotificationsEnabled) {
            _sendNotification(_reviewee, "You have received a new review.", "review_received", 0);
        }

        emit ReviewSubmitted(msg.sender, _reviewee, _rating, _comment, _isLandlordReview);
    }

    /**
     * @dev Enhanced termination with damage assessment and improved deposit handling
     */
    function terminateAgreement(uint256 _agreementId, bool _returnDeposit, uint256 _damagesCost) external nonReentrant whenNotPaused agreementExists(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.isActive, "Agreement is already terminated");
        require(
            msg.sender == agreement.landlord || msg.sender == agreement.tenant,
            "Only landlord or tenant can terminate"
        );

        // Check for early termination fee
        bool isEarlyTermination = block.timestamp < agreement.agreementEnd;
        uint256 earlyTerminationFee = 0;
        
        if (isEarlyTermination && msg.sender == agreement.tenant) {
            earlyTerminationFee = agreement.earlyTerminationFee;
        }

        agreement.isActive = false;

        // Handle deposit return with damage deduction
        if (_returnDeposit && agreement.depositPaid) {
            require(msg.sender == agreement.landlord, "Only landlord can decide on deposit return");
            
            uint256 totalDeposits = agreement.securityDeposit + agreement.utilityDeposit + agreement.petDeposit;
            uint256 depositToReturn = totalDeposits;
            uint256 totalDeductions = _damagesCost + earlyTerminationFee + agreement.lateFeesOwed;
            
            if (totalDeductions > 0) {
                if (totalDeductions >= totalDeposits) {
                    depositToReturn = 0;
                } else {
                    depositToReturn = totalDeposits - totalDeductions;
                }
            }
            
            if (depositToReturn > 0) {
                require(address(this).balance >= depositToReturn, "Insufficient contract balance");
                (bool success, ) = agreement.tenant.call{value: depositToReturn}("");
                require(success, "Deposit return failed");
                
                emit DepositReturned(_agreementId, agreement.tenant, depositToReturn);
            }
        }

        // Return unused maintenance reserve to landlord
        if (agreement.maintenanceReserve > 0) {
            (bool success, ) = agreement.landlord.call{value: agreement.maintenanceReserve}("");
            require(success, "Maintenance reserve return failed");
        }

        // Send notifications
        if (autoNotificationsEnabled) {
            address otherParty = msg.sender == agreement.landlord ? agreement.tenant : agreement.landlord;
            _sendNotification(otherParty, "Your rental agreement has been terminated.", "agreement_terminated", _agreementId);
        }

        emit AgreementTerminated(_agreementId, msg.sender, block.timestamp);
    }

    // Enhanced view functions
    function getAgreementDetails(uint256 _agreementId) external view agreementExists(_agreementId) returns (
        Agreement memory agreement,
        PropertyDetails memory propertyInfo,
        uint256[] memory maintenanceRequestIds,
        bool rentDue,
        uint256 daysUntilDue,
        uint256 totalOutstanding
    ) {
        agreement = agreements[_agreementId];
        propertyInfo = propertyDetails[_agreementId];
        maintenanceRequestIds = agreementMaintenanceRequests[_agreementId];
        
        if (agreement.isActive && agreement.depositPaid) {
            uint256 timeSinceLastPayment = agreement.lastRentPayment == 0 
                ? block.timestamp - agreement.agreementStart 
                : block.timestamp - agreement.lastRentPayment;
            
            uint256 gracePeriodSeconds = agreement.gracePeriodDays * 1 days;
            rentDue = timeSinceLastPayment >= (SECONDS_IN_MONTH + gracePeriodSeconds);
            
            if (rentDue) {
                daysUntilDue = 0;
                totalOutstanding = agreement.monthlyRent + agreement.lateFeesOwed;
            } else {
                daysUntilDue = (SECONDS_IN_MONTH + gracePeriodSeconds - timeSinceLastPayment) / 1 days;
            }
        }
    }

    function getUserProfile(address _user) external view returns (
        uint256 averageRating,
        uint256 reviewCount,
        uint256 securityScore,
        bool isVerified,
        uint256 totalAgreements,
        uint256 kycLevel,
        uint256 unreadNotifications
    ) {
        averageRating = userRatings[_user];
        reviewCount = userReviewCount[_user];
        securityScore = userSecurityScores[_user];
        isVerified = verifiedUsers[_user];
        totalAgreements = landlordAgreements[_user].length + tenantAgreements[_user].length;
        kycLevel = userKYCLevel[_user];
        unreadNotifications = unreadNotificationCount[_user];
    }

    function getMaintenanceRequest(uint256 _requestId) external view returns (MaintenanceRequest memory) {
        return maintenanceRequests[_requestId];
    }

    function getUserReviews(address _user) external view returns (Review[] memory) {
        return userReviews[_user];
    }

    function getDispute(uint256 _disputeId) external view returns (Dispute memory) {
        return disputes[_disputeId];
    }

    // Admin functions
    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function withdrawPlatformFees() external onlyOwner {
        uint256 fees = totalPlatformFees;
        totalPlatformFees = 0;
        (bool success, ) = owner().call{value: fees}("");
        require(success, "Platform fee withdrawal failed");
    }

    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Emergency withdrawal failed");
    }

    receive() external payable {}
}
