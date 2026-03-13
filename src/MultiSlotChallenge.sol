// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
 
/*
    ============================================================
    Minimal ERC20 Interface
    ============================================================
 
    We only need three ERC20 functions from the USDC token:
 
    balanceOf()     → check wallet balance
    transfer()      → send tokens
    transferFrom()  → pull tokens from user after approval
*/
 
interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
 
    function transfer(address to, uint256 amount) external returns (bool);
 
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
 
 
/*
    ============================================================
    MultiSlotChallenge
    ============================================================
 
    This contract implements a simple on-chain trading challenge.
 
    Basic flow
    ----------
 
    1. Owner deposits USDC rewards into the contract.
 
    2. Owner whitelists trader wallets.
 
    3. Trader starts a challenge:
       - pays $10 fee
       - fee is immediately sent to feeRecipient
       - contract records trader’s USDC balance after fee
       - contract reserves a $50 reward
 
    4. Trader passes if their wallet USDC balance doubles.
 
       Example:
       Trader had 70 USDC.
       Pays 10 USDC fee.
       Remaining balance = 60.
 
       Pass target = 120 USDC.
 
    5. Trader claims reward.
 
    6. If challenge expires, reserved reward is released.
 
    ------------------------------------------------------------
 
    Design goals of this contract:
 
    - Extremely easy to read
    - Simple on-chain accounting
    - Deterministic reward payouts
    - Fully auditable behaviour
*/
 
contract MultiSlotChallenge {
 
    // ============================================================
    //                         CONFIGURATION
    // ============================================================
 
    /// Address that deployed the contract.
    /// Has administrative powers such as whitelisting users.
    address public immutable owner;
 
    /// Address that receives challenge fees.
    address public feeRecipient;
 
    /// ERC20 token used for fees and rewards (USDC).
    IERC20 public immutable usdc;
 
    /*
        Monetary parameters.
 
        USDC uses 6 decimals.
 
        $10 = 10_000_000
        $50 = 50_000_000
    */
 
    uint256 public fee;      // Challenge entry fee
    uint256 public reward;   // Reward paid if trader passes
 
    /// Challenge duration in seconds.
    uint256 public duration;
 
    /// Maximum number of challenges any wallet may start.
    uint256 public maxChallengesPerWallet = 3;
 
    /*
        Minimum balance required after paying the fee.
 
        Prevents trivial pass conditions if wallet becomes empty.
    */
 
    uint256 public constant MIN_REMAINING_BALANCE = 1_000_000; // $1
 
 
    // ============================================================
    //                   WHITELIST AND LIMITS
    // ============================================================
 
    /// Only whitelisted wallets may start challenges.
    mapping(address => bool) public allowed;
 
    /// Track how many challenges each wallet has started.
    mapping(address => uint256) public challengesStarted;
 
 
    // ============================================================
    //                   REWARD POOL ACCOUNTING
    // ============================================================
 
    /*
        rewardPool
 
        Total USDC currently held for rewards.
 
        This increases when the owner deposits funds.
        It decreases when rewards are paid out.
    */
 
    uint256 public rewardPool;
 
    /*
        activeRewardReserved
 
        Portion of rewardPool reserved for active challenges.
 
        Prevents oversubscribing the reward pool.
    */
 
    uint256 public activeRewardReserved;
 
 
    // ============================================================
    //                       CHALLENGE STORAGE
    // ============================================================
 
    struct Challenge {
 
        /// Trader wallet address
        address player;
 
        /// USDC balance immediately after fee payment
        uint256 startBalanceAfterFee;
 
        /// Block timestamp when challenge began
        uint256 startTime;
 
        /// Whether challenge is still active
        bool active;
 
        /// Snapshot values (protects against config changes)
        uint256 rewardSnap;
        uint256 durationSnap;
    }
 
    /// Auto-incrementing challenge ID counter
    uint256 public nextChallengeId = 1;
 
    /// Storage mapping of challengeId → challenge data
    mapping(uint256 => Challenge) public challenges;
 
 
    // ============================================================
    //                           EVENTS
    // ============================================================
 
    event ConfigUpdated(address feeRecipient, uint256 fee, uint256 reward, uint256 duration);
 
    event AllowedSet(address indexed wallet, bool isAllowed);
 
    event RewardsToppedUp(address indexed from, uint256 amount, uint256 newRewardPool);
 
    event RewardsWithdrawn(address indexed to, uint256 amount);
 
    event ChallengeStarted(
        uint256 indexed challengeId,
        address indexed player,
        uint256 startBalanceAfterFee,
        uint256 startTime,
        uint256 feePaid,
        uint256 rewardReserved
    );
 
    event ChallengeEnded(
        uint256 indexed challengeId,
        address indexed player,
        bool paidOut,
        uint256 payout,
        string reason
    );
 
 
    // ============================================================
    //                          MODIFIERS
    // ============================================================
 
    /// Restricts function execution to owner only.
    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }
 
 
    // ============================================================
    //                        CONSTRUCTOR
    // ============================================================
 
    constructor(
        address _usdc,
        address _feeRecipient,
        uint256 _fee,
        uint256 _reward,
        uint256 _duration
    ) {
        require(_usdc != address(0), "bad usdc");
        require(_feeRecipient != address(0), "bad feeRecipient");
 
        owner = msg.sender;
 
        usdc = IERC20(_usdc);
 
        feeRecipient = _feeRecipient;
 
        fee = _fee;
        reward = _reward;
        duration = _duration;
 
        emit ConfigUpdated(_feeRecipient, _fee, _reward, _duration);
    }
 
 
    // ============================================================
    //                         VIEW FUNCTIONS
    // ============================================================
 
    /*
        Returns the amount of reward capital currently free
        to allocate to new challenges.
    */
 
    function availableRewardPool() public view returns (uint256) {
 
        if (rewardPool <= activeRewardReserved) {
            return 0;
        }
 
        return rewardPool - activeRewardReserved;
    }
 
    /*
        Calculates how many new challenges can start
        with the currently available reward capital.
    */
 
    function availableSlots() external view returns (uint256) {
 
        if (reward == 0) return 0;
 
        return availableRewardPool() / reward;
    }
 
    /*
        Returns true if a challenge has expired.
    */
 
    function isExpired(uint256 challengeId) public view returns (bool) {
 
        Challenge storage c = challenges[challengeId];
 
        if (!c.active) return false;
 
        return block.timestamp > c.startTime + c.durationSnap;
    }
 
    /*
        Calculates the wallet balance required to pass.
 
        Pass condition = 2 × starting balance.
    */
 
    function passTarget(uint256 challengeId) public view returns (uint256) {
 
        Challenge storage c = challenges[challengeId];
 
        return c.startBalanceAfterFee * 2;
    }
 
 
    // ============================================================
    //                      OWNER ADMIN FUNCTIONS
    // ============================================================
 
    function setAllowed(address wallet, bool isAllowed) external onlyOwner {
 
        allowed[wallet] = isAllowed;
 
        emit AllowedSet(wallet, isAllowed);
    }
 
    /*
        Owner deposits USDC reward capital.
 
        Requires the owner to approve this contract first.
    */
 
    function topUpRewards(uint256 amount) external onlyOwner {
 
        require(amount > 0, "amount=0");
 
        bool ok = usdc.transferFrom(msg.sender, address(this), amount);
 
        require(ok, "transferFrom failed");
 
        rewardPool += amount;
 
        emit RewardsToppedUp(msg.sender, amount, rewardPool);
    }
 
    /*
        Owner can withdraw only unreserved reward funds.
    */
 
    function withdrawUnreservedRewards(uint256 amount, address to) external onlyOwner {
 
        require(amount <= availableRewardPool(), "amount > available");
 
        rewardPool -= amount;
 
        bool ok = usdc.transfer(to, amount);
 
        require(ok, "transfer failed");
 
        emit RewardsWithdrawn(to, amount);
    }
 
 
    // ============================================================
    //                        USER FLOW
    // ============================================================
 
    function startChallenge() external returns (uint256 challengeId) {
 
        require(allowed[msg.sender], "not whitelisted");
 
        require(
            challengesStarted[msg.sender] < maxChallengesPerWallet,
            "max challenges reached"
        );
 
        require(availableRewardPool() >= reward, "insufficient rewards");
 
        /*
            Pull fee from trader wallet.
 
            Trader must approve this contract first.
        */
 
        bool okPull = usdc.transferFrom(msg.sender, address(this), fee);
 
        require(okPull, "fee transferFrom failed");
 
        /*
            Immediately forward fee to feeRecipient.
        */
 
        bool okFee = usdc.transfer(feeRecipient, fee);
 
        require(okFee, "fee transfer failed");
 
        /*
            Record trader balance after paying fee.
        */
 
        uint256 remaining = usdc.balanceOf(msg.sender);
 
        require(
            remaining >= MIN_REMAINING_BALANCE,
            "must have at least $1 remaining"
        );
 
        /*
            Reserve reward for this challenge.
        */
 
        activeRewardReserved += reward;
 
        challengeId = nextChallengeId++;
 
        Challenge storage c = challenges[challengeId];
 
        c.player = msg.sender;
        c.startBalanceAfterFee = remaining;
        c.startTime = block.timestamp;
        c.active = true;
 
        c.rewardSnap = reward;
        c.durationSnap = duration;
 
        challengesStarted[msg.sender] += 1;
 
        emit ChallengeStarted(
            challengeId,
            msg.sender,
            remaining,
            c.startTime,
            fee,
            reward
        );
    }
 
 
    /*
        Anyone can finalize an expired challenge.
 
        This releases the reserved reward back into the pool.
    */
 
    function finalizeIfExpired(uint256 challengeId) external {
 
        Challenge storage c = challenges[challengeId];
 
        require(c.active, "no active challenge");
 
        require(isExpired(challengeId), "not expired");
 
        address oldPlayer = c.player;
 
        uint256 r = c.rewardSnap;
 
        _resetChallenge(c);
 
        activeRewardReserved -= r;
 
        emit ChallengeEnded(challengeId, oldPlayer, false, 0, "expired");
    }
 
 
    /*
        Trader claims reward if pass target reached.
    */
 
    function claimReward(uint256 challengeId) external {
 
        Challenge storage c = challenges[challengeId];
 
        require(c.active, "no active challenge");
 
        require(msg.sender == c.player, "not player");
 
        require(!isExpired(challengeId), "expired");
 
        uint256 currentBalance = usdc.balanceOf(msg.sender);
 
        uint256 target = c.startBalanceAfterFee * 2;
 
        require(currentBalance >= target, "target not met");
 
        address winner = c.player;
 
        uint256 r = c.rewardSnap;
 
        _resetChallenge(c);
 
        activeRewardReserved -= r;
 
        rewardPool -= r;
 
        bool okPay = usdc.transfer(winner, r);
 
        require(okPay, "reward transfer failed");
 
        emit ChallengeEnded(challengeId, winner, true, r, "passed");
    }
 
 
    // ============================================================
    //                       INTERNAL HELPERS
    // ============================================================
 
    function _resetChallenge(Challenge storage c) internal {
 
        c.player = address(0);
 
        c.startBalanceAfterFee = 0;
 
        c.startTime = 0;
 
        c.active = false;
 
        c.rewardSnap = 0;
 
        c.durationSnap = 0;
    }
}

