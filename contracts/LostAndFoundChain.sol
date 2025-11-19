// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/**
 * @title Blockchain + AI Lost & Found Platform
 * @author Muhammad Mateen Sadiq – 2025
 */
contract LostAndFoundChain {
    address public owner;
    uint256 public reportCount;

    enum ReportType { Lost, Found }
    enum ReportStatus { Open, Matched, Claimed, Closed }

    struct Report {
        uint256 id;
        address reporter;
        ReportType reportType;
        string itemCategory;           // e.g., "backpack", "laptop"
        string description;
        string ipfsImageHash;          // CID of image stored on IPfs
        bytes32 aiFeatureHash;         // keccak256 of AI embedding / probabilities
        uint256 aiConfidence;          // multiplied by 10000 (e.g., 0.91 → 9100)
        string location;
        uint256 timestamp;
        ReportStatus status;
        uint256 matchedWith;           // report ID of the counterpart
    }

    // All reports
    mapping(uint256 => Report) public reports;
    // Potential matches emitted as events (off-chain matcher listens)
    event PotentialMatch(uint256 lostId, uint256 foundId, uint256 score);
    event ReportCreated(uint256 id, ReportType reportType, address reporter);
    event ClaimInitiated(uint256 lostId, uint256 foundId, address claimant);
    event ItemReturned(uint256 lostId, uint256 foundId);

    uint256 public constant MATCH_THRESHOLD = 8500; // 0.85 confidence minimum
    uint256 public constant REWARD_TOKENS = 10 ether; // example incentive

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    /**
     * @dev Create a lost or found report
     * @param _type 0 = Lost, 1 = Found
     * @param _category AI-predicted category
     * @param _description Text description
     * @param _ipfsHash IPFS CID of photo
     * @param _aiFeatureHash keccak256 of AI embedding vector or probabilities
     * @param _aiConfidence Confidence × 10000
     * @param _location GPS or textual location
     */
    function createReport(
        ReportType _type,
        string memory _category,
        string memory _description,
        string memory _ipfsHash,
        bytes32 _aiFeatureHash,
        uint256 _aiConfidence,
        string memory _location
    ) external returns (uint256) {
        require(_aiConfidence <= 10000, "Confidence > 100%");

        reportCount++;
        reports[reportCount] = Report(
            reportCount,
            msg.sender,
            _type,
            _category,
            _description,
            _ipfsHash,
            _aiFeatureHash,
            _aiConfidence,
            _location,
            block.timestamp,
            ReportStatus.Open,
            0
        );

        emit ReportCreated(reportCount, _type, msg.sender);
        // Off-chain service will call checkForMatches()
        return reportCount;
    }

    /**
     * @dev Called by off-chain AI matcher after new report
     */
    function checkForMatches(uint256 _newReportId) external {
        Report memory newRep = reports[_newReportId];

        for (uint256 i = 1; i < reportCount; i++) {
            if (i == _newReportId) continue;
            Report memory rep = reports[i];

            // Opposite type only
            if (rep.reportType == newRep.reportType) continue;
            if (rep.status != ReportStatus.Open) continue;

            // Simple category + confidence filter
            if (
                keccak256(bytes(rep.itemCategory)) == keccak256(bytes(newRep.itemCategory)) &&
                rep.aiConfidence >= MATCH_THRESHOLD &&
                newRep.aiConfidence >= MATCH_THRESHOLD
            ) {
                // Advanced similarity could compare _aiFeatureHash with cosine similarity off-chain
                uint256 similarityScore = _calculateScore(rep.aiFeatureHash, newRep.aiFeatureHash, rep.aiConfidence, newRep.aiConfidence);

                if (similarityScore >= MATCH_THRESHOLD) {
                    emit PotentialMatch(
                        newRep.reportType == ReportType.Lost ? _newReportId : i,
                        newRep.reportType == ReportType.Found ? _newReportId : i,
                        similarityScore
                    );
                }
            }
        }
    }

    // Simplified score – real implementation would use off-chain vector DB
    function _calculateScore(
        bytes32 hash1,
        bytes32 hash2,
        uint256 conf1,
        uint256 conf2
    ) internal pure returns (uint256) {
        // Placeholder – in production use oracle or ZK-proof of cosine similarity
        uint256 base = uint256(keccak256(abi.encodePacked(hash1, hash2))) % 3000;
        return 7000 + base + (conf1 + conf2) / 200;
    }

    /**
     * @dev Owner of lost item initiates claim after receiving PotentialMatch event
     */
    function initiateClaim(uint256 _lostId, uint256 _foundId) external {
        Report storage lost = reports[_lostId];
        Report storage found = reports[_foundId];

        require(lost.reportType == ReportType.Lost, "First must be Lost");
        require(found.reportType == ReportType.Found, "Second must be Found");
        require(lost.reporter == msg.sender, "Only owner can claim");

        lost.status = ReportStatus.Matched;
        found.status = ReportStatus.Matched;
        lost.matchedWith = _foundId;
        found.matchedWith = _lostId;

        emit ClaimInitiated(_lostId, _foundId, msg.sender);
    }

    /**
     * @dev Finder confirms handover → reward + reward (optional ERC20)
     */
    function confirmHandover(uint256 _lostId, uint256 _foundId) external {
        require(
            reports[_lostId].matchedWith == _foundId &&
            reports[_foundId].matchedWith == _lostId,
            "Not matched"
        );
        require(
            msg.sender == reports[_lostId].reporter ||
            msg.sender == reports[_foundId].reporter,
            "Only parties"
        );

        reports[_lostId].status = ReportStatus.Claimed;
        reports[_foundId].status = ReportStatus.Closed;

        emit ItemReturned(_lostId, _foundId);
        // Here you can mint reward tokens to finder
    }

    // View functions
    function getReport(uint256 _id) external view returns (Report memory) {
        return reports[_id];
    }
}