pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";


contract Escrow is ReentrancyGuard {

    using SafeERC20 for ERC20;

    /*
        This contract implements an escrow service for trading ERC20 tokens on the blockchain.
        Notably it allows the OTC sale of tokens that have not yet launched, in a secure and trustless manner.

        Seller:

        -Create an offer by calling createOffer(), specifying baseToken (the token you wish to receive), number of tokens to sell, 
        total sale value (the amount of baseToken you expect to receive in total), and a deadline.
        (Optional) Add the token address of the token to sell by calling addTokenAddress().
        -Deposit the tokens to sell by calling depositTokens().
        -If the offer is not fulfilled, the seller can cancel the offer (cancelOffer()) or back out (backOut()) after the deadline.

        Note: The deadline is specified in seconds since the Unix epoch, using the block.timestamp. For example, a deadline of 1 day is equivalent to 86400 seconds.
        In this example, the deadline would be up 86400 seconds after you create the Offer.


        Buyer:

        -Accept an offer by calling acceptOffer(), depositing the required baseToken amount.
        -Verify the token address provided by the seller using verifyTokenAddress().
        -If the offer conditions are met, either the buyer or seller can settle the offer by calling settleOffer().
        -If the other party has reneged on the deal, the buyer can back out (backOut()) after the deadline.
        
        IMPORTANT NOTE: Buyer must call acceptOffer(), passing the Offer id and a boolean. Ensuring that the _hasBuyerVerifiedAddress boolean parameter is set to FALSE.
        Setting to it TRUE will skip the required tx where the Buyer confirms the address given by the Seller

        ***-ONLY SET _hasBuyerVerifiedAddress TO TRUE IF YOU ARE 100% CERTAIN THE TOKEN BEING SUPPLIED BY THE SELLER IS CORRECT-***

        Note: Offers are secured by a 25% deposit from the seller (in baseToken). A 1% fee on the transaction value is charged to the seller.
        Note: All values are in wei. If you are using a token with a different decimal count than the standard 18, you must account for that.
    */

    uint256 public offerCount = 0;
    mapping(uint256 => Offer) public offers;
    mapping(address => uint256) public feesEarned;
    address public dev;

    event OfferCreated(uint256 indexed offerId, address tokenForSale, address tokenRequested, uint256 numberOfTokensForSale, uint256 totalSaleValue);
    event OfferAccepted(uint256 indexed offerId, address buyer);
    event OfferSettled(uint256 indexed offerId);
    event OfferCancelled(uint256 indexed offerId);
    event TokenAddressUpdated(uint256 indexed offerId, address tokenAddress);
    event OfferBackedOut(uint256 indexed offerId);

    constructor(address _dev){
        dev = _dev;
    }


    struct Offer {
        uint256 id;
        uint256 createdBlockTimestamp;
        address seller;
        address baseToken;
        address tokenAddress;
        bool tokenAddressVerified;
        uint256 numberOfTokensForSale;
        uint256 totalSaleValue;
        uint256 deadline;
        uint256 depositValue;
        bool isOpen;
        uint256 bidValue;
        address buyer;
        uint256 tokensDeposited;
    }

    
    /* Seller creates an offer to sell _tokenToSellAddress for _baseToken and puts up 25% of the sale value, as baseToken, as a deposit.
    Seller defines address of the baseToken they want to receive, and optionally the address of the token they are selling, the price per tokenToSell denominated in
    the baseToken. Lastly the Seller defines a deadline (timestamp) that, when passed, renders the Offer void. (i.e. 48 hours */

    function createOffer(address _baseToken, uint256 _numOfTokensToSell, uint256 _totalSaleValue, uint256 _deadline) public {
        _createOffer(msg.sender, _baseToken, address(0), _numOfTokensToSell, _totalSaleValue, _deadline);
    }
    function createOffer(address _baseToken, address _tokenToSellAddress, uint256 _numOfTokensToSell, uint256 _totalSaleValue, uint256 _deadline) public {
         _createOffer(msg.sender, _baseToken, _tokenToSellAddress, _numOfTokensToSell, _totalSaleValue, _deadline);
    }


    //above overloaded functions call below private Offer creation function
    function _createOffer(address _caller, address _baseToken, address _tokenToSellAddress, uint256 _numOfTokensToSell, uint256 _totalSaleValue, uint256 _deadline) private {
        require(_caller != address(0), "Seller address cannot be the zero address.");
        require(_numOfTokensToSell > 0 && _totalSaleValue > 0 && _deadline > 0 && _baseToken != address(0));
            ERC20 baseToken = ERC20(_baseToken);
            ERC20 token = ERC20(_tokenToSellAddress);
        baseToken.safeTransferFrom(_caller, address(this), getExpectedValueDeposit(_totalSaleValue));
        uint256 _depositedTokens = 0;
        if(_tokenToSellAddress != address(0)){
            uint256 preBal = token.balanceOf(address(this));
            token.safeTransferFrom(_caller, address(this), _numOfTokensToSell);
            _depositedTokens = token.balanceOf(address(this)) - preBal;
        }
            offerCount++;
            Offer memory userOffer = Offer(offerCount, block.timestamp, _caller, _baseToken, _tokenToSellAddress, false, _numOfTokensToSell, _totalSaleValue, _deadline, getExpectedValueDeposit(_totalSaleValue), true, 0, address(this), _depositedTokens);
            offers[offerCount] = userOffer;
                emit OfferCreated(userOffer.id, userOffer.tokenAddress, userOffer.baseToken, userOffer.numberOfTokensForSale, userOffer.totalSaleValue);
    }

    /*  Seller must add the token address of what they are selling. This is only possible if the Seller did NOT
        define an _tokenToSellAddress when creating the offer. It can only be called ONCE.  */
    function addTokenAddress(uint256 _id, address _tokenToSellAddress) public {
        require(_tokenToSellAddress != address(0));
        require(offers[_id].tokenAddress == address(0), "Token address has already been updated!");
        require(offers[_id].seller == msg.sender, "You are not the seller.");
        require(!hasDeadlinePassed(_id), "Deadline passed.");
            offers[_id].tokenAddress = _tokenToSellAddress;
                emit TokenAddressUpdated(_id, _tokenToSellAddress);
    }
    /*  The Buyer MUST verify the Seller's given address by calling this function. Buyer will pass the _expectedAddress in to ensure safety. 
        This step is required for the Offer to be able to get settled.*/
    function verifyTokenAddress(uint256 _id, address _expectedAddress) public {
        require(msg.sender == offers[_id].buyer, "Not the buyer.");
        require(offers[_id].isOpen, "Offer is closed.");
        require(!hasDeadlinePassed(_id), "Deadline passed.");
        if(offers[_id].tokenAddress == _expectedAddress){
            offers[_id].tokenAddressVerified = true;
        } else {
            offers[_id].tokenAddressVerified = false;
        }
    }

    //Seller must deposit the tokens they are selling AFTER buyer has verified the address
    function depositTokens(uint256 _id) public {
        require(offers[_id].isOpen, "Offer is closed.");
        require(!hasDeadlinePassed(_id), "Deadline passed.");
        require(offers[_id].tokenAddressVerified, "Token address not verified by buyer.");
        require(msg.sender == offers[_id].seller);
        require(offers[_id].tokenAddress != address(0));
            ERC20 token = ERC20(offers[_id].tokenAddress);
        token.safeTransferFrom(msg.sender, address(this), offers[_id].numberOfTokensForSale);
            offers[_id].tokensDeposited += offers[_id].numberOfTokensForSale;
    }

    //Buyer can accept offer by depositing the correct number of baseToken to an offer
    //_verifiedTokenAddress should be FALSE unless buyer is 100% certain
    function acceptOffer(uint256 _id, bool _hasBuyerVerifiedTokenAddress) public {
        require(msg.sender != address(0), "Buyer address cannot be the zero address.");
        require(offers[_id].isOpen, "Offer is closed.");
        require(!hasDeadlinePassed(_id), "Deadline passed.");
            ERC20 baseToken = ERC20(offers[_id].baseToken);
            uint256 preBal = baseToken.balanceOf(address(this));
            baseToken.safeTransferFrom(msg.sender, address(this), offers[_id].totalSaleValue);
            uint256 newBal = baseToken.balanceOf(address(this)) - preBal;
            offers[_id].bidValue = newBal;
            offers[_id].buyer = msg.sender;
            offers[_id].isOpen = false;
                emit OfferAccepted(_id, msg.sender);
            if(offers[_id].tokensDeposited >= offers[_id].numberOfTokensForSale && _hasBuyerVerifiedTokenAddress == true && offers[_id].bidValue >= offers[_id].totalSaleValue){
                offers[_id].tokenAddressVerified = true;
                settleOffer(_id);
            }
    }

    /*  Either seller or buyer can settle the Offer if the number of baseTokens deposited are >= to the sale offer AND the number tokensDeposited are >= the listed amount
        The Buyer MUST have verified the givenTokenAddress */
    function settleOffer(uint256 _id) public nonReentrant {
        require(!offers[_id].isOpen, "Offer is still open.");
        require(!hasDeadlinePassed(_id), "Deadline passed.");
        require(msg.sender == offers[_id].buyer || msg.sender == offers[_id].seller);
        require(offers[_id].tokensDeposited >= offers[_id].numberOfTokensForSale);
        require(offers[_id].bidValue >= offers[_id].totalSaleValue);
        require(offers[_id].tokenAddressVerified, "Token address not verified by buyer.");
        
        _transferTokensAndSettle(_id);
        clearOffer(_id);
        emit OfferSettled(_id);
    }
    //Split into 2 functions to avoid stack errors
    function _transferTokensAndSettle(uint256 _id) private {
        ERC20 token = ERC20(offers[_id].tokenAddress);
        ERC20 baseToken = ERC20(offers[_id].baseToken);
        
        uint256 totalValue = offers[_id].bidValue + offers[_id].depositValue;
        uint256 fee = getExpectedFee(totalValue);
        
        baseToken.transfer(offers[_id].seller, totalValue - fee);
        feesEarned[offers[_id].baseToken] += fee;
        token.transfer(offers[_id].buyer, offers[_id].numberOfTokensForSale);
    }

    //Seller can cancel the offer if the deadline has passed and there is no matching bid
    function cancelOffer(uint256 _id) public nonReentrant {
        require(offers[_id].isOpen, "Offer is closed.");
        require(msg.sender == offers[_id].seller, "Wrong permissions.");
        require(hasDeadlinePassed(_id), "Deadline has not passed.");
        require(offers[_id].bidValue < offers[_id].totalSaleValue, "Active bid, cannot cancel.");
            ERC20 token = ERC20(offers[_id].tokenAddress);
            ERC20 baseToken = ERC20(offers[_id].baseToken);
            if(offers[_id].bidValue > 0){
                baseToken.transfer(offers[_id].buyer, offers[_id].bidValue);
            }
            token.transfer(offers[_id].seller, offers[_id].tokensDeposited);
            baseToken.transfer(offers[_id].seller, offers[_id].depositValue - getExpectedFee(offers[_id].depositValue + offers[_id].bidValue));
            feesEarned[offers[_id].baseToken] += getExpectedFee(offers[_id].bidValue + offers[_id].depositValue);
            clearOffer(_id);
                emit OfferCancelled(_id);
    }

    /*backout function is used for either party to back-out of the offer, if the other party has reneged on the deal.
      The seller will lose their deposit if they do not deposit the tokens, the buyer does not get punished, as they have put money up first. */
    function backOut(uint256 _id) public nonReentrant {
        ERC20 token = ERC20(offers[_id].tokenAddress);
        ERC20 baseToken = ERC20(offers[_id].baseToken);
        require(!offers[_id].isOpen, "Offer is still open.");
        require(msg.sender == offers[_id].seller || msg.sender == offers[_id].buyer, "Wrong permissions.");
        require(hasDeadlinePassed(_id), "Deadline has not passed.");
            if(offers[_id].bidValue >= offers[_id].totalSaleValue && offers[_id].tokensDeposited < offers[_id].numberOfTokensForSale){
                baseToken.transfer(offers[_id].buyer, offers[_id].bidValue + offers[_id].depositValue - getExpectedFee(offers[_id].depositValue + offers[_id].bidValue));
                if(offers[_id].tokensDeposited > 0){
                    token.transfer(offers[_id].seller, offers[_id].tokensDeposited);
                }
                feesEarned[offers[_id].baseToken] += getExpectedFee(offers[_id].bidValue + offers[_id].depositValue);
                    clearOffer(_id);
                        emit OfferCancelled(_id);
                        emit OfferBackedOut(_id);
            }else if ((offers[_id].bidValue < offers[_id].totalSaleValue && offers[_id].tokensDeposited >= offers[_id].numberOfTokensForSale)){
                token.transfer(offers[_id].seller, offers[_id].tokensDeposited);
                if(offers[_id].bidValue > 0){
                    baseToken.transfer(offers[_id].buyer, offers[_id].bidValue);
                }
                baseToken.transfer(offers[_id].seller, offers[_id].depositValue - getExpectedFee(offers[_id].depositValue + offers[_id].bidValue));
                feesEarned[offers[_id].baseToken] += getExpectedFee(offers[_id].bidValue + offers[_id].depositValue);
                    clearOffer(_id);
                        emit OfferCancelled(_id);
                        emit OfferBackedOut(_id);
            }
    }

    //helper function to clear data on an Offer
    function clearOffer(uint256 _id) internal {
        offers[_id].tokensDeposited = 0;
        offers[_id].bidValue = 0;
        offers[_id].isOpen = false;
        offers[_id].buyer = address(0);
        offers[_id].seller = address(0);
        offers[_id].numberOfTokensForSale = 0;
        offers[_id].totalSaleValue = 0;

    }
    
    function getExpectedValueDeposit(uint256 _totalSaleValue) internal pure returns (uint256) {
        uint256 ev = (_totalSaleValue) * 25 / 100;
        return ev;
    }

    function getExpectedFee(uint256 _depositValue) internal pure returns (uint256) {
        uint256 ev = _depositValue / 100;
        return ev;
    }

    function getOfferInfo(uint256 _id) public view returns(Offer memory){
        return offers[_id];
    }

    //returns TRUE if the deadline HAS passed.
    //returns FALSE if the deadline NOT passed.
    function hasDeadlinePassed(uint256 _id) internal view returns(bool){
        if(block.timestamp - offers[_id].createdBlockTimestamp > offers[_id].deadline){
            return true;
        } else {
            return false;
        }
    }

    function withdrawFees(address _token) public onlyOwner {
        ERC20 token = ERC20(_token);
        token.transfer(dev, feesEarned[_token]);
        feesEarned[_token] = 0;
    }

    modifier onlyOwner {
        require(msg.sender == dev, "Not the owner.");
        _;
    }
    
}
