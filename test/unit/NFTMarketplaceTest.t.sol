// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test}    from "forge-std/Test.sol";
import {NFTMarketplace}    from "../../src/NFTMarketplace.sol";
import {MockERC20}         from "../../src/MockERC20.sol";

/**
 * @title  NFTMarketplaceTest
 *   1. Type declarations
 *   2. State variables
 *   3. setUp
 *   4. Modifiers (shared state setup helpers)
 *   5. Test groups — one comment section per function under test
 *
 * Naming:  test_<FunctionName>_<Condition>_<Expected>
 * Reverts: test_<FunctionName>_<Condition>_Reverts
 */
contract NFTMarketplaceTest is Test {

    /*//////////////////////////////////////////////////////////////
                          STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    NFTMarketplace  internal marketplace;
    MockERC20       internal usdc;
    MockERC20       internal usdt;

    // Named actors
    address internal constant OWNER        = address(0x1);
    address internal constant SELLER       = address(0x2);
    address internal constant BUYER        = address(0x3);
    address internal constant FEE_RECIP    = address(0x4);
    address internal constant ROYALTY_RECIP = address(0x5);
    address internal constant ATTACKER     = address(0x9);

    // Standard test values
    uint256 internal constant LISTING_PRICE  = 0.001 ether;
    uint256 internal constant ETH_PRICE      = 1 ether;
    uint256 internal constant USDC_PRICE     = 1_000 * 1e6; // 1 000 USDC
    uint256 internal constant USDT_PRICE     = 1_000 * 1e6; // 1 000 USDT
    uint16  internal constant ROYALTY_BPS    = 500;          // 5 %
    uint256 internal constant PLATFORM_BPS   = 250;          // 2.5 %
    string  internal constant TOKEN_URI      = "ipfs://QmTest";

    /*//////////////////////////////////////////////////////////////
                              SET UP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        // Deploy mock tokens
        vm.startPrank(OWNER);
        usdc = new MockERC20("Mock USDC", "mUSDC", 6, 10_000_000 * 1e6);
        usdt = new MockERC20("Mock USDT", "mUSDT", 6, 10_000_000 * 1e6);

        marketplace = new NFTMarketplace(
            address(usdc),
            address(usdt),
            FEE_RECIP,
            "NFT Marketplace",
            "NFTM"
        );
        vm.stopPrank();

        // Fund actors
        vm.deal(SELLER, 100 ether);
        vm.deal(BUYER,  100 ether);

        // Give BUYER ERC20 tokens + approve marketplace
        vm.startPrank(OWNER);
        usdc.mint(BUYER, 100_000 * 1e6);
        usdt.mint(BUYER, 100_000 * 1e6);
        vm.stopPrank();

        vm.startPrank(BUYER);
        usdc.approve(address(marketplace), type(uint256).max);
        usdt.approve(address(marketplace), type(uint256).max);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    MODIFIERS — SHARED STATE HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Creates one token listed by SELLER, sets tokenId = 1
    modifier tokenListed() {
        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, USDC_PRICE, USDT_PRICE),
            ROYALTY_BPS,
            ROYALTY_RECIP
        );
        _;
    }

    /// @dev Creates a token and has BUYER purchase it via ETH
    modifier tokenSoldEth() {
        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, USDC_PRICE, USDT_PRICE),
            ROYALTY_BPS,
            ROYALTY_RECIP
        );
        vm.prank(BUYER);
        marketplace.createMarketSaleETH{value: ETH_PRICE}(1);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                    CONSTRUCTOR / DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Constructor_SetsUSDC() public view {
        assertEq(address(marketplace.USDC()), address(usdc));
    }

    function test_Constructor_SetsUSDT() public view {
        assertEq(address(marketplace.USDT()), address(usdt));
    }

    function test_Constructor_SetsFeeRecipient() public view {
        assertEq(marketplace.feeRecipient(), FEE_RECIP);
    }

    function test_Constructor_SetsListingPrice() public view {
        assertEq(marketplace.listingPrice(), LISTING_PRICE);
    }

    function test_Constructor_SetsPlatformFee() public view {
        assertEq(marketplace.platformFeeBps(), 250);
    }

    function test_Constructor_ZeroAddressUsdc_Reverts() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidAddress.selector);
        new NFTMarketplace(address(0), address(usdt), FEE_RECIP, "N", "N");
    }

    function test_Constructor_ZeroAddressUsdt_Reverts() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidAddress.selector);
        new NFTMarketplace(address(usdc), address(0), FEE_RECIP, "N", "N");
    }

    function test_Constructor_ZeroFeeRecipient_Reverts() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidAddress.selector);
        new NFTMarketplace(address(usdc), address(usdt), address(0), "N", "N");
    }

    /*//////////////////////////////////////////////////////////////
                       createToken TESTS
    //////////////////////////////////////////////////////////////*/

    function test_CreateToken_MintedToSeller() public {
        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, 0, 0),
            ROYALTY_BPS,
            ROYALTY_RECIP
        );
        // NFT transferred to contract (escrow) on listing
        assertEq(marketplace.ownerOf(1), address(marketplace));
    }

    function test_CreateToken_IncrementsTotalTokens() public {
        assertEq(marketplace.getTotalTokens(), 0);

        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, 0, 0),
            ROYALTY_BPS,
            ROYALTY_RECIP
        );

        assertEq(marketplace.getTotalTokens(), 1);
    }

    function test_CreateToken_MarketItemStoredCorrectly() public tokenListed {
        NFTMarketplace.MarketItem memory item = marketplace.getMarketItem(1);
        assertEq(item.tokenId,          1);
        assertEq(item.ethPrice,         ETH_PRICE);
        assertEq(item.usdcPrice,        USDC_PRICE);
        assertEq(item.usdtPrice,        USDT_PRICE);
        assertEq(item.seller,           SELLER);
        assertFalse(item.sold);
        assertEq(item.owner,            address(marketplace));
        assertEq(item.royaltyRecipient, ROYALTY_RECIP);
        assertEq(item.royaltyBps,       ROYALTY_BPS);
    }

    function test_CreateToken_ZeroRoyaltyRecipientDefaultsToSeller() public {
        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, 0, 0),
            ROYALTY_BPS,
            address(0) // zero → should default to SELLER
        );
        NFTMarketplace.MarketItem memory item = marketplace.getMarketItem(1);
        assertEq(item.royaltyRecipient, SELLER);
    }

    function test_CreateToken_EmitsMarketItemCreated() public {
        vm.expectEmit(true, true, false, true);
        emit NFTMarketplace.MarketItemCreated(
            1, SELLER, ETH_PRICE, USDC_PRICE, USDT_PRICE, ROYALTY_BPS, ROYALTY_RECIP
        );
        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, USDC_PRICE, USDT_PRICE),
            ROYALTY_BPS,
            ROYALTY_RECIP
        );
    }

    function test_CreateToken_WrongListingFee_Reverts() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidListingFee.selector);
        vm.prank(SELLER);
        marketplace.createToken{value: 0.0001 ether}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, 0, 0),
            ROYALTY_BPS,
            ROYALTY_RECIP
        );
    }

    function test_CreateToken_AllZeroPrices_Reverts() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidPrice.selector);
        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(0, 0, 0),
            ROYALTY_BPS,
            ROYALTY_RECIP
        );
    }

    function test_CreateToken_ExcessiveRoyaltyBps_Reverts() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidRoyaltyBps.selector);
        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, 0, 0),
            1001, // > MAX_ROYALTY_BPS
            ROYALTY_RECIP
        );
    }

    function test_CreateToken_BlacklistedSeller_Reverts() public {
        vm.prank(OWNER);
        marketplace.setUserBlacklisted(SELLER, true);

        vm.expectRevert(NFTMarketplace.NFTMarketplace__BlacklistedUser.selector);
        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, 0, 0),
            ROYALTY_BPS,
            ROYALTY_RECIP
        );
    }

    function test_CreateToken_WhenPaused_Reverts() public {
        vm.prank(OWNER);
        marketplace.pause();

        vm.expectRevert();
        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, 0, 0),
            ROYALTY_BPS,
            ROYALTY_RECIP
        );
    }

    /*//////////////////////////////////////////////////////////////
                    updateItemPrices TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpdateItemPrices_UpdatesCorrectly() public tokenListed {
        vm.prank(SELLER);
        marketplace.updateItemPrices(1, NFTMarketplace.TokenPrices(2 ether, 2_000 * 1e6, 2_000 * 1e6));

        NFTMarketplace.MarketItem memory item = marketplace.getMarketItem(1);
        assertEq(item.ethPrice,  2 ether);
        assertEq(item.usdcPrice, 2_000 * 1e6);
        assertEq(item.usdtPrice, 2_000 * 1e6);
    }

    function test_UpdateItemPrices_NotSeller_Reverts() public tokenListed {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotItemSeller.selector);
        vm.prank(ATTACKER);
        marketplace.updateItemPrices(1, NFTMarketplace.TokenPrices(2 ether, 0, 0));
    }

    function test_UpdateItemPrices_AlreadySold_Reverts() public tokenSoldEth {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__AlreadySold.selector);
        vm.prank(SELLER);
        marketplace.updateItemPrices(1, NFTMarketplace.TokenPrices(2 ether, 0, 0));
    }

    /*//////////////////////////////////////////////////////////////
                     cancelListing TESTS  (NEW)
    //////////////////////////////////////////////////////////////*/

    function test_CancelListing_ReturnsNFTToSeller() public tokenListed {
        vm.prank(SELLER);
        marketplace.cancelListing(1);
        assertEq(marketplace.ownerOf(1), SELLER);
    }

    function test_CancelListing_MarkedSoldAndOwnerSetToSeller() public tokenListed {
        vm.prank(SELLER);
        marketplace.cancelListing(1);

        NFTMarketplace.MarketItem memory item = marketplace.getMarketItem(1);
        assertTrue(item.sold);
        assertEq(item.owner,  SELLER);
        assertEq(item.seller, address(0));
    }

    function test_CancelListing_IncrementsSoldCounter() public tokenListed {
        vm.prank(SELLER);
        marketplace.cancelListing(1);
        assertEq(marketplace.getTotalSold(), 1);
    }

    function test_CancelListing_EmitsListingCancelled() public tokenListed {
        vm.expectEmit(true, true, false, false);
        emit NFTMarketplace.ListingCancelled(1, SELLER);
        vm.prank(SELLER);
        marketplace.cancelListing(1);
    }

    function test_CancelListing_RemovesFromFetchMarketItems() public tokenListed {
        assertEq(marketplace.fetchMarketItems().length, 1);

        vm.prank(SELLER);
        marketplace.cancelListing(1);

        assertEq(marketplace.fetchMarketItems().length, 0);
    }

    function test_CancelListing_NotSeller_Reverts() public tokenListed {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotItemSeller.selector);
        vm.prank(ATTACKER);
        marketplace.cancelListing(1);
    }

    function test_CancelListing_AlreadySold_Reverts() public tokenSoldEth {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__AlreadySold.selector);
        vm.prank(SELLER);
        marketplace.cancelListing(1);
    }

    /*//////////////////////////////////////////////////////////////
                      resellToken TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ResellToken_RelitsNFT() public tokenSoldEth {
        vm.prank(BUYER);
        marketplace.resellToken{value: LISTING_PRICE}(
            1,
            NFTMarketplace.TokenPrices(2 ether, 0, 0)
        );

        NFTMarketplace.MarketItem memory item = marketplace.getMarketItem(1);
        assertFalse(item.sold);
        assertEq(item.seller, BUYER);
        assertEq(item.owner,  address(marketplace));
    }

    function test_ResellToken_DecrementsSoldCounter() public tokenSoldEth {
        assertEq(marketplace.getTotalSold(), 1);

        vm.prank(BUYER);
        marketplace.resellToken{value: LISTING_PRICE}(
            1,
            NFTMarketplace.TokenPrices(2 ether, 0, 0)
        );

        assertEq(marketplace.getTotalSold(), 0);
    }

    function test_ResellToken_EmitsMarketItemRelisted() public tokenSoldEth {
        vm.expectEmit(true, true, false, true);
        emit NFTMarketplace.MarketItemRelisted(1, BUYER, 2 ether, 0, 0);
        vm.prank(BUYER);
        marketplace.resellToken{value: LISTING_PRICE}(1, NFTMarketplace.TokenPrices(2 ether, 0, 0));
    }

    function test_ResellToken_NotOwner_Reverts() public tokenSoldEth {
        vm.deal(ATTACKER, LISTING_PRICE);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotTokenOwner.selector);
        vm.prank(ATTACKER);
        marketplace.resellToken{value: LISTING_PRICE}(1, NFTMarketplace.TokenPrices(1 ether, 0, 0));
    }

    function test_ResellToken_WrongFee_Reverts() public tokenSoldEth {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidListingFee.selector);
        vm.prank(BUYER);
        marketplace.resellToken{value: 0}(1, NFTMarketplace.TokenPrices(1 ether, 0, 0));
    }

    /*//////////////////////////////////////////////////////////////
                   createMarketSaleETH TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SaleETH_TransfersNFTToBuyer() public tokenListed {
        vm.prank(BUYER);
        marketplace.createMarketSaleETH{value: ETH_PRICE}(1);
        assertEq(marketplace.ownerOf(1), BUYER);
    }

    function test_SaleETH_MarketItemUpdated() public tokenListed {
        vm.prank(BUYER);
        marketplace.createMarketSaleETH{value: ETH_PRICE}(1);

        NFTMarketplace.MarketItem memory item = marketplace.getMarketItem(1);
        assertTrue(item.sold);
        assertEq(item.owner,  BUYER);
        assertEq(item.seller, address(0));
    }

    function test_SaleETH_FeeDistributionCorrect() public tokenListed {
        uint256 sellerBefore      = SELLER.balance;
        uint256 feeRecipBefore    = FEE_RECIP.balance;
        uint256 royaltyRecipBefore = ROYALTY_RECIP.balance;

        vm.prank(BUYER);
        marketplace.createMarketSaleETH{value: ETH_PRICE}(1);

        uint256 platformFee = (ETH_PRICE * PLATFORM_BPS) / 10_000;   // 2.5 %
        uint256 royaltyFee  = (ETH_PRICE * ROYALTY_BPS)  / 10_000;   // 5 %
        uint256 sellerGet   = ETH_PRICE - platformFee - royaltyFee;

        assertEq(FEE_RECIP.balance    - feeRecipBefore,     platformFee);
        assertEq(ROYALTY_RECIP.balance - royaltyRecipBefore, royaltyFee);
        assertEq(SELLER.balance       - sellerBefore,        sellerGet);
    }

    function test_SaleETH_IncrementsSoldCounter() public tokenListed {
        vm.prank(BUYER);
        marketplace.createMarketSaleETH{value: ETH_PRICE}(1);
        assertEq(marketplace.getTotalSold(), 1);
    }

    function test_SaleETH_EmitsMarketItemSold() public tokenListed {
        uint256 platformFee = (ETH_PRICE * PLATFORM_BPS) / 10_000;
        uint256 royaltyFee  = (ETH_PRICE * ROYALTY_BPS)  / 10_000;

        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.MarketItemSold(
            1, SELLER, BUYER, ETH_PRICE,
            NFTMarketplace.PaymentToken.ETH, platformFee, royaltyFee
        );
        vm.prank(BUYER);
        marketplace.createMarketSaleETH{value: ETH_PRICE}(1);
    }

    function test_SaleETH_WrongPrice_Reverts() public tokenListed {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InsufficientPayment.selector);
        vm.prank(BUYER);
        marketplace.createMarketSaleETH{value: 0.5 ether}(1);
    }

    function test_SaleETH_NotForSale_Reverts() public tokenListed {
        // List with only USDC price
        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(0, USDC_PRICE, 0), // eth price = 0
            ROYALTY_BPS,
            ROYALTY_RECIP
        );

        vm.expectRevert(NFTMarketplace.NFTMarketplace__NotForSale.selector);
        vm.prank(BUYER);
        marketplace.createMarketSaleETH{value: 0}(2);
    }

    function test_SaleETH_BlacklistedToken_Reverts() public tokenListed {
        vm.prank(OWNER);
        marketplace.setTokenBlacklisted(1, true);

        vm.expectRevert(NFTMarketplace.NFTMarketplace__BlacklistedToken.selector);
        vm.prank(BUYER);
        marketplace.createMarketSaleETH{value: ETH_PRICE}(1);
    }

    function test_SaleETH_BlacklistedBuyer_Reverts() public tokenListed {
        vm.prank(OWNER);
        marketplace.setUserBlacklisted(BUYER, true);

        vm.expectRevert(NFTMarketplace.NFTMarketplace__BlacklistedUser.selector);
        vm.prank(BUYER);
        marketplace.createMarketSaleETH{value: ETH_PRICE}(1);
    }

    /*//////////////////////////////////////////////////////////////
                  createMarketSaleUSDC TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SaleUSDC_TransfersNFT() public tokenListed {
        vm.prank(BUYER);
        marketplace.createMarketSaleUSDC(1);
        assertEq(marketplace.ownerOf(1), BUYER);
    }

    function test_SaleUSDC_FeesDistributedCorrectly() public tokenListed {
        uint256 feeRecipBefore     = usdc.balanceOf(FEE_RECIP);
        uint256 royaltyRecipBefore = usdc.balanceOf(ROYALTY_RECIP);
        uint256 sellerBefore       = usdc.balanceOf(SELLER);

        vm.prank(BUYER);
        marketplace.createMarketSaleUSDC(1);

        uint256 platformFee = (USDC_PRICE * PLATFORM_BPS) / 10_000;
        uint256 royaltyFee  = (USDC_PRICE * ROYALTY_BPS)  / 10_000;
        uint256 sellerGet   = USDC_PRICE - platformFee - royaltyFee;

        assertEq(usdc.balanceOf(FEE_RECIP)    - feeRecipBefore,     platformFee);
        assertEq(usdc.balanceOf(ROYALTY_RECIP) - royaltyRecipBefore, royaltyFee);
        assertEq(usdc.balanceOf(SELLER)        - sellerBefore,       sellerGet);
    }

    function test_SaleUSDC_InsufficientAllowance_Reverts() public tokenListed {
        // Fresh address with no pre-approval
        address poorBuyer = address(0x99);
        vm.deal(poorBuyer, 10 ether);

        vm.startPrank(OWNER);
        usdc.mint(poorBuyer, 100_000 * 1e6);
        vm.stopPrank();
        // No approve call → should revert on safeTransferFrom

        vm.expectRevert();
        vm.prank(poorBuyer);
        marketplace.createMarketSaleUSDC(1);
    }

    /*//////////////////////////////////////////////////////////////
                  createMarketSaleUSDT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_SaleUSDT_TransfersNFT() public tokenListed {
        vm.prank(BUYER);
        marketplace.createMarketSaleUSDT(1);
        assertEq(marketplace.ownerOf(1), BUYER);
    }

    function test_SaleUSDT_FeesDistributedCorrectly() public tokenListed {
        uint256 feeRecipBefore     = usdt.balanceOf(FEE_RECIP);
        uint256 royaltyRecipBefore = usdt.balanceOf(ROYALTY_RECIP);
        uint256 sellerBefore       = usdt.balanceOf(SELLER);

        vm.prank(BUYER);
        marketplace.createMarketSaleUSDT(1);

        uint256 platformFee = (USDT_PRICE * PLATFORM_BPS) / 10_000;
        uint256 royaltyFee  = (USDT_PRICE * ROYALTY_BPS)  / 10_000;
        uint256 sellerGet   = USDT_PRICE - platformFee - royaltyFee;

        assertEq(usdt.balanceOf(FEE_RECIP)    - feeRecipBefore,     platformFee);
        assertEq(usdt.balanceOf(ROYALTY_RECIP) - royaltyRecipBefore, royaltyFee);
        assertEq(usdt.balanceOf(SELLER)        - sellerBefore,       sellerGet);
    }

    /*//////////////////////////////////////////////////////////////
              fetchMarketItems BUG FIX TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Regression: original returned array with trailing zero-value structs
    ///         when blacklisted tokens were present.
    function test_FetchMarketItems_WithBlacklistedToken_NoTrailingZeroStructs() public {
        // Mint two tokens
        vm.startPrank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, 0, 0),
            ROYALTY_BPS, ROYALTY_RECIP
        );
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, 0, 0),
            ROYALTY_BPS, ROYALTY_RECIP
        );
        vm.stopPrank();

        // Blacklist token #1
        vm.prank(OWNER);
        marketplace.setTokenBlacklisted(1, true);

        NFTMarketplace.MarketItem[] memory items = marketplace.fetchMarketItems();

        // Should return exactly 1 item (not 2 with a trailing zero)
        assertEq(items.length, 1);
        assertEq(items[0].tokenId, 2); // only token 2 visible
    }

    function test_FetchMarketItems_AfterSale_NotIncluded() public tokenListed {
        assertEq(marketplace.fetchMarketItems().length, 1);

        vm.prank(BUYER);
        marketplace.createMarketSaleETH{value: ETH_PRICE}(1);

        assertEq(marketplace.fetchMarketItems().length, 0);
    }

    function test_FetchMyNFTs_ReturnsCorrectItems() public tokenSoldEth {
        vm.prank(BUYER);
        NFTMarketplace.MarketItem[] memory myItems = marketplace.fetchMyNFTs();

        assertEq(myItems.length, 1);
        assertEq(myItems[0].tokenId, 1);
        assertEq(myItems[0].owner,   BUYER);
    }

    function test_FetchItemsListed_ReturnsCorrectItems() public tokenListed {
        vm.prank(SELLER);
        NFTMarketplace.MarketItem[] memory listed = marketplace.fetchItemsListed();

        assertEq(listed.length, 1);
        assertEq(listed[0].seller, SELLER);
    }

    /*//////////////////////////////////////////////////////////////
                      EIP-2981 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_RoyaltyInfo_ReturnsCorrectValues() public tokenListed {
        (address receiver, uint256 royaltyAmount) = marketplace.royaltyInfo(1, 1 ether);
        assertEq(receiver,      ROYALTY_RECIP);
        assertEq(royaltyAmount, 0.05 ether); // 5% of 1 ether
    }

    function test_SupportsInterface_ERC2981() public view {
        assertTrue(marketplace.supportsInterface(type(IERC2981).interfaceId));
    }

    function test_SupportsInterface_ERC721() public view {
        assertTrue(marketplace.supportsInterface(0x80ac58cd));
    }

    /*//////////////////////////////////////////////////////////////
                     ADMIN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_UpdateListingPrice_Owner_Succeeds() public {
        vm.prank(OWNER);
        marketplace.updateListingPrice(0.002 ether);
        assertEq(marketplace.listingPrice(), 0.002 ether);
    }

    function test_UpdateListingPrice_EmitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit NFTMarketplace.ListingPriceUpdated(LISTING_PRICE, 0.002 ether);
        vm.prank(OWNER);
        marketplace.updateListingPrice(0.002 ether);
    }

    function test_UpdateListingPrice_ExceedsMax_Reverts() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidListingFee.selector);
        vm.prank(OWNER);
        marketplace.updateListingPrice(2 ether);
    }

    function test_UpdateListingPrice_NonOwner_Reverts() public {
        vm.expectRevert();
        vm.prank(ATTACKER);
        marketplace.updateListingPrice(0.002 ether);
    }

    function test_UpdatePlatformFee_Owner_Succeeds() public {
        vm.prank(OWNER);
        marketplace.updatePlatformFee(300);
        assertEq(marketplace.platformFeeBps(), 300);
    }

    function test_UpdatePlatformFee_ExceedsTenPercent_Reverts() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidPlatformFee.selector);
        vm.prank(OWNER);
        marketplace.updatePlatformFee(1001);
    }

    function test_UpdateFeeRecipient_Succeeds() public {
        address newRecipient = address(0xBEEF);
        vm.prank(OWNER);
        marketplace.updateFeeRecipient(newRecipient);
        assertEq(marketplace.feeRecipient(), newRecipient);
    }

    function test_UpdateFeeRecipient_ZeroAddress_Reverts() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidAddress.selector);
        vm.prank(OWNER);
        marketplace.updateFeeRecipient(address(0));
    }

    function test_Pause_StopsCreateToken() public {
        vm.prank(OWNER);
        marketplace.pause();
        assertTrue(marketplace.paused());

        vm.expectRevert();
        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, 0, 0),
            ROYALTY_BPS, ROYALTY_RECIP
        );
    }

    function test_Unpause_AllowsOperations() public {
        vm.startPrank(OWNER);
        marketplace.pause();
        marketplace.unpause();
        vm.stopPrank();
        assertFalse(marketplace.paused());
    }

    /*//////////////////////////////////////////////////////////////
                    BLACKLIST TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BlacklistUser_PreventsListing() public {
        vm.prank(OWNER);
        marketplace.setUserBlacklisted(SELLER, true);

        vm.expectRevert(NFTMarketplace.NFTMarketplace__BlacklistedUser.selector);
        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI, NFTMarketplace.TokenPrices(ETH_PRICE, 0, 0), ROYALTY_BPS, ROYALTY_RECIP
        );
    }

    function test_BlacklistToken_PreventsSale() public tokenListed {
        vm.prank(OWNER);
        marketplace.setTokenBlacklisted(1, true);

        vm.expectRevert(NFTMarketplace.NFTMarketplace__BlacklistedToken.selector);
        vm.prank(BUYER);
        marketplace.createMarketSaleETH{value: ETH_PRICE}(1);
    }

    function test_UnblacklistUser_AllowsListing() public {
        vm.startPrank(OWNER);
        marketplace.setUserBlacklisted(SELLER, true);
        marketplace.setUserBlacklisted(SELLER, false);
        vm.stopPrank();

        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI, NFTMarketplace.TokenPrices(ETH_PRICE, 0, 0), ROYALTY_BPS, ROYALTY_RECIP
        );
        assertEq(marketplace.getTotalTokens(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                   EMERGENCY WITHDRAW TESTS
    //////////////////////////////////////////////////////////////*/

    function test_EmergencyWithdraw_AfterDelay_Succeeds() public tokenListed {
        vm.prank(OWNER);
        marketplace.initiateEmergencyWithdraw();

        // Fast-forward past 7 day delay
        vm.warp(block.timestamp + 7 days + 1);

        uint256 contractBal = address(marketplace).balance;
        uint256 ownerBefore  = OWNER.balance;

        vm.prank(OWNER);
        marketplace.emergencyWithdrawETH();

        assertEq(OWNER.balance - ownerBefore, contractBal);
    }

    /// @notice FIX REGRESSION: flag must be reset after execution
    function test_EmergencyWithdrawETH_ResetsFlag() public {
        vm.prank(OWNER);
        marketplace.initiateEmergencyWithdraw();
        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(OWNER);
        marketplace.emergencyWithdrawETH();

        assertFalse(marketplace.emergencyWithdrawEnabled());
        assertEq(marketplace.emergencyWithdrawUnlockAt(), 0);
    }

    function test_EmergencyWithdrawToken_ResetsFlag() public tokenListed {
        vm.prank(OWNER);
        marketplace.initiateEmergencyWithdraw();
        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(OWNER);
        marketplace.emergencyWithdrawToken(usdc);

        assertFalse(marketplace.emergencyWithdrawEnabled());
    }

    function test_EmergencyWithdraw_BeforeDelay_Reverts() public {
        vm.prank(OWNER);
        marketplace.initiateEmergencyWithdraw();

        // Only 1 day passed, not 7
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert(NFTMarketplace.NFTMarketplace__EmergencyNotReady.selector);
        vm.prank(OWNER);
        marketplace.emergencyWithdrawETH();
    }

    function test_EmergencyWithdraw_NotInitiated_Reverts() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__EmergencyNotReady.selector);
        vm.prank(OWNER);
        marketplace.emergencyWithdrawETH();
    }

    function test_CancelEmergencyWithdraw_PreventsExecution() public {
        vm.startPrank(OWNER);
        marketplace.initiateEmergencyWithdraw();
        marketplace.cancelEmergencyWithdraw();
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);

        vm.expectRevert(NFTMarketplace.NFTMarketplace__EmergencyNotReady.selector);
        vm.prank(OWNER);
        marketplace.emergencyWithdrawETH();
    }

    /*//////////////////////////////////////////////////////////////
                    TOKEN EXISTENCE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_GetMarketItem_InvalidId_Reverts() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__TokenDoesNotExist.selector);
        marketplace.getMarketItem(0);
    }

    function test_GetMarketItem_FutureId_Reverts() public {
        vm.expectRevert(NFTMarketplace.NFTMarketplace__TokenDoesNotExist.selector);
        marketplace.getMarketItem(999);
    }

    /*//////////////////////////////////////////////////////////////
                     FULL END-TO-END FLOW
    //////////////////////////////////////////////////////////////*/

    function test_FullFlow_ListBuyResell() public {
        // 1. SELLER lists
        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, 0, 0),
            ROYALTY_BPS,
            ROYALTY_RECIP
        );
        assertEq(marketplace.getTotalTokens(), 1);

        // 2. BUYER buys
        vm.prank(BUYER);
        marketplace.createMarketSaleETH{value: ETH_PRICE}(1);
        assertEq(marketplace.ownerOf(1), BUYER);
        assertEq(marketplace.getTotalSold(), 1);

        // 3. BUYER relists
        vm.prank(BUYER);
        marketplace.resellToken{value: LISTING_PRICE}(
            1,
            NFTMarketplace.TokenPrices(2 ether, 0, 0)
        );
        assertEq(marketplace.getTotalSold(), 0);

        // 4. Another buyer (SELLER acting as buyer this time)
        vm.deal(SELLER, 100 ether);
        vm.prank(SELLER);
        marketplace.createMarketSaleETH{value: 2 ether}(1);
        assertEq(marketplace.ownerOf(1), SELLER);
        assertEq(marketplace.getTotalSold(), 1);
    }

    function test_FullFlow_ListCancel_NotInMarket() public {
        vm.prank(SELLER);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ETH_PRICE, 0, 0),
            ROYALTY_BPS,
            ROYALTY_RECIP
        );

        assertEq(marketplace.fetchMarketItems().length, 1);

        vm.prank(SELLER);
        marketplace.cancelListing(1);

        assertEq(marketplace.fetchMarketItems().length, 0);
        assertEq(marketplace.ownerOf(1), SELLER);
    }
}

// Expose IERC2981 interfaceId for test_SupportsInterface_ERC2981
interface IERC2981 {
    function royaltyInfo(uint256, uint256) external view returns (address, uint256);
}
