pragma solidity ^0.4.20;

import "./UfoodoToken.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./Pausable.sol";

contract SeedSale is Ownable, Pausable {
    using SafeMath for uint256;

    // Tokens that will be sold
    ufoodoToken public token;

    // Time in Unix timestamp
    // Start: 01-Apr-18 14:00:00 UTC
    uint256 public constant seedStartTime = 1522591200;
    // End: 31-May-18 14:00:00 UTC
    uint256 public constant seedEndTime = 1527775200;

    uint256 public seedSupply_ = 0;

    // Update all funds raised that are not validated yet, 140 ether from private sale already added
    uint256 public fundsRaised = 140 ether;

    // Update only funds validated, 140 ether from private sale already added
    uint256 public fundsRaisedFinalized = 140 ether; //

    // Lock tokens for team
    uint256 public releasedLockedAmount = 0;

    // All pending UFT which needs to validated before transfered to contributors
    uint256 public pendingUFT = 0;
    // Conclude UFT which are transferred to contributer if soft cap reached and contributor is validated
    uint256 public concludeUFT = 0;

    uint256 public constant softCap = 200 ether;
    uint256 public constant hardCap = 3550 ether;
    uint256 public constant minContrib = 0.1 ether;

    uint256 public lockedTeamUFT = 0;
    uint256 public privateReservedUFT = 0;

    // Will updated in condition with funds raised finalized
    bool public SoftCapReached = false;
    bool public hardCapReached = false;
    bool public seedSaleFinished = false;

    //Refund will enabled if seed sale End and min cap not reached
    bool public refundAllowed = false;

    // Address where only validated funds will be transfered
    address public fundWallet = 0xf7d4C80DE0e2978A1C5ef3267F488B28499cD22E;

    // Amount of ether in wei, needs to be validated first
    mapping(address => uint256) public weiContributedPending;
    // Amount of ether in wei validated
    mapping(address => uint256) public weiContributedConclude;
    // Amount of UFT which will reserved first until the contributor is validated
    mapping(address => uint256) public pendingAmountUFT;

    event OpenTier(uint256 activeTier);
    event LogContributionPending(address contributor, uint256 amountWei, uint256 tokenAmount, uint256 activeTier, uint256 timestamp);
    event LogContributionConclude(address contributor, uint256 amountWei, uint256 tokenAmount, uint256 timeStamp);
    event ValidationFailed(address contributor, uint256 amountWeiRefunded, uint timestamp);

    // Initialized Tier
    uint public activeTier = 0;

    // Max ether per tier to collect
    uint256[8] public tierCap = [
        400 ether,
        420 ether,
        380 ether,
        400 ether,
        410 ether,
        440 ether,
        460 ether,
        500 ether
    ];

    // Based on 1 Ether = 12500
    // Tokenrate + tokenBonus = totalAmount the contributor received
    uint256[8] public tierTokens = [
        17500, //40%
        16875, //35%
        16250, //30%
        15625, //25%
        15000, //20%
        13750, //10%
        13125, //5%
        12500  //0%
    ];

    // Will be updated due wei contribution
    uint256[8] public activeFundRaisedTier = [
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0
    ];

    // Constructor
    function SeedSale(address _vault) public {
        token = ufoodoToken(_vault);
        privateReservedUFT = token.supplySeed().mul(4).div(100);
        lockedTeamUFT = token.supplySeed().mul(20).div(100);
        seedSupply_ = token.supplySeed();
    }

    function seedStarted() public view returns (bool) {
        return now >= seedStartTime;
    }

    function seedEnded() public view returns (bool) {
        return now >= seedEndTime || fundsRaised >= hardCap;
    }

    modifier checkContribution() {
        require(canContribute());
        _;
    }

    function canContribute() internal view returns(bool) {
        if(!seedStarted() || seedEnded()) {
            return false;
        }
        if(msg.value < minContrib) {
            return false;
        }
        return true;
    }

    // Fallback function
    function() payable public whenNotPaused {
        buyUFT(msg.sender);
    }

    // Process UFT contribution
    function buyUFT(address contributor) public whenNotPaused checkContribution payable {
        uint256 weiAmount = msg.value;
        uint256 refund = 0;
        uint256 _tierIndex = activeTier;
        uint256 _activeTierCap = tierCap[_tierIndex];
        uint256 _activeFundRaisedTier = activeFundRaisedTier[_tierIndex];

        require(_activeFundRaisedTier < _activeTierCap);

        // Checks Amoount of eth still can contributed to the active Tier
        uint256 tierCapOverSold = _activeTierCap.sub(_activeFundRaisedTier);

        // if contributer amount will oversold the active tier cap, partial
        // purchase will proceed, rest contributer amount will refunded to contributor
        if(tierCapOverSold < weiAmount) {
            weiAmount = tierCapOverSold;
            refund = msg.value.sub(weiAmount);

        }
        // Calculate the amount of tokens the Contributor will receive
        uint256 amountUFT = weiAmount.mul(tierTokens[_tierIndex]);

        // Update status
        fundsRaised = fundsRaised.add(weiAmount);
        activeFundRaisedTier[_tierIndex] = activeFundRaisedTier[_tierIndex].add(weiAmount);
        weiContributedPending[contributor] = weiContributedPending[contributor].add(weiAmount);
        pendingAmountUFT[contributor] = pendingAmountUFT[contributor].add(amountUFT);
        pendingUFT = pendingUFT.add(amountUFT);

        // partial process, refund rest value
        if(refund > 0) {
            msg.sender.transfer(refund);
        }

        emit LogContributionPending(contributor, weiAmount, amountUFT, _tierIndex, now);
    }

    function softCapReached() public returns (bool) {
        if (fundsRaisedFinalized >= softCap) {
            SoftCapReached = true;
            return true;
        }
        return false;
    }

    // Next Tier will increment manually and Paused by the team to guarantee safe transition
    // Initialized next tier if previous tier sold out
    // For contributor safety we pause the seedSale process
    function nextTier() onlyOwner public {
        require(paused == true);
        require(activeTier < 7);
        uint256 _tierIndex = activeTier;
        activeTier = _tierIndex +1;
        emit OpenTier(activeTier);
    }

    // Validation Update Process
    // After we finished the kyc process, we update each validated contributor and transfer if softCapReached the tokens
    // If the contributor is not validated due failed validation, the contributed wei amount will refundet back to the contributor
    function validationPassed(address contributor) onlyOwner public returns (bool) {
        require(contributor != 0x0);

        uint256 amountFinalized = pendingAmountUFT[contributor];
        pendingAmountUFT[contributor] = 0;
        token.transferFromVault(token, contributor, amountFinalized);

        // Update status
        uint256 _fundsRaisedFinalized = fundsRaisedFinalized.add(weiContributedPending[contributor]);
        fundsRaisedFinalized = _fundsRaisedFinalized;
        concludeUFT = concludeUFT.add(amountFinalized);

        weiContributedConclude[contributor] = weiContributedConclude[contributor].add(weiContributedPending[contributor]);

        emit LogContributionConclude(contributor, weiContributedPending[contributor], amountFinalized, now);
        softCapReached();
        // Amount finalized tokes update status

        return true;
    }

    // Update which address is not validated
    // By updating the address, the contributor will receive his contribution back
    function validationFailed(address contributor) onlyOwner public returns (bool) {
        require(contributor != 0x0);
        require(weiContributedPending[contributor] > 0);

        uint256 currentBalance = weiContributedPending[contributor];

        weiContributedPending[contributor] = 0;
        contributor.transfer(currentBalance);
        emit ValidationFailed(contributor, currentBalance, now);
        return true;
    }

    // If seed sale ends and soft cap is not reached, Contributer can claim their funds
    function refund() public {
        require(refundAllowed);
        require(!SoftCapReached);
        require(weiContributedPending[msg.sender] > 0);

        uint256 currentBalance = weiContributedPending[msg.sender];

        weiContributedPending[msg.sender] = 0;
        msg.sender.transfer(currentBalance);
    }


   // Allows only to refund the contributed amount that passed the validation and reached the softcap
    function withdrawFunds(uint256 _weiAmount) public onlyOwner {
        require(SoftCapReached);
        fundWallet.transfer(_weiAmount);
    }

    /*
     * If tokens left make a priveledge token sale for contributor that are already validated
     * make a new date time for left tokens only for priveledge whitelisted
     * If not enouhgt tokens left for a sale send directly to locked contract/ vault
     */
    function seedSaleTokenLeft(address _tokenContract) public onlyOwner {
        require(seedEnded());
        uint256 amountLeft = pendingUFT.sub(concludeUFT);
        token.transferFromVault(token, _tokenContract, amountLeft );
    }


    function vestingToken(address _beneficiary) public onlyOwner returns (bool) {
      require(SoftCapReached);
      uint256 release_1 = seedStartTime.add(180 days);
      uint256 release_2 = release_1.add(180 days);
      uint256 release_3 = release_2.add(180 days);
      uint256 release_4 = release_3.add(180 days);

      //20,000,000 UFT total splitted in 4 time periods
      uint256 lockedAmount_1 = lockedTeamUFT.mul(25).div(100);
      uint256 lockedAmount_2 = lockedTeamUFT.mul(25).div(100);
      uint256 lockedAmount_3 = lockedTeamUFT.mul(25).div(100);
      uint256 lockedAmount_4 = lockedTeamUFT.mul(25).div(100);

      if(seedStartTime >= release_1 && releasedLockedAmount < lockedAmount_1) {
        token.transferFromVault(token, _beneficiary, lockedAmount_1 );
        releasedLockedAmount = releasedLockedAmount.add(lockedAmount_1);
        return true;

      } else if(seedStartTime >= release_2 && releasedLockedAmount < lockedAmount_2.mul(2)) {
        token.transferFromVault(token, _beneficiary, lockedAmount_2 );
        releasedLockedAmount = releasedLockedAmount.add(lockedAmount_2);
        return true;

      } else if(seedStartTime >= release_3 && releasedLockedAmount < lockedAmount_3.mul(3)) {
        token.transferFromVault(token, _beneficiary, lockedAmount_3 );
        releasedLockedAmount = releasedLockedAmount.add(lockedAmount_3);
        return true;

      } else if(seedStartTime >= release_4 && releasedLockedAmount < lockedAmount_4.mul(4)) {
        token.transferFromVault(token, _beneficiary, lockedAmount_4 );
        releasedLockedAmount = releasedLockedAmount.add(lockedAmount_4);
        return true;
      }

    }

    // Total Reserved from Private Sale Contributor 4,000,000 UFT
    function transferPrivateReservedUFT(address _beneficiary, uint256 _amount) public onlyOwner {
        require(SoftCapReached);
        require(_amount > 0);
        require(privateReservedUFT >= _amount);

        token.transferFromVault(token, _beneficiary, _amount);
        privateReservedUFT = privateReservedUFT.sub(_amount);

    }

     function finalizeSeedSale() public onlyOwner {
        if(seedStartTime >= seedEndTime && SoftCapReached) {

        // Bounty Campaign: 5,000,000 UFT
        uint256 bountyAmountUFT = token.supplySeed().mul(5).div(100);
        token.transferFromVault(token, fundWallet, bountyAmountUFT);

        // Reserved Company: 20,000,000 UFT
        uint256 reservedCompanyUFT = token.supplySeed().mul(20).div(100);
        token.transferFromVault(token, fundWallet, reservedCompanyUFT);

        } else if(seedStartTime >= seedEndTime && !SoftCapReached) {

            // Enable fund`s crowdsale refund if soft cap is not reached
            refundAllowed = true;

            token.transferFromVault(token, owner, seedSupply_);
            seedSupply_ = 0;

        }
    }

}
