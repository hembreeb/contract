// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/IWFIL.sol";

contract FairAuction is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using Address for address;

    struct UserInfo {
        uint256 allocation; // amount taken into account to obtain TOKEN (amount spent + discount)
        uint256 contribution; // amount spent to buy TOKEN
        bool hasClaimed; // has already claimed its allocation
    }

    IERC20 public immutable PROJECT_TOKEN; // Project token contract
    IERC20 public immutable SALE_TOKEN; // token used to participate

    uint256 public immutable START_TIME; // sale start time
    uint256 public immutable END_TIME; // sale end time

    uint256 public constant REFERRAL_SHARE = 3; // 3%

    mapping(address => UserInfo) public userInfo; // buyers and referrers info
    uint256 public totalRaised; // raised amount, does not take into account referral shares
    uint256 public totalAllocation; // takes into account discounts

    uint256 public immutable MAX_PROJECT_TOKENS_TO_DISTRIBUTE; // max PROJECT_TOKEN amount to distribute during the sale
    uint256 public immutable MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN; // amount to reach to distribute max PROJECT_TOKEN amount

    uint256 public immutable MAX_RAISE_AMOUNT;
    uint256 public immutable CAP_PER_WALLET;

    address public immutable treasury; // treasury multisig, will receive raised amount

    bool public unsoldTokensBurnt;
    address public wfil = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; //This is not a real address. If the sale token is the same as this address, it means that only fil is accepted

    constructor(
        IERC20 projectToken,
        IERC20 saleToken,
        uint256 startTime,
        uint256 endTime,
        address treasury_,
        uint256 maxToDistribute,
        uint256 minToRaise,
        uint256 maxToRaise,
        uint256 capPerWallet
    ) {
        require(startTime < endTime, "invalid dates");
        require(treasury_ != address(0), "invalid treasury");
        PROJECT_TOKEN = projectToken;
        SALE_TOKEN = saleToken;
        START_TIME = startTime;
        END_TIME = endTime;
        treasury = treasury_;
        MAX_PROJECT_TOKENS_TO_DISTRIBUTE = maxToDistribute;
        MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN = minToRaise;
        if (maxToRaise == 0) {
            maxToRaise = type(uint256).max;
        }
        MAX_RAISE_AMOUNT = maxToRaise;
        if (capPerWallet == 0) {
            capPerWallet = type(uint256).max;
        }
        CAP_PER_WALLET = capPerWallet;
    }

    /********************************************/
    /****************** EVENTS ******************/
    /********************************************/

    event Buy(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);
    event EmergencyWithdraw(address token, uint256 amount);

    /***********************************************/
    /****************** MODIFIERS ******************/
    /***********************************************/
    /**
     * @dev Check whether the sale is currently active
     *
     * Will be marked as inactive if PROJECT_TOKEN has not been deposited into the contract
     */
    modifier isSaleActive() {
        require(
            hasStarted() &&
                !hasEnded() &&
                PROJECT_TOKEN.balanceOf(address(this)) >=
                MAX_PROJECT_TOKENS_TO_DISTRIBUTE,
            "isActive: sale is not active"
        );
        _;
    }

    /**
     * @dev Check whether users can claim their purchased PROJECT_TOKEN
     *
     * Sale must have ended, and LP tokens must have been formed
     */
    modifier isClaimable() {
        require(hasEnded(), "isClaimable: sale has not ended");
        _;
    }

    /**************************************************/
    /****************** PUBLIC VIEWS ******************/
    /**************************************************/

    /**
     * @dev Get remaining duration before the end of the sale
     */
    function getRemainingTime() external view returns (uint256) {
        if (hasEnded()) return 0;
        return END_TIME.sub(_currentBlockTimestamp());
    }

    /**
     * @dev Returns whether the sale has already started
     */
    function hasStarted() public view returns (bool) {
        return _currentBlockTimestamp() >= START_TIME;
    }

    /**
     * @dev Returns whether the sale has already ended
     */
    function hasEnded() public view returns (bool) {
        return END_TIME <= _currentBlockTimestamp();
    }

    /**
     * @dev Returns the amount of PROJECT_TOKEN to be distributed based on the current total raised
     */
    function tokensToDistribute() public view returns (uint256) {
        if (MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN > totalRaised) {
            return
                MAX_PROJECT_TOKENS_TO_DISTRIBUTE.mul(totalRaised).div(
                    MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN
                );
        }
        return MAX_PROJECT_TOKENS_TO_DISTRIBUTE;
    }

    /**
     * @dev Get user share times 1e5
     */
    function getExpectedClaimAmount(
        address account
    ) public view returns (uint256) {
        if (totalAllocation == 0) return 0;

        UserInfo memory user = userInfo[account];
        return user.allocation.mul(tokensToDistribute()).div(totalAllocation);
    }

    /****************************************************************/
    /****************** EXTERNAL PUBLIC FUNCTIONS  ******************/
    /****************************************************************/

    function buyFIL(
        address referralAddress
    ) external payable isSaleActive nonReentrant {
        require(address(SALE_TOKEN) == wfil, "non fil sale");
        uint256 amount = msg.value;
        _buy(amount, referralAddress);
    }

    /**
     * @dev Purchase an allocation for the sale for a value of "amount" SALE_TOKEN, referred by "referralAddress"
     */
    function buy(
        uint256 amount,
        address referralAddress
    ) external isSaleActive nonReentrant {
        require(address(SALE_TOKEN) != wfil, "token is not supported");
        SALE_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        _buy(amount, referralAddress);
    }

    function _buy(uint256 amount, address referralAddress) internal {
        require(amount > 0, "buy: zero amount");
        require(
            totalRaised.add(amount) <= MAX_RAISE_AMOUNT,
            "buy: hardcap reached"
        );
        require(
            !address(msg.sender).isContract() &&
                !address(tx.origin).isContract(),
            "FORBIDDEN"
        );

        uint256 participationAmount = amount;
        UserInfo storage user = userInfo[msg.sender];
        require(
            user.contribution.add(amount) <= CAP_PER_WALLET,
            "buy: wallet cap reached"
        );

        uint256 allocation = amount;

        // update raised amounts
        user.contribution = user.contribution.add(amount);
        totalRaised = totalRaised.add(amount);

        // update allocations
        user.allocation = user.allocation.add(allocation);
        totalAllocation = totalAllocation.add(allocation);

        emit Buy(msg.sender, amount);
        // transfer contribution to treasury
        if (address(SALE_TOKEN) != wfil) {
            SALE_TOKEN.safeTransfer(treasury, participationAmount);
        } else {
            (bool success, ) = treasury.call{value: participationAmount}("");
            require(success, "transfer failed");
        }
    }

    /**
     * @dev Claim purchased PROJECT_TOKEN during the sale
     */
    function claim() external isClaimable nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        require(
            totalAllocation > 0 && user.allocation > 0,
            "claim: zero allocation"
        );
        require(!user.hasClaimed, "claim: already claimed");
        user.hasClaimed = true;

        uint256 amount = getExpectedClaimAmount(msg.sender);

        emit Claim(msg.sender, amount);
        // send PROJECT_TOKEN allocation
        _safeClaimTransfer(msg.sender, amount);
    }

    /****************************************************************/
    /********************** OWNABLE FUNCTIONS  **********************/
    /****************************************************************/

    /********************************************************/
    /****************** /!\ EMERGENCY ONLY ******************/
    /********************************************************/

    /**
     * @dev Failsafe
     */
    function emergencyWithdrawFunds(
        address token,
        uint256 amount
    ) external onlyOwner {
        if (token != wfil) {
            IERC20(token).safeTransfer(msg.sender, amount);
        } else {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "transfer failed");
        }

        emit EmergencyWithdraw(token, amount);
    }

    /**
     * @dev Burn unsold PROJECT_TOKEN if MIN_TOTAL_RAISED_FOR_MAX_PROJECT_TOKEN has not been reached
     *
     * Must only be called by the owner
     */
    function burnUnsoldTokens() external onlyOwner {
        require(hasEnded(), "burnUnsoldTokens: presale has not ended");
        require(!unsoldTokensBurnt, "burnUnsoldTokens: already burnt");

        uint256 totalSold = tokensToDistribute();
        require(
            totalSold < MAX_PROJECT_TOKENS_TO_DISTRIBUTE,
            "burnUnsoldTokens: no token to burn"
        );

        unsoldTokensBurnt = true;
        PROJECT_TOKEN.transfer(
            0x000000000000000000000000000000000000dEaD,
            MAX_PROJECT_TOKENS_TO_DISTRIBUTE.sub(totalSold)
        );
    }

    /********************************************************/
    /****************** INTERNAL FUNCTIONS ******************/
    /********************************************************/

    /**
     * @dev Safe token transfer function, in case rounding error causes contract to not have enough tokens
     */
    function _safeClaimTransfer(address to, uint256 amount) internal {
        uint256 balance = PROJECT_TOKEN.balanceOf(address(this));
        bool transferSuccess = false;

        if (amount > balance) {
            transferSuccess = PROJECT_TOKEN.transfer(to, balance);
        } else {
            transferSuccess = PROJECT_TOKEN.transfer(to, amount);
        }
        require(transferSuccess, "safeClaimTransfer: Transfer failed");
    }

    /**
     * @dev Utility function to get the current block timestamp
     */
    function _currentBlockTimestamp() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}
