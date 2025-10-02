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
        // Added to support multi-tenant or shares later if required
        uint256 maintenancePool; // funds set aside for maintenance per agreement
    }

    struct MaintenanceRequest {
        uint256 agreementId;
        bool isApproved;
        address assignedContractor;
        uint256 estimatedCost;
        bool landlordFunded;
        bool paidOut;
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
        address resolvedBy;
    }

    struct PaymentRecord {
        uint256 agreementId;
        uint256 amount;
        uint256 timestamp;
    }

    struct LandlordReview {
        uint256 agreementId;
        address tenant;
        string reviewText;
        uint8 rating; // 1–5
        uint256 timestamp;
    }

    struct RentReminder {
        uint256 agreementId;
        address tenant;
        uint256 remindBeforeDays;
        bool active;
    }

    // New structures for added features
    struct AutoPayment {
        bool enabled;
    }

    struct TenantReview {
        uint256 agreementId;
        address landlord;
        string reviewText;
        uint8 rating;
        uint256 timestamp;
    }

    // Mappings & storage (existing + new)
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
    mapping(address => LandlordReview[]) public landlordReviews;
    mapping(uint256 => RentReminder) public rentReminders;

    mapping(uint256 => AutoPayment) public autoPayments;
    mapping(address => TenantReview[]) public tenantReviews;

    mapping(address => bool) public arbitrators; // arbitrator role appointed by admin

    EmergencyMaintenance[] public emergencyRequests;
    MaintenanceRequest[] public maintenanceRequests;
    Dispute[] public disputes;

    uint256 constant SECONDS_IN_MONTH = 30 days;
    uint256 constant LATE_FEE_PERCENTAGE = 5; // percent per late event baseline
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

    modifier onlyArbitratorOrAdmin() {
        require(msg.sender == admin || arbitrators[msg.sender], "Not arbitrator/admin");
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
    event AgreementRenewalRequested(uint256 agreementId, address requestedBy, uint256 requestedTill);
    event AgreementRenewalRejected(uint256 agreementId, address rejectedBy);
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
    event DisputeResolved(uint256 disputeId, string resolutionNote, address resolvedBy);
    event SecurityDepositRefunded(uint256 agreementId, address tenant, uint256 amount);
    event UserBlacklisted(address user, bool status);
    event PlatformFeesWithdrawn(address admin, uint256 amount);
    event PartialRentPaid(uint256 agreementId, address tenant, uint256 amount);
    event LandlordReviewed(address indexed landlord, address indexed tenant, uint8 rating, string review);
    event RentReminderSet(uint256 indexed agreementId, address tenant, uint256 remindBeforeDays);
    event RentReminderTriggered(uint256 indexed agreementId, address tenant, uint256 dueDate);
    // New events
    event AutoPaymentToggled(uint256 indexed agreementId, address tenant, bool enabled);
    event RentAutoPaid(uint256 indexed agreementId, uint256 amount, uint256 time);
    event EscrowDeposited(address indexed user, uint256 amount);
    event EscrowRentWithdrawn(uint256 indexed agreementId, address landlord, uint256 amount);
    event MaintenancePoolFunded(uint256 indexed agreementId, address by, uint256 amount);
    event TenantReviewed(address indexed tenant, address indexed landlord, uint8 rating, string review);
    event ArbitratorSet(address indexed arbitrator, bool status);
    event MaintenancePayout(uint256 indexed requestId, uint256 agreementId, address to, uint256 amount);

    // ------------------- Core Functions (original + updated) -------------------

    function acceptRentChange(uint256 _agreementId)
        external nonReentrant whenNotPaused agreementExists(_agreementId) onlyTenant(_agreementId)
    {
        uint256 newRent = pendingRentChanges[_agreementId];
        require(newRent > 0, "No proposed rent change");
        agreements[_agreementId].monthlyRent = newRent;
        delete pendingRentChanges[_agreementId];
        emit RentChangeAccepted(_agreementId, newRent);
    }

    // Escrow deposit for tenants (to support auto-pay)
    function depositToEscrow() external payable whenNotPaused notBlacklisted {
        require(msg.value > 0, "No value");
        userEscrowBalance[msg.sender] += msg.value;
        emit EscrowDeposited(msg.sender, msg.value);
    }

    function withdrawEscrow() external nonReentrant whenNotPaused {
        require(userEscrowBalance[msg.sender] > 0, "No balance to withdraw");
        require(!_hasActiveAgreement(msg.sender), "Active agreement exists");

        uint256 balance = userEscrowBalance[msg.sender];
        userEscrowBalance[msg.sender] = 0;
        payable(msg.sender).transfer(balance);
        emit EscrowWithdrawn(msg.sender, balance);
    }

    // Landlord can withdraw monthly rent from escrow if tenant deposited
    function withdrawRentFromEscrow(uint256 _agreementId) external nonReentrant whenNotPaused agreementExists(_agreementId) {
        Agreement storage a = agreements[_agreementId];
        require(msg.sender == a.landlord, "Only landlord");
        uint256 owed = a.monthlyRent;
        require(userEscrowBalance[a.tenant] >= owed, "Insufficient tenant escrow");

        userEscrowBalance[a.tenant] -= owed;
        payable(a.landlord).transfer(owed);

        a.lastRentPayment = block.timestamp;
        a.totalRentPaid += owed;
        emit EscrowRentWithdrawn(_agreementId, a.landlord, owed);
    }

    function depositSecurity(uint256 _agreementId) external payable whenNotPaused {
        Agreement storage a = agreements[_agreementId];
        require(msg.sender == a.landlord, "Only landlord");
        require(msg.value > 0, "No deposit amount");

        a.securityDeposit += msg.value;
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

    // ------------------- New Functionalities -------------------

    // ✅ Early Termination
    function terminateAgreementEarly(uint256 _agreementId)
        external nonReentrant whenNotPaused onlyTenant(_agreementId)
    {
        Agreement storage a = agreements[_agreementId];
        require(a.isActive, "Agreement not active");

        uint256 fee = a.earlyTerminationFee;
        require(userEscrowBalance[msg.sender] >= fee, "Insufficient escrow");

        userEscrowBalance[msg.sender] -= fee;
        totalPlatformFees += fee;

        a.isActive = false;
        emit AgreementTerminated(_agreementId, msg.sender, block.timestamp);
    }

    // ✅ Partial Rent Payment
    function payPartialRent(uint256 _agreementId) external payable whenNotPaused onlyTenant(_agreementId) {
        require(msg.value > 0, "No payment");
        Agreement storage a = agreements[_agreementId];
        require(a.isActive, "Agreement not active");

        a.totalRentPaid += msg.value;
        userPayments[msg.sender].push(PaymentRecord(_agreementId, msg.value, block.timestamp));
        emit PartialRentPaid(_agreementId, msg.sender, msg.value);
    }

    // ✅ Maintenance Funding (landlord funds specific maintenance request)
    function fundMaintenance(uint256 _requestId) external payable {
        MaintenanceRequest storage req = maintenanceRequests[_requestId];
        require(msg.sender == agreements[req.agreementId].landlord, "Only landlord can fund");
        require(!req.landlordFunded, "Already funded");
        require(!req.paidOut, "Already paid out");
        require(msg.value >= req.estimatedCost, "Insufficient funds");

        req.landlordFunded = true;
        // funds are held in contract until paid out to contractor
    }

    // Pay out maintenance to assigned contractor (only landlord or admin)
    function payoutMaintenance(uint256 _requestId) external nonReentrant whenNotPaused {
        MaintenanceRequest storage req = maintenanceRequests[_requestId];
        Agreement storage a = agreements[req.agreementId];
        require(req.landlordFunded, "Not funded");
        require(!req.paidOut, "Already paid");
        require(msg.sender == a.landlord || msg.sender == admin, "Not authorized");

        req.paidOut = true;
        uint256 amount = req.estimatedCost;
        if (address(this).balance >= amount) {
            payable(req.assignedContractor).transfer(amount);
            emit MaintenancePayout(_requestId, req.agreementId, req.assignedContractor, amount);
        }
    }

    // ✅ Security Deposit Refund (admin only)
    function refundSecurityDeposit(uint256 _agreementId) external onlyAdmin {
        Agreement storage a = agreements[_agreementId];
        require(!a.isActive, "Agreement still active");
        require(a.securityDeposit > 0, "No deposit");

        uint256 refund = a.securityDeposit;
        a.securityDeposit = 0;
        payable(a.tenant).transfer(refund);
        emit SecurityDepositRefunded(_agreementId, a.tenant, refund);
    }

    // ✅ Blacklist Management
    function blacklistUser(address _user, bool _status) external onlyAdmin {
        blacklistedUsers[_user] = _status;
        emit UserBlacklisted(_user, _status);
    }

    // ✅ Withdraw Platform Fees
    function withdrawPlatformFees() external onlyAdmin {
        uint256 amount = totalPlatformFees;
        totalPlatformFees = 0;
        payable(admin).transfer(amount);
        emit PlatformFeesWithdrawn(admin, amount);
    }

    // ✅ Payment History
    function getUserPaymentHistory(address _user) external view returns (PaymentRecord[] memory) {
        return userPayments[_user];
    }

    // ✅ Agreement Renewal Request & Approval
    function requestAgreementRenewal(uint256 _agreementId, uint256 _extendMonths)
        external whenNotPaused onlyTenant(_agreementId)
    {
        Agreement storage a = agreements[_agreementId];
        require(a.isActive, "Agreement not active");
        require(_extendMonths > 0, "Invalid extension");

        uint256 requestedTill = a.agreementEnd + (_extendMonths * SECONDS_IN_MONTH);
        emit AgreementRenewalRequested(_agreementId, msg.sender, requestedTill);
    }

    function approveAgreementRenewal(uint256 _agreementId, uint256 _extendMonths)
        external whenNotPaused onlyAgreementParties(_agreementId)
    {
        Agreement storage a = agreements[_agreementId];
        require(a.isActive, "Agreement not active");
        require(_extendMonths > 0, "Invalid extension");

        a.agreementEnd += _extendMonths * SECONDS_IN_MONTH;
        emit AgreementRenewed(_agreementId, msg.sender, a.agreementEnd);
    }

    function rejectAgreementRenewal(uint256 _agreementId)
        external whenNotPaused onlyAgreementParties(_agreementId)
    {
        Agreement memory a = agreements[_agreementId];
        require(a.isActive, "Agreement not active");
        emit AgreementRenewalRejected(_agreementId, msg.sender);
    }

    // ✅ Dispute Resolution System
    function raiseDispute(uint256 _agreementId, string calldata _reason)
        external whenNotPaused onlyAgreementParties(_agreementId)
    {
        disputes.push(Dispute({
            agreementId: _agreementId,
            raisedBy: msg.sender,
            reason: _reason,
            resolved: false,
            resolutionNote: "",
            resolvedBy: address(0)
        }));
        emit DisputeRaised(disputes.length - 1, _agreementId, msg.sender, _reason);
    }

    // Admin or arbitrator can resolve disputes
    function resolveDispute(uint256 _disputeId, string calldata _resolutionNote)
        external whenNotPaused onlyArbitratorOrAdmin
    {
        Dispute storage d = disputes[_disputeId];
        require(!d.resolved, "Dispute already resolved");

        d.resolved = true;
        d.resolutionNote = _resolutionNote;
        d.resolvedBy = msg.sender;
        emit DisputeResolved(_disputeId, _resolutionNote, msg.sender);
    }

    // ✅ Tenant Review System for Landlords
    function leaveLandlordReview(uint256 _agreementId, string calldata _reviewText, uint8 _rating)
        external whenNotPaused onlyTenant(_agreementId)
    {
        Agreement memory a = agreements[_agreementId];
        require(!a.isActive, "Agreement still active");
        require(_rating >= 1 && _rating <= 5, "Invalid rating");

        landlordReviews[a.landlord].push(LandlordReview({
            agreementId: _agreementId,
            tenant: msg.sender,
            reviewText: _reviewText,
            rating: _rating,
            timestamp: block.timestamp
        }));

        emit LandlordReviewed(a.landlord, msg.sender, _rating, _reviewText);
    }

    function getLandlordReviews(address _landlord) external view returns (LandlordReview[] memory) {
        return landlordReviews[_landlord];
    }

    // Landlord can leave review for tenant after agreement ends
    function leaveTenantReview(uint256 _agreementId, string calldata _reviewText, uint8 _rating)
        external whenNotPaused
    {
        Agreement memory a = agreements[_agreementId];
        require(msg.sender == a.landlord, "Only landlord can review");
        require(!a.isActive, "Agreement still active");
        require(_rating >= 1 && _rating <= 5, "Invalid rating");

        tenantReviews[a.tenant].push(TenantReview({
            agreementId: _agreementId,
            landlord: msg.sender,
            reviewText: _reviewText,
            rating: _rating,
            timestamp: block.timestamp
        }));

        emit TenantReviewed(a.tenant, msg.sender, _rating, _reviewText);
    }

    function getTenantReviews(address _tenant) external view returns (TenantReview[] memory) {
        return tenantReviews[_tenant];
    }

    // ------------------- Auto Payment Functionality -------------------

    // Tenant toggles auto payment (auto-debit from their escrow)
    function toggleAutoPayment(uint256 _agreementId, bool _status)
        external whenNotPaused onlyTenant(_agreementId)
    {
        autoPayments[_agreementId].enabled = _status;
        emit AutoPaymentToggled(_agreementId, msg.sender, _status);
    }

    // Process auto payment: contract checks tenant escrow and transfers rent to landlord
    // This function can be called by anyone (e.g., an off-chain keeper, or the tenant)
    function processAutoPayment(uint256 _agreementId) external nonReentrant whenNotPaused agreementExists(_agreementId) {
        Agreement storage a = agreements[_agreementId];
        require(a.isActive, "Agreement not active");
        require(autoPayments[_agreementId].enabled, "Auto payment disabled");

        uint256 dueDate = a.lastRentPayment + SECONDS_IN_MONTH;
        require(block.timestamp >= dueDate, "Rent not due yet");

        uint256 rentAmount = a.monthlyRent;
        // Check for overdue penalty beyond grace period
        if (block.timestamp > dueDate + (a.gracePeriodDays * 1 days)) {
            uint256 daysOverdue = (block.timestamp - dueDate) / 1 days;
            // Cap multiplier to MAX_LATE_FEE_MULTIPLIER
            uint256 multiplier = daysOverdue;
            if (multiplier > MAX_LATE_FEE_MULTIPLIER) multiplier = MAX_LATE_FEE_MULTIPLIER;
            uint256 lateFee = (rentAmount * LATE_FEE_PERCENTAGE * multiplier) / 100;
            // Add late fee to rent amount
            rentAmount += lateFee;
            a.lateFeesOwed += lateFee;
        }

        require(userEscrowBalance[a.tenant] >= rentAmount, "Insufficient escrow");
        userEscrowBalance[a.tenant] -= rentAmount;
        payable(a.landlord).transfer(rentAmount);

        a.lastRentPayment = block.timestamp;
        a.totalRentPaid += rentAmount;

        emit RentAutoPaid(_agreementId, rentAmount, block.timestamp);
    }

    // Legacy/manual rent pay function (tenant pays directly)
    function payRent(uint256 _agreementId) external payable whenNotPaused onlyTenant(_agreementId) nonReentrant {
        require(msg.value > 0, "No payment");
        Agreement storage a = agreements[_agreementId];
        require(a.isActive, "Agreement not active");

        uint256 rentAmount = a.monthlyRent;
        uint256 lateFee = 0;
        uint256 dueDate = a.lastRentPayment + SECONDS_IN_MONTH;

        if (block.timestamp > dueDate + (a.gracePeriodDays * 1 days)) {
            uint256 daysOverdue = (block.timestamp - dueDate) / 1 days;
            uint256 multiplier = daysOverdue;
            if (multiplier > MAX_LATE_FEE_MULTIPLIER) multiplier = MAX_LATE_FEE_MULTIPLIER;
            lateFee = (rentAmount * LATE_FEE_PERCENTAGE * multiplier) / 100;
            a.lateFeesOwed += lateFee;
        }

        require(msg.value >= rentAmount + lateFee, "Insufficient value including late fee");
        // Transfer rent (excess refunded)
        uint256 toLandlord = rentAmount + lateFee;
        payable(a.landlord).transfer(toLandlord);
        uint256 excess = msg.value - toLandlord;
        if (excess > 0) {
            // keep excess in tenant escrow for convenience
            userEscrowBalance[msg.sender] += excess;
        }

        a.lastRentPayment = block.timestamp;
        a.totalRentPaid += toLandlord;

        userPayments[msg.sender].push(PaymentRecord(_agreementId, toLandlord, block.timestamp));
        emit RentPaid(_agreementId, msg.sender, rentAmount, lateFee, block.timestamp);
    }

    // ------------------- Rent Reminder System -------------------
    function setRentReminder(uint256 _agreementId, uint256 _daysBefore)
        external whenNotPaused onlyTenant(_agreementId)
    {
        require(_daysBefore > 0 && _daysBefore <= 30, "Invalid reminder days");
        Agreement memory a = agreements[_agreementId];
        require(a.isActive, "Agreement not active");

        rentReminders[_agreementId] = RentReminder({
            agreementId: _agreementId,
            tenant: msg.sender,
            remindBeforeDays: _daysBefore,
            active: true
        });

        emit RentReminderSet(_agreementId, msg.sender, _daysBefore);
    }

    function triggerRentReminder(uint256 _agreementId)
        external whenNotPaused onlyAgreementParties(_agreementId)
    {
        Agreement memory a = agreements[_agreementId];
        require(a.isActive, "Agreement not active");

        RentReminder memory r = rentReminders[_agreementId];
        require(r.active, "No reminder set");

        uint256 dueDate = a.lastRentPayment + SECONDS_IN_MONTH;
        require(block.timestamp >= dueDate - (r.remindBeforeDays * 1 days), "Too early");

        emit RentReminderTriggered(_agreementId, r.tenant, dueDate);
    }

    // ------------------- Maintenance Pooling -------------------
    // Tenant or landlord can add to maintenance pool for agreement
    function fundMaintenancePool(uint256 _agreementId) external payable whenNotPaused {
        require(msg.value > 0, "No funds");
        Agreement storage a = agreements[_agreementId];
        require(a.isActive, "Agreement not active");

        // Allow both tenant and landlord to fund maintenance pool
        a.maintenancePool += msg.value;
        emit MaintenancePoolFunded(_agreementId, msg.sender, msg.value);
    }

    // Use funds from maintenance pool to pay contractor (landlord only)
    function payFromMaintenancePool(uint256 _agreementId, address _to, uint256 _amount) external nonReentrant whenNotPaused {
        require(_amount > 0, "Zero amount");
        Agreement storage a = agreements[_agreementId];
        require(msg.sender == a.landlord, "Only landlord");
        require(a.maintenancePool >= _amount, "Insufficient pool");

        a.maintenancePool -= _amount;
        payable(_to).transfer(_amount);
        emit MaintenancePayout(type(uint256).max, _agreementId, _to, _amount); // request id not used here
    }

    // ------------------- Helper & Admin Functions -------------------

    function _hasActiveAgreement(address _user) internal view returns (bool) {
        // Note: original code iterated 0..99; keep same but safer if your agreements id space differs.
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

    // Admin: set arbitrator
    function setArbitrator(address _arb, bool _status) external onlyAdmin {
        arbitrators[_arb] = _status;
        emit ArbitratorSet(_arb, _status);
    }

    // Admin: create a basic agreement helper (for testing / creation)
    function createAgreement(
        uint256 _id,
        address _tenant,
        address _landlord,
        uint256 _monthlyRent,
        uint256 _agreementEnd,
        uint256 _earlyTerminationFee,
        uint256 _gracePeriodDays
    ) external onlyAdmin {
        require(agreements[_id].tenant == address(0), "Agreement exists");
        agreements[_id] = Agreement({
            tenant: _tenant,
            landlord: _landlord,
            monthlyRent: _monthlyRent,
            agreementEnd: _agreementEnd,
            lastRentPayment: block.timestamp,
            totalRentPaid: 0,
            earlyTerminationFee: _earlyTerminationFee,
            gracePeriodDays: _gracePeriodDays,
            isActive: true,
            autoRenewal: false,
            lateFeesOwed: 0,
            securityDeposit: 0,
            maintenancePool: 0
        });
    }

    // Admin: propose rent change
    function proposeRentChange(uint256 _agreementId, uint256 _newRent)
        external whenNotPaused onlyAgreementParties(_agreementId)
    {
        require(_newRent > 0, "Invalid rent");
        pendingRentChanges[_agreementId] = _newRent;
        emit RentChangeProposed(_agreementId, msg.sender, _newRent);
    }

    // Misc: request emergency maintenance
    function raiseEmergencyMaintenance(uint256 _agreementId, string calldata _description) external whenNotPaused onlyTenant(_agreementId) {
        emergencyRequests.push(EmergencyMaintenance({
            agreementId: _agreementId,
            raisedBy: msg.sender,
            description: _description,
            timestamp: block.timestamp,
            resolved: false
        }));
        emit EmergencyMaintenanceRaised(emergencyRequests.length - 1, _agreementId, msg.sender, _description);
    }

    // Add maintenance request
    function createMaintenanceRequest(uint256 _agreementId, uint256 _estimatedCost) external whenNotPaused onlyAgreementParties(_agreementId) {
        maintenanceRequests.push(MaintenanceRequest({
            agreementId: _agreementId,
            isApproved: false,
            assignedContractor: address(0),
            estimatedCost: _estimatedCost,
            landlordFunded: false,
            paidOut: false
        }));
    }

    // Assign contractor to a maintenance request (landlord or admin)
    function assignContractorToRequest(uint256 _requestId, address _contractor) external whenNotPaused {
        MaintenanceRequest storage req = maintenanceRequests[_requestId];
        Agreement memory a = agreements[req.agreementId];
        require(msg.sender == a.landlord || msg.sender == admin, "Not authorized");
        req.assignedContractor = _contractor;
        req.isApproved = true;
    }

    // rate contractor
    function rateContractor(address _contractor, uint8 _rating) external whenNotPaused {
        require(_rating >= 1 && _rating <= 5, "Invalid rating");
        contractorRatings[_contractor].push(_rating);
        emit ContractorRated(_contractor, _rating);
    }

    // Fallback / receive to accept ETH when needed (e.g., funding maintenance via fundMaintenance)
    receive() external payable {}
    fallback() external payable {}
}
