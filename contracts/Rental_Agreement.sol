// ✅ NEW FUNCTIONALITY: Tenant Review System
struct LandlordReview {
    uint256 agreementId;
    address tenant;
    string reviewComment;
    uint8 rating; // Rating out of 5
    uint256 timestamp;
}

mapping(address => LandlordReview[]) public landlordReviews;

event LandlordReviewed(
    address indexed landlord,
    address indexed tenant,
    uint256 agreementId,
    uint8 rating,
    string review
);

function submitLandlordReview(
    uint256 _agreementId,
    string calldata _reviewComment,
    uint8 _rating
) external whenNotPaused onlyTenant(_agreementId) {
    Agreement memory a = agreements[_agreementId];
    require(!a.isActive, "Agreement must be ended to review");
    require(_rating > 0 && _rating <= 5, "Invalid rating (1-5)");

    landlordReviews[a.landlord].push(LandlordReview({
        agreementId: _agreementId,
        tenant: msg.sender,
        reviewComment: _reviewComment,
        rating: _rating,
        timestamp: block.timestamp
    }));

    emit LandlordReviewed(a.landlord, msg.sender, _agreementId, _rating, _reviewComment);
}

// ✅ Helper Function to Fetch All Reviews for a Landlord
function getLandlordReviews(address _landlord)
    external
    view
    returns (LandlordReview[] memory)
{
    return landlordReviews[_landlord];
}

