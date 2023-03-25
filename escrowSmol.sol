pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";


contract Escrow is ReentrancyGuard {

    using SafeERC20 for ERC20;

    /*
        This contract implements an escrow service for trading ERC20 tokens on the blockchain.
        
        Note: All values are in wei. If you are using a token with a different decimal count than the standard 18, you must account for that.
    */

    uint256 public offerCount = 0;
    mapping(uint256 => Offer) public offers;
    mapping(address => uint256) public submittedAddress;
    mapping(address => uint256) public feesEarned;
    address public dev;

    event OfferCreated(uint256 indexed offerId, address tokenForSale, address tokenRequested, uint256 numberOfTokensForSale, uint256 totalSaleValue);
    event OfferAccepted(uint256 indexed offerId, address buyer);
    event OfferSettled(uint256 indexed offerId);
    event OfferCancelled(uint256 indexed offerId);

    constructor(address _dev){
        dev = _dev;
    }


    struct Offer {
        uint256 id;
        uint256 createdBlockTimestamp;
        address seller;
        address baseToken;
        address tokenAddress;
        uint256 numberOfTokensForSale;
        uint256 totalSaleValue;
        uint256 deadline;
        bool isOpen;
        uint256 bidValue;
        address buyer;
        uint256 tokensDeposited;
    }

    
    function createOffer(address _baseToken, address _tokenToSellAddress, uint256 _numOfTokensToSell, uint256 _totalSaleValue, uint256 _deadline) public {
         _createOffer(msg.sender, _baseToken, _tokenToSellAddress, _numOfTokensToSell, _totalSaleValue, _deadline);
    }


    function _createOffer(address _caller, address _baseToken, address _tokenToSellAddress, uint256 _numOfTokensToSell, uint256 _totalSaleValue, uint256 _deadline) private {
        require(_caller != address(0), "Seller address cannot be the zero address.");
        require(_numOfTokensToSell > 0 && _totalSaleValue > 0 && _deadline > 0 && _baseToken != address(0));
        ERC20 token = ERC20(_tokenToSellAddress);
        uint256 _depositedTokens = 0;
        uint256 preBal = token.balanceOf(address(this));
        token.safeTransferFrom(_caller, address(this), _numOfTokensToSell);
            _depositedTokens = token.balanceOf(address(this)) - preBal;
            offerCount++;
            Offer memory userOffer = Offer(offerCount, block.timestamp, _caller, _baseToken, _tokenToSellAddress, _numOfTokensToSell, _totalSaleValue, _deadline, true, 0, address(this), _depositedTokens);
            offers[offerCount] = userOffer;
                emit OfferCreated(userOffer.id, userOffer.tokenAddress, userOffer.baseToken, userOffer.numberOfTokensForSale, userOffer.totalSaleValue);
    }

    //Buyer can accept offer by depositing the correct number of baseToken to an offer
    function acceptOffer(uint256 _id) public {
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
                settleOffer(_id, msg.sender);
    }

    function settleOffer(uint256 _id, address _caller) private nonReentrant {
        require(!offers[_id].isOpen, "Offer is still open.");
        require(!hasDeadlinePassed(_id), "Deadline passed.");
        require(_caller == offers[_id].buyer || _caller == offers[_id].seller);
        require(offers[_id].tokensDeposited >= offers[_id].numberOfTokensForSale);
        require(offers[_id].bidValue >= offers[_id].totalSaleValue);
        
        _transferTokensAndSettle(_id);
        clearOffer(_id);
        emit OfferSettled(_id);
    }

    //Split into 2 functions to avoid stack errors
    function _transferTokensAndSettle(uint256 _id) private {
        ERC20 token = ERC20(offers[_id].tokenAddress);
        ERC20 baseToken = ERC20(offers[_id].baseToken);
        
        uint256 fee = getExpectedFee(offers[_id].bidValue) / 2;
        uint256 fee2 = getExpectedFee(offers[_id].numberOfTokensForSale) / 2;
        
        baseToken.transfer(offers[_id].seller, offers[_id].bidValue - fee);
        feesEarned[offers[_id].baseToken] += fee;
        feesEarned[offers[_id].tokenAddress] += fee2;
        token.transfer(offers[_id].buyer, offers[_id].numberOfTokensForSale - fee2);
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
            clearOffer(_id);
                emit OfferCancelled(_id);
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
