// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract RentalAgreement is ReentrancyGuard, Ownable {
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
    }

    mapping(uint256 => Agreement) public agreements;
    mapping(address => uint256[]) public landlordAgreements;
    mapping(address => uint256[]) public tenantAgreements;
    
    uint256 public agreementCounter;
    uint256 public constant LATE_FEE_PERCENTAGE = 5; // 5% late fee
    uint256 public constant SECONDS_IN_MONTH = 30 days;

    event AgreementCreated(
        uint256 indexed agreementId,
        address indexed landlord,
        address indexed tenant,
        uint256 monthlyRent,
        uint256 securityDeposit
    );

    event RentPaid(
        uint256 indexed agreementId,
        address indexed tenant,
        uint256 amount,
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

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Creates a new rental agreement
     * @param _tenant Address of the tenant
     * @param _monthlyRent Monthly rent amount in wei
     * @param _securityDeposit Security deposit amount in wei
     * @param _durationInMonths Duration of the agreement in months
     */
    function createAgreement(
        address _tenant,
        uint256 _monthlyRent,
        uint256 _securityDeposit,
        uint256 _durationInMonths
    ) external nonReentrant {
        require(_tenant != address(0), "Invalid tenant address");
        require(_tenant != msg.sender, "Landlord cannot be tenant");
        require(_monthlyRent > 0, "Monthly rent must be greater than 0");
        require(_securityDeposit > 0, "Security deposit must be greater than 0");
        require(_durationInMonths > 0, "Duration must be greater than 0");

        uint256 agreementId = agreementCounter++;
        
        agreements[agreementId] = Agreement({
            landlord: msg.sender,
            tenant: _tenant,
            monthlyRent: _monthlyRent,
            securityDeposit: _securityDeposit,
            agreementStart: block.timestamp,
            agreementEnd: block.timestamp + (_durationInMonths * SECONDS_IN_MONTH),
            isActive: true,
            depositPaid: false,
            lastRentPayment: 0
        });

        landlordAgreements[msg.sender].push(agreementId);
        tenantAgreements[_tenant].push(agreementId);

        emit AgreementCreated(agreementId, msg.sender, _tenant, _monthlyRent, _securityDeposit);
    }

    /**
     * @dev Allows tenant to pay security deposit and monthly rent
     * @param _agreementId ID of the agreement
     */
    function payRent(uint256 _agreementId) external payable nonReentrant agreementExists(_agreementId) onlyTenant(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.isActive, "Agreement is not active");
        require(block.timestamp <= agreement.agreementEnd, "Agreement has expired");

        uint256 expectedAmount = agreement.monthlyRent;
        
        // If deposit not paid, add deposit to expected amount
        if (!agreement.depositPaid) {
            expectedAmount += agreement.securityDeposit;
        }

        // Check if rent is late (more than 30 days since last payment or agreement start)
        uint256 timeSinceLastPayment = agreement.lastRentPayment == 0 
            ? block.timestamp - agreement.agreementStart 
            : block.timestamp - agreement.lastRentPayment;

        if (timeSinceLastPayment > SECONDS_IN_MONTH && agreement.lastRentPayment != 0) {
            // Apply late fee
            uint256 lateFee = (agreement.monthlyRent * LATE_FEE_PERCENTAGE) / 100;
            expectedAmount += lateFee;
        }

        require(msg.value >= expectedAmount, "Insufficient payment amount");

        // Mark deposit as paid if this is the first payment
        if (!agreement.depositPaid) {
            agreement.depositPaid = true;
        }

        agreement.lastRentPayment = block.timestamp;

        // Transfer rent to landlord
        uint256 rentAmount = agreement.monthlyRent;
        if (timeSinceLastPayment > SECONDS_IN_MONTH && agreement.lastRentPayment != block.timestamp) {
            uint256 lateFee = (agreement.monthlyRent * LATE_FEE_PERCENTAGE) / 100;
            rentAmount += lateFee;
        }

        (bool success, ) = agreement.landlord.call{value: rentAmount}("");
        require(success, "Transfer to landlord failed");

        // Refund excess payment if any
        if (msg.value > expectedAmount) {
            (bool refundSuccess, ) = msg.sender.call{value: msg.value - expectedAmount}("");
            require(refundSuccess, "Refund failed");
        }

        emit RentPaid(_agreementId, msg.sender, rentAmount, block.timestamp);
    }

    /**
     * @dev Terminates the rental agreement and handles deposit return
     * @param _agreementId ID of the agreement
     * @param _returnDeposit Whether to return the security deposit to tenant
     */
    function terminateAgreement(uint256 _agreementId, bool _returnDeposit) external nonReentrant agreementExists(_agreementId) {
        Agreement storage agreement = agreements[_agreementId];
        require(agreement.isActive, "Agreement is already terminated");
        require(
            msg.sender == agreement.landlord || msg.sender == agreement.tenant,
            "Only landlord or tenant can terminate"
        );

        agreement.isActive = false;

        // Return deposit if requested and conditions are met
        if (_returnDeposit && agreement.depositPaid) {
            require(msg.sender == agreement.landlord, "Only landlord can decide on deposit return");
            require(address(this).balance >= agreement.securityDeposit, "Insufficient contract balance");
            
            (bool success, ) = agreement.tenant.call{value: agreement.securityDeposit}("");
            require(success, "Deposit return failed");
            
            emit DepositReturned(_agreementId, agreement.tenant, agreement.securityDeposit);
        }

        emit AgreementTerminated(_agreementId, msg.sender, block.timestamp);
    }

    // View functions
    function getAgreement(uint256 _agreementId) external view agreementExists(_agreementId) returns (Agreement memory) {
        return agreements[_agreementId];
    }

    function getLandlordAgreements(address _landlord) external view returns (uint256[] memory) {
        return landlordAgreements[_landlord];
    }

    function getTenantAgreements(address _tenant) external view returns (uint256[] memory) {
        return tenantAgreements[_tenant];
    }

    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function isRentDue(uint256 _agreementId) external view agreementExists(_agreementId) returns (bool) {
        Agreement memory agreement = agreements[_agreementId];
        if (!agreement.isActive || !agreement.depositPaid) return false;
        
        uint256 timeSinceLastPayment = agreement.lastRentPayment == 0 
            ? block.timestamp - agreement.agreementStart 
            : block.timestamp - agreement.lastRentPayment;
            
        return timeSinceLastPayment >= SECONDS_IN_MONTH;
    }

    // Emergency functions
    function emergencyWithdraw() external onlyOwner {
        (bool success, ) = owner().call{value: address(this).balance}("");
        require(success, "Emergency withdrawal failed");
    }

    receive() external payable {}
}
