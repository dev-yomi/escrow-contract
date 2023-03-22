# Escrow Contract for ERC20 Tokens

This contract provides an escrow service for securely trading ERC20 tokens on the blockchain, including the Over-The-Counter (OTC) sale of tokens that have not yet launched. It ensures a trustless and secure trading environment for both sellers and buyers.

## Features

Allows sellers to create offers by specifying the token they wish to receive, the number of tokens to sell, the total sale value, and a deadline.
Sellers can optionally add the token address of the token they want to sell.
Buyers can accept offers and deposit the required base tokens.
Both parties can settle or cancel the offer, depending on the fulfillment of the conditions.
Secured by a 25% deposit from the seller (in baseToken).
A 1% fee on the transaction value is charged to the seller.

Implements ReentrancyGuard for added security.

## How It Works

Seller
Create an offer by calling createOffer() with the required parameters.
Optionally, add the token address of the token to sell by calling addTokenAddress().
Deposit the tokens to sell by calling depositTokens().
If the offer is not fulfilled, the seller can cancel the offer (cancelOffer()) or back out (backOut()) after the deadline.
Buyer
Accept an offer by calling acceptOffer(), depositing the required baseToken amount.
Verify the token address provided by the seller using verifyTokenAddress().
If the offer conditions are met, either the buyer or seller can settle the offer by calling settleOffer().
If the other party has reneged on the deal, the buyer can back out (backOut()) after the deadline.
In the event that the seller did not deposit tokens, the buyer receives the seller's deposit.

## Important Notes

Deadlines are specified in seconds since the Unix epoch, using the block.timestamp.
All values are in wei. If you are using a token with a different decimal count than the standard 18, you must account for that.
Events
OfferCreated: Emitted when an offer is created.
OfferAccepted: Emitted when an offer is accepted by a buyer.
OfferSettled: Emitted when an offer is settled.
OfferCancelled: Emitted when an offer is cancelled.
TokenAddressUpdated: Emitted when the token address is updated.
OfferBackedOut: Emitted when a party backs out of an offer.
