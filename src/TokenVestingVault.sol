// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
}

library VestingMath {
    function vestedAmount(
        uint256 total,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        uint256 currentTime
    ) internal pure returns (uint256) {
        if (currentTime < cliff) return 0;
        if (currentTime >= start + duration) return total;
        return total * (currentTime - start) / duration;
    }
}

contract TokenVestingVault {
    using VestingMath for uint256;

    address public owner;

    struct Schedule {
        address token;
        address beneficiary;
        uint256 totalAmount;
        uint256 start;
        uint256 cliff;
        uint256 duration;
        uint256 claimed;
        bool revocable;
        bool revoked;
    }

    uint256 public scheduleCount;
    mapping(uint256 => Schedule) public schedules;

    event ScheduleCreated(
        uint256 indexed id,
        address indexed beneficiary,
        address token,
        uint256 totalAmount,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        bool revocable
    );
    event TokensClaimed(uint256 indexed id, address indexed beneficiary, uint256 amount);
    event ScheduleRevoked(uint256 indexed id, uint256 vestedAmount, uint256 returnedAmount);

    error NotOwner();
    error NotBeneficiary();
    error ZeroAddress();
    error ZeroAmount();
    error InvalidSchedule();
    error AlreadyRevoked();
    error NotRevocable();
    error NothingToClaim();
    error TransferFailed();

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function createSchedule(
        address token,
        address beneficiary,
        uint256 totalAmount,
        uint256 start,
        uint256 cliffDuration,
        uint256 duration,
        bool revocable
    ) external onlyOwner returns (uint256 id) {
        if (token == address(0) || beneficiary == address(0)) revert ZeroAddress();
        if (totalAmount == 0) revert ZeroAmount();
        if (duration == 0 || cliffDuration > duration) revert InvalidSchedule();

        uint256 cliff = start + cliffDuration;

        bool ok = IERC20(token).transferFrom(msg.sender, address(this), totalAmount);
        if (!ok) revert TransferFailed();

        scheduleCount++;
        id = scheduleCount;

        schedules[id] = Schedule({
            token: token,
            beneficiary: beneficiary,
            totalAmount: totalAmount,
            start: start,
            cliff: cliff,
            duration: duration,
            claimed: 0,
            revocable: revocable,
            revoked: false
        });

        emit ScheduleCreated(id, beneficiary, token, totalAmount, start, cliff, duration, revocable);
    }

	function claim(uint256 id) external {
    Schedule storage s = schedules[id];

    if (msg.sender != s.beneficiary) revert NotBeneficiary();
    if (s.revoked) revert AlreadyRevoked();

    uint256 vested = VestingMath.vestedAmount(
        s.totalAmount,
        s.start,
        s.cliff,
        s.duration,
        block.timestamp
    );

    uint256 claimableAmount = vested - s.claimed;
    if (claimableAmount == 0) revert NothingToClaim();

    s.claimed += claimableAmount;

    bool ok = IERC20(s.token).transfer(s.beneficiary, claimableAmount);
    if (!ok) revert TransferFailed();

    emit TokensClaimed(id, s.beneficiary, claimableAmount);
	}


    function revoke(uint256 id) external onlyOwner {
        Schedule storage s = schedules[id];

        if (!s.revocable) revert NotRevocable();
        if (s.revoked) revert AlreadyRevoked();

        uint256 vested = VestingMath.vestedAmount(
            s.totalAmount,
            s.start,
            s.cliff,
            s.duration,
            block.timestamp
        );

        uint256 unvested = s.totalAmount - vested;
        uint256 claimableByBeneficiary = vested - s.claimed;

        s.revoked = true;

        if (claimableByBeneficiary > 0) {
            bool ok1 = IERC20(s.token).transfer(s.beneficiary, claimableByBeneficiary);
            if (!ok1) revert TransferFailed();
        }

        if (unvested > 0) {
            bool ok2 = IERC20(s.token).transfer(owner, unvested);
            if (!ok2) revert TransferFailed();
        }

        emit ScheduleRevoked(id, vested, unvested);
    }

    function claimable(uint256 id) external view returns (uint256) {
        Schedule storage s = schedules[id];
        if (s.revoked) return 0;

        uint256 vested = VestingMath.vestedAmount(
            s.totalAmount,
            s.start,
            s.cliff,
            s.duration,
            block.timestamp
        );

        return vested - s.claimed;
    }
}
