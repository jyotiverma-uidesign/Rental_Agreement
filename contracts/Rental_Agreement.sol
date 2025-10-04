// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract RentalAgreement is ReentrancyGuard, Pausable {
    address public admin;
    uint256 public totalPlatformFees;
    uint256 public constant SECONDS_IN_MONTH = 30 days;

    constructor() { admin = msg.sender; }

    modifier onlyAdmin() { require(msg.sender == admin, "Not admin"); _; }
    modifier onlyLandlord(uint id) { require(msg.sender == agreements[id].landlord, "Not landlord"); _; }
    modifier onlyTenant(uint id) { require(msg.sender == agreements[id].tenant, "Not tenant"); _; }

    struct Agreement {
        address landlord;
        address tenant;
        uint rent;
        uint deposit;
        uint startDate;
        uint duration;
        uint lastPayment;
        bool active;
        bool autoRenew;
        uint graceDays;
        uint lateFee;
        string landlordKYC;
        string tenantKYC;
        uint contractorId;
    }

    struct Contractor { address addr; string skill; bool assigned; bool done; }
    struct RentInsurance { bool active; uint premium; uint coverage; bool claimed; }

    mapping(uint => Agreement) public agreements;
    mapping(uint => Contractor) public contractors;
    mapping(address => RentInsurance) public insurance;
    uint public nextAgreementId;
    uint public nextContractorId;
    uint public insurancePool;

    event AgreementCreated(uint id, address landlord, address tenant, uint rent);
    event RentPaid(uint id, uint amount);
    event AgreementEnded(uint id);
    event InsuranceBought(address tenant, uint premium);
    event InsuranceClaimed(address tenant, uint payout);
    event ContractorAssigned(uint id, address contractor);
    event ContractorDone(uint id);

    // -------- Agreement --------
    function createAgreement(
        address _tenant, uint _rent, uint _deposit, uint _duration,
        uint _graceDays, uint _lateFee, string memory _lKYC, string memory _tKYC
    ) external whenNotPaused {
        uint id = ++nextAgreementId;
        agreements[id] = Agreement({
            landlord: msg.sender, tenant: _tenant, rent: _rent, deposit: _deposit,
            startDate: block.timestamp, duration: _duration, lastPayment: block.timestamp,
            active: true, autoRenew: true, graceDays: _graceDays, lateFee: _lateFee,
            landlordKYC: _lKYC, tenantKYC: _tKYC, contractorId: 0
        });
        emit AgreementCreated(id, msg.sender, _tenant, _rent);
    }

    function payRent(uint id) external payable nonReentrant whenNotPaused onlyTenant(id) {
        Agreement storage a = agreements[id];
        require(a.active, "Inactive");
        uint due = a.rent;
        if (block.timestamp > a.lastPayment + SECONDS_IN_MONTH + (a.graceDays * 1 days))
            due += a.lateFee;
        require(msg.value >= due, "Insufficient");
        a.lastPayment = block.timestamp;
        payable(a.landlord).transfer(due);
        totalPlatformFees += (msg.value - due);
        emit RentPaid(id, due);
    }

    function endAgreement(uint id) external whenNotPaused {
        Agreement storage a = agreements[id];
        require(a.active, "Ended");
        require(msg.sender == a.landlord || msg.sender == a.tenant || msg.sender == admin, "Unauthorized");
        a.active = false;
        payable(a.tenant).transfer(a.deposit);
        emit AgreementEnded(id);
    }

    function toggleAutoRenew(uint id, bool state) external onlyTenant(id) {
        agreements[id].autoRenew = state;
    }

    // -------- Contractor --------
    function addContractor(address addr, string memory skill) external onlyAdmin {
        contractors[++nextContractorId] = Contractor(addr, skill, false, false);
    }

    function assignContractor(uint id, uint cId) external onlyAdmin {
        Agreement storage a = agreements[id];
        require(a.active, "Inactive");
        require(!contractors[cId].assigned, "Already assigned");
        a.contractorId = cId;
        contractors[cId].assigned = true;
        emit ContractorAssigned(id, contractors[cId].addr);
    }

    function markContractorDone(uint id) external {
        Contractor storage c = contractors[agreements[id].contractorId];
        require(msg.sender == c.addr, "Not contractor");
        c.done = true;
        emit ContractorDone(id);
    }

    // -------- Rent Insurance --------
    function buyInsurance(uint id) external payable whenNotPaused onlyTenant(id) {
        require(!insurance[msg.sender].active, "Already insured");
        require(msg.value > 0, "Zero premium");
        uint cover = agreements[id].rent;
        insurance[msg.sender] = RentInsurance(true, msg.value, cover, false);
        insurancePool += msg.value;
        emit InsuranceBought(msg.sender, msg.value);
    }

    function fundInsurancePool() external payable onlyAdmin { insurancePool += msg.value; }

    function claimInsurance(uint id) external nonReentrant whenNotPaused onlyTenant(id) {
        Agreement storage a = agreements[id];
        RentInsurance storage ins = insurance[msg.sender];
        require(ins.active && !ins.claimed, "Invalid");
        require(block.timestamp > a.lastPayment + SECONDS_IN_MONTH + (a.graceDays * 1 days), "Too early");
        require(insurancePool >= ins.coverage, "Low pool");

        ins.active = false; ins.claimed = true;
        insurancePool -= ins.coverage;
        payable(a.landlord).transfer(ins.coverage);
        emit InsuranceClaimed(msg.sender, ins.coverage);
    }

    function cancelInsurance(uint id) external nonReentrant onlyTenant(id) {
        Agreement memory a = agreements[id];
        RentInsurance storage ins = insurance[msg.sender];
        require(!a.active && ins.active && !ins.claimed, "Invalid");
        ins.active = false; ins.claimed = true;
        uint refund = ins.premium / 2;
        payable(msg.sender).transfer(refund);
    }

    // -------- Admin --------
    function pause() external onlyAdmin { _pause(); }
    function unpause() external onlyAdmin { _unpause(); }
    function withdrawFees(address to) external onlyAdmin {
        uint amt = totalPlatformFees; totalPlatformFees = 0; payable(to).transfer(amt);
    }
}
