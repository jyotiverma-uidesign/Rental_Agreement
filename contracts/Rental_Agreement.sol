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
    }

    struct Review {
        address reviewer;
        address reviewee;
        uint256 rating; // 1-5 stars
        string comment;
        uint256 timestamp;
        bool isLandlordReview; // true if landlord reviewing tenant
    }

    mapping(uint256 => Agreement) public agreements;
    mapping(address => uint256[]) public landlordAgreements;
    mapping(address => uint256[]) public tenantAgreements;
    mapping(uint256 => MaintenanceRequest) public maintenanceRequests;
    mapping(address => Review[]) public userReviews;
    mapping(address => uint256) public userRatings; // Average rating * 100
    mapping(address => uint256) public userReviewCount;
    mapping(uint256 => uint256[]) public agreementMaintenanceRequests;
    
    uint256 public agreementCounter;
    uint256 public maintenanceRequestCounter;
    uint256 public constant LATE_FEE_PERCENTAGE = 5; // 5% late fee
    uint256 public constant SECONDS_IN_MONTH = 30 days;
    uint256 public constant MAINTENANCE_RESERVE_PERCENTAGE = 2; // 2% of monthly rent
    uint256 public constant PLATFORM_FEE_PERCENTAGE = 1; // 1% platform fee
    uint256 public constant MAX_LATE_FEE_MULTIPLIER = 3; // Max 3x late fees
    
    // New state variables
    uint256 public totalPlatformFees;
    mapping(address => bool) public verifiedUsers;
    mapping(address => uint256) public userSecurityScores;

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

    constructor() Ownable(msg.sender) {}

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
        uint256 _renewalDuration
    ) external nonReentrant whenNotPaused {
        require(_tenant != address(0), "Invalid tenant address");
        require(_tenant != msg.sender, "Landlord cannot be tenant");
        require(_monthlyRent > 0, "Monthly rent must be greater than 0");
        require(_securityDeposit > 0, "Security deposit must be greater than 0");
        require(_durationInMonths > 0, "Duration must be greater than 0");
        require(bytes(_propertyAddress).length > 0, "Property address required");

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
            totalRentPaid: 0
        });

        landlordAgreements[msg.sender].push(agreementId);
        tenantAgreements[_tenant].push(agreementId);

        emit AgreementCreated(agreementId, msg.sender, _tenant, _monthlyRent, _securityDeposit, _propertyAddress);
    }

    /**
     * @dev Enhanced rent payment with automatic calculations
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
        }

        // Add maintenance reserve
        expectedAmount += agreement.maintenanceReserve;

        // Calculate late fees
        uint256 timeSinceLastPayment = agreement.lastRentPayment == 0 
            ? block.timestamp - agreement.agreementStart 
            : block.timestamp - agreement.lastRentPayment;

        if (timeSinceLastPayment > SECONDS_IN_MONTH && agreement.lastRentPayment != 0) {
            // Progressive late fee calculation
            uint256 monthsLate = timeSinceLastPayment / SECONDS_IN_MONTH;
            lateFee = (agreement.monthlyRent * LATE_FEE_PERCENTAGE * monthsLate) / 100;
            
            // Cap late fees
            uint256 maxLateFee = (agreement.monthlyRent * LATE_FEE_PERCENTAGE * MAX_LATE_FEE_MULTIPLIER) / 100;
            if (lateFee > maxLateFee) {
                lateFee = maxLateFee;
            }
            
            expectedAmount += lateFee;
        }

        // Add any outstanding late fees
        expectedAmount += agreement.lateFeesOwed;

        require(msg.value >= expectedAmount, "Insufficient payment amount");

        // Mark deposit as paid if this is the first payment
        if (!agreement.depositPaid) {
            agreement.depositPaid = true;
        }

        agreement.lastRentPayment = block.timestamp;
        agreement.lateFeesOwed = 0; // Clear outstanding late fees
        agreement.totalRentPaid += agreement.monthlyRent;

        // Calculate platform fee
        uint256 platformFee = (agreement.monthlyRent * PLATFORM_FEE_PERCENTAGE) / 100;
        totalPlatformFees += platformFee;

        // Transfer amounts
        uint256 landlordAmount = agreement.monthlyRent + lateFee - platformFee;
        (bool success, ) = agreement.landlord.call{value: landlordAmount}("");
        require(success, "Transfer to landlord failed");

        // Refund excess payment if any
        if (msg.value > expectedAmount) {
            (bool refundSuccess, ) = msg.sender.call{value: msg.value - expectedAmount}("");
            require(refundSuccess, "Refund failed");
        }

        emit RentPaid(_agreementId, msg.sender, agreement.monthlyRent, lateFee, block.timestamp);
    }

    /**
     * @dev Create maintenance request
     */
    function createMaintenanceRequest(
        uint256 _agreementId,
        string memory _description,
        uint256 _estimatedCost,
        bool _isUrgent
    ) external nonReentrant whenNotPaused agreementExists(_agreementId) onlyAgreementParties(_agreementId) {
        require(agreements[_agreementId].isActive, "Agreement is not active");
        require(bytes(_description).length > 0, "Description required");
        require(_estimatedCost > 0, "Estimated cost must be greater than 0");

        uint256 requestId = maintenanceRequestCounter++;
        
        maintenanceRequests[requestId] = MaintenanceRequest({
            agreementId: _agreementId,
            requester: msg.sender,
            description: _description,
            estimatedCost: _estimatedCost,
            isApproved: false,
            isCompleted: false,
            actualCost: 0,
            timestamp: block.timestamp,
            isUrgent: _isUrgent
        });

        agreementMaintenanceRequests[_agreementId].push(requestId);

        emit MaintenanceRequestCreated(requestId, _agreementId, msg.sender, _description, _estimatedCost, _isUrgent);
    }

    /**
     * @dev Approve maintenance request (landlord only)
     */
    function approveMaintenanceRequest(uint256 _requestId, uint256 _approvedCost) external nonReentrant whenNotPaused {
        MaintenanceRequest storage request = maintenanceRequests[_requestId];
        require(agreements[request.agreementId].landlord == msg.sender, "Only landlord can approve");
        require(!request.isApproved, "Request already approved");
        require(_approvedCost > 0, "Approved cost must be greater than 0");

        request.isApproved = true;
        request.estimatedCost = _approvedCost;

        emit MaintenanceRequestApproved(_requestId, _approvedCost);
    }

    /**
     * @dev Complete maintenance request and pay from reserve
     */
    function completeMaintenanceRequest(uint256 _requestId, uint256 _actualCost) external nonReentrant whenNotPaused {
        MaintenanceRequest storage request = maintenanceRequests[_requestId];
        Agreement storage agreement = agreements[request.agreementId];
        
        require(agreement.landlord == msg.sender, "Only landlord can complete");
        require(request.isApproved, "Request not approved");
        require(!request.isCompleted, "Request already completed");
        require(_actualCost > 0, "Actual cost must be greater than 0");

        request.isCompleted = true;
        request.actualCost = _actualCost;

        // Pay from maintenance reserve if sufficient
        if (agreement.maintenanceReserve >= _actualCost) {
            agreement.maintenanceReserve -= _actualCost;
            (bool success, ) = msg.sender.call{value: _actualCost}("");
            require(success, "Payment failed");
        }

        emit MaintenanceRequestCompleted(_requestId, _actualCost);
    }

    /**
     * @dev Submit review for landlord or tenant
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

        // Verify reviewer has had agreements with reviewee
        bool hasAgreement = false;
        if (_isLandlordReview) {
            // Check if msg.sender (landlord) has agreements with _reviewee (tenant)
            uint256[] memory landlordAgreementIds = landlordAgreements[msg.sender];
            for (uint256 i = 0; i < landlordAgreementIds.length; i++) {
                if (agreements[landlordAgreementIds[i]].tenant == _reviewee) {
                    hasAgreement = true;
                    break;
                }
            }
        } else {
            // Check if msg.sender (tenant) has agreements with _reviewee (landlord)
            uint256[] memory tenantAgreementIds = tenantAgreements[msg.sender];
            for (uint256 i = 0; i < tenantAgreementIds.length; i++) {
                if (agreements[tenantAgreementIds[i]].landlord == _reviewee) {
                    hasAgreement = true;
                    break;
                }
            }
        }
        require(hasAgreement, "No agreement history with reviewee");

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

        emit ReviewSubmitted(msg.sender, _reviewee, _rating, _comment, _isLandlordReview);
    }

    /**
     * @dev Renew agreement (automatic or manual)
     */
    function renewAgreement(uint256 _agreementId, uint256 _newMonthlyRent) external nonReentrant whenNotPaused agreementExists(_agreementId) onlyLandlord(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.isActive, "Agreement is not active");
        require(block.timestamp >= agreement.agreementEnd - (7 days), "Too early to renew");
        require(_newMonthlyRent > 0, "New rent must be greater than 0");

        uint256 renewalDuration = agreement.renewalDuration > 0 ? agreement.renewalDuration : 12; // Default 12 months
        agreement.agreementEnd = block.timestamp + (renewalDuration * SECONDS_IN_MONTH);
        agreement.monthlyRent = _newMonthlyRent;
        agreement.maintenanceReserve = (_newMonthlyRent * MAINTENANCE_RESERVE_PERCENTAGE) / 100;

        emit AgreementRenewed(_agreementId, agreement.agreementEnd, _newMonthlyRent);
    }

    /**
     * @dev Verify user with security score
     */
    function verifyUser(address _user, uint256 _securityScore) external onlyOwner {
        require(_user != address(0), "Invalid user address");
        require(_securityScore <= 100, "Security score must be <= 100");
        
        verifiedUsers[_user] = true;
        userSecurityScores[_user] = _securityScore;
        
        emit UserVerified(_user, _securityScore);
    }

    /**
     * @dev Enhanced termination with damage assessment
     */
    function terminateAgreement(uint256 _agreementId, bool _returnDeposit, uint256 _damagesCost) external nonReentrant whenNotPaused agreementExists(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.isActive, "Agreement is already terminated");
        require(
            msg.sender == agreement.landlord || msg.sender == agreement.tenant,
            "Only landlord or tenant can terminate"
        );

        agreement.isActive = false;

        // Handle deposit return with damage deduction
        if (_returnDeposit && agreement.depositPaid) {
            require(msg.sender == agreement.landlord, "Only landlord can decide on deposit return");
            
            uint256 depositToReturn = agreement.securityDeposit;
            if (_damagesCost > 0) {
                require(msg.sender == agreement.landlord, "Only landlord can assess damages");
                if (_damagesCost >= agreement.securityDeposit) {
                    depositToReturn = 0;
                } else {
                    depositToReturn = agreement.securityDeposit - _damagesCost;
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

        emit AgreementTerminated(_agreementId, msg.sender, block.timestamp);
    }

    // Enhanced view functions
    function getAgreementDetails(uint256 _agreementId) external view agreementExists(_agreementId) returns (
        Agreement memory agreement,
        uint256[] memory maintenanceRequestIds,
        bool rentDue,
        uint256 daysUntilDue
    ) {
        agreement = agreements[_agreementId];
        maintenanceRequestIds = agreementMaintenanceRequests[_agreementId];
        
        if (agreement.isActive && agreement.depositPaid) {
            uint256 timeSinceLastPayment = agreement.lastRentPayment == 0 
                ? block.timestamp - agreement.agreementStart 
                : block.timestamp - agreement.lastRentPayment;
            rentDue = timeSinceLastPayment >= SECONDS_IN_MONTH;
            daysUntilDue = rentDue ? 0 : (SECONDS_IN_MONTH - timeSinceLastPayment) / 1 days;
        }
    }

    function getUserProfile(address _user) external view returns (
        uint256 averageRating,
        uint256 reviewCount,
        uint256 securityScore,
        bool isVerified,
        uint256 totalAgreements
    ) {
        averageRating = userRatings[_user];
        reviewCount = userReviewCount[_user];
        securityScore = userSecurityScores[_user];
        isVerified = verifiedUsers[_user];
        totalAgreements = landlordAgreements[_user].length + tenantAgreements[_user].length;
    }

    function getMaintenanceRequest(uint256 _requestId) external view returns (MaintenanceRequest memory) {
        return maintenanceRequests[_requestId];
    }

    function getUserReviews(address _user) external view returns (Review[] memory) {
        return userReviews[_user];
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
