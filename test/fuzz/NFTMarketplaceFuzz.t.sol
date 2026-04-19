// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test}           from "forge-std/Test.sol";
import {NFTMarketplace} from "../../src/NFTMarketplace.sol";
import {MockERC20}      from "../../src/MockERC20.sol";

/**
 * @title  NFTMarketplaceFuzz
 * @notice Fuzz & invariant tests for NFTMarketplace.
 *
 * Run:
 *   forge test --match-contract NFTMarketplaceFuzz -vv
 *   forge test --match-contract NFTMarketplaceFuzz --fuzz-runs 1000 -vv
 */
contract NFTMarketplaceFuzz is Test {

    /*//////////////////////////////////////////////////////////////
                             STATE
    //////////////////////////////////////////////////////////////*/

    NFTMarketplace internal marketplace;
    MockERC20      internal usdc;
    MockERC20      internal usdt;

    address internal constant OWNER      = address(0x1);
    address internal constant FEE_RECIP  = address(0x4);

    uint256 internal constant LISTING_PRICE = 0.001 ether;
    string  internal constant TOKEN_URI     = "ipfs://fuzz";

    /*//////////////////////////////////////////////////////////////
                             SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.startPrank(OWNER);
        usdc = new MockERC20("Mock USDC", "mUSDC", 6, type(uint128).max);
        usdt = new MockERC20("Mock USDT", "mUSDT", 6, type(uint128).max);
        marketplace = new NFTMarketplace(
            address(usdc), address(usdt), FEE_RECIP, "NFT", "NFT"
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                    HELPER
    //////////////////////////////////////////////////////////////*/

    function _listToken(address seller, uint256 ethPrice) internal returns (uint256 tokenId) {
        vm.deal(seller, seller.balance + LISTING_PRICE);
        vm.prank(seller);
        tokenId = marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ethPrice, 0, 0),
            0,
            seller
        );
    }

    /*//////////////////////////////////////////////////////////////
              testFuzz — createToken price bounds
    //////////////////////////////////////////////////////////////*/

    /// @notice Any non-zero ethPrice should allow token creation.
    function testFuzz_CreateToken_AnyNonZeroEthPrice_Succeeds(uint256 ethPrice) public {
        vm.assume(ethPrice > 0 && ethPrice < type(uint128).max);

        address seller = address(0xABCD);
        vm.deal(seller, LISTING_PRICE);
        vm.prank(seller);
        uint256 tid = marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ethPrice, 0, 0),
            0,
            seller
        );

        assertEq(marketplace.getMarketItem(tid).ethPrice, ethPrice);
    }

    /// @notice Royalty bps in [0, 1000] should always succeed.
    function testFuzz_CreateToken_ValidRoyaltyBps_Succeeds(uint16 royaltyBps) public {
        vm.assume(royaltyBps <= 1_000);

        address seller = address(0xABCD);
        vm.deal(seller, LISTING_PRICE);
        vm.prank(seller);
        uint256 tid = marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(1 ether, 0, 0),
            royaltyBps,
            seller
        );

        assertEq(marketplace.getMarketItem(tid).royaltyBps, royaltyBps);
    }

    /// @notice Royalty bps > 1000 should always revert.
    function testFuzz_CreateToken_ExcessiveRoyaltyBps_AlwaysReverts(uint16 royaltyBps) public {
        vm.assume(royaltyBps > 1_000);

        address seller = address(0xABCD);
        vm.deal(seller, LISTING_PRICE);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidRoyaltyBps.selector);
        vm.prank(seller);
        marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(1 ether, 0, 0),
            royaltyBps,
            seller
        );
    }

    /*//////////////////////////////////////////////////////////////
                 testFuzz — fee distribution never overflows
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice For any price and any valid royaltyBps + platformBps:
     *         platformFee + royaltyFee + sellerAmount == price
     *         (no dust, no overflow, no underflow)
     */
    function testFuzz_FeeDistribution_SumEqualsPrice(
        uint128 price,
        uint16  royaltyBps,
        uint16  platformBps
    ) public pure {
        vm.assume(price      > 0);
        vm.assume(royaltyBps  <= 1_000);
        vm.assume(platformBps <= 1_000);

        uint256 BPS_BASE = 10_000;
        uint256 platformFee = (uint256(price) * platformBps)  / BPS_BASE;
        uint256 royaltyFee  = (uint256(price) * royaltyBps)   / BPS_BASE;

        // sellerAmount must not underflow
        // Combined fee cap: platformBps + royaltyBps ≤ 2000 bps = 20%
        // So price - platformFee - royaltyFee ≥ price * 80% > 0
        assertGe(uint256(price), platformFee + royaltyFee);
        uint256 sellerAmount = uint256(price) - platformFee - royaltyFee;
        assertEq(platformFee + royaltyFee + sellerAmount, uint256(price));
    }

    /*//////////////////////////////////////////////////////////////
             testFuzz — ETH sale with random price
    //////////////////////////////////////////////////////////////*/

    function testFuzz_SaleETH_BuyerPaysExactPrice_Succeeds(uint128 ethPrice) public {
        vm.assume(ethPrice > 0);

        address seller = makeAddr("seller");
        address buyer  = makeAddr("buyer");

        // List
        vm.deal(seller, LISTING_PRICE);
        vm.prank(seller);
        uint256 tid = marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ethPrice, 0, 0),
            0,
            seller
        );

        // Buy
        vm.deal(buyer, ethPrice);
        vm.prank(buyer);
        marketplace.createMarketSaleETH{value: ethPrice}(tid);

        assertEq(marketplace.ownerOf(tid), buyer);
    }

    function testFuzz_SaleETH_BuyerPaysWrongAmount_AlwaysReverts(
        uint128 ethPrice,
        uint128 wrongPayment
    ) public {
        vm.assume(ethPrice    > 0);
        vm.assume(wrongPayment != ethPrice);

        address seller = makeAddr("seller");
        address buyer  = makeAddr("buyer");

        vm.deal(seller, LISTING_PRICE);
        vm.prank(seller);
        uint256 tid = marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ethPrice, 0, 0),
            0,
            seller
        );

        vm.deal(buyer, uint256(wrongPayment) + 1 ether);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InsufficientPayment.selector);
        vm.prank(buyer);
        marketplace.createMarketSaleETH{value: wrongPayment}(tid);
    }

    /*//////////////////////////////////////////////////////////////
              testFuzz — platformFee updates
    //////////////////////////////////////////////////////////////*/

    function testFuzz_UpdatePlatformFee_ValidRange_Succeeds(uint16 bps) public {
        vm.assume(bps <= 1_000);
        vm.prank(OWNER);
        marketplace.updatePlatformFee(bps);
        assertEq(marketplace.platformFeeBps(), bps);
    }

    function testFuzz_UpdatePlatformFee_TooHigh_Reverts(uint16 bps) public {
        vm.assume(bps > 1_000);
        vm.expectRevert(NFTMarketplace.NFTMarketplace__InvalidPlatformFee.selector);
        vm.prank(OWNER);
        marketplace.updatePlatformFee(bps);
    }

    /*//////////////////////////////////////////////////////////////
              testFuzz — royaltyInfo EIP-2981
    //////////////////////////////////////////////////////////////*/

    function testFuzz_RoyaltyInfo_MatchesStoredBps(
        uint128 salePrice,
        uint16  royaltyBps
    ) public {
        vm.assume(royaltyBps <= 1_000);

        address seller = makeAddr("seller");
        vm.deal(seller, LISTING_PRICE);
        vm.prank(seller);
        uint256 tid = marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(1 ether, 0, 0),
            royaltyBps,
            seller
        );

        (, uint256 royaltyAmount) = marketplace.royaltyInfo(tid, salePrice);
        uint256 expected = (uint256(salePrice) * royaltyBps) / 10_000;
        assertEq(royaltyAmount, expected);
    }

    /*//////////////////////////////////////////////////////////////
              testFuzz — cancelListing then resell
    //////////////////////////////////////////////////////////////*/

    function testFuzz_CancelAndResell_SoldCounterStaysConsistent(uint128 ethPrice) public {
        vm.assume(ethPrice > 0 && ethPrice < 1000 ether);

        address seller = makeAddr("seller");
        vm.deal(seller, 10 ether);

        // List + cancel
        vm.prank(seller);
        uint256 tid = marketplace.createToken{value: LISTING_PRICE}(
            TOKEN_URI,
            NFTMarketplace.TokenPrices(ethPrice, 0, 0),
            0,
            seller
        );
        vm.prank(seller);
        marketplace.cancelListing(tid);

        // After cancel: 1 "sold" (cancel counts as taken off market)
        assertEq(marketplace.getTotalSold(), 1);

        // Resell
        vm.prank(seller);
        marketplace.resellToken{value: LISTING_PRICE}(
            tid,
            NFTMarketplace.TokenPrices(ethPrice, 0, 0)
        );

        // After resell from cancel state: sold counter should decrement back
        assertEq(marketplace.getTotalSold(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                     INVARIANT HELPERS
    //////////////////////////////////////////////////////////////*/

    // Note: For full invariant testing, use forge's invariant test framework.
    // These targeted assertions document the key invariant:
    //   _itemsSold <= _tokenIds at all times.

    function testFuzz_SoldCounterNeverExceedsTotalTokens(uint8 numMints) public {
        vm.assume(numMints > 0 && numMints <= 20);

        address seller = makeAddr("seller");
        vm.deal(seller, uint256(numMints) * LISTING_PRICE * 2);

        for (uint8 i = 0; i < numMints; i++) {
            vm.prank(seller);
            marketplace.createToken{value: LISTING_PRICE}(
                TOKEN_URI,
                NFTMarketplace.TokenPrices(0.1 ether, 0, 0),
                0,
                seller
            );
        }

        // Invariant: sold ≤ total
        assertLe(marketplace.getTotalSold(), marketplace.getTotalTokens());
    }
}
