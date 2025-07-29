// ✅ Early termination by tenant with penalty
function terminateAgreementEarly(uint256 _agreementId) 
    external 
    nonReentrant 
    whenNotPaused 
    agreementExists(_agreementId) 
    onlyTenant(_agreementId) 
{
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

// ✅ Toggle auto-renewal by tenant or landlord
function toggleAutoRenewal(uint256 _agreementId, bool _status) 
    external 
    nonReentrant 
    whenNotPaused 
    agreementExists(_agreementId) 
    onlyAgreementParties(_agreementId) 
{
    agreements[_agreementId].autoRenewal = _status;
    emit AutoPaymentSetup(_agreementId, msg.sender, _status);
}

// ✅ Upload KYC hash
function uploadKYC(string calldata _kycHash) external {
    require(bytes(_kycHash).length > 0, "Invalid hash");
    userKYCHash[msg.sender] = _kycHash;
    emit UserVerified(msg.sender, userSecurityScores[msg.sender]);
}

// ✅ Assign maintenance request to contractor
function assignMaintenanceToContractor(uint256 _requestId, address _contractor)
    external
    nonReentrant
    whenNotPaused
{
    MaintenanceRequest storage request = maintenanceRequests[_requestId];
    require(agreements[request.agreementId].landlord == msg.sender, "Not landlord");
    require(verifiedContractors[_contractor], "Contractor not verified");
    require(request.isApproved, "Request not approved");

    request.assignedContractor = _contractor;
}

// ✅ Contractors submit skills and get verified
function submitContractorSkills(string[] calldata _skills) external {
    require(_skills.length > 0, "No skills submitted");

    contractorSkills[msg.sender] = _skills;
    verifiedContractors[msg.sender] = true;

    emit ContractorVerified(msg.sender, _skills);
}

// ✅ Tenant pays rent with optional late fee
function payRent(uint256 _agreementId) 
    external 
    payable 
    nonReentrant 
    whenNotPaused 
    agreementExists(_agreementId) 
    onlyTenant(_agreementId) 
{
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

// ✅ Request document access (optional for private docs)
event DocumentAccessRequested(uint256 indexed agreementId, address indexed requester, string documentType);

function requestDocumentAccess(uint256 _agreementId, string calldata _documentType) external {
    emit DocumentAccessRequested(_agreementId, msg.sender, _documentType);
}
