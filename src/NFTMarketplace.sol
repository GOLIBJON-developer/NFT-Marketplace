// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721,ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/**
 * @title  NFTMarketplace
 * @author GOLIBJON-developer
 * @notice Production-ready NFT marketplace — ETH / USDC / USDT payments, EIP-2981 royalties.
 *
 * Gas fixes vs original:
 *  • MarketItem struct packed from 10 → 7 storage slots
 *    (royaltyRecipient + listedAt uint64 + royaltyBps uint16 + sold bool share one slot)
 *  • Removed duplicate usdcAddress / usdtAddress state (use address(USDC/USDT))
 *  • Removed dead tokenListingFees mapping
 *  • unchecked arithmetic in all counter increments and loop indices
 *  • Storage reads cached into locals before CEI writes
 *
 * Logic fixes vs original:
 *  • fetchMarketItems() — two-pass count so array has no trailing zero entries
 *  • cancelListing()    — seller can delist their own NFT
 *  • emergencyWithdraw  — resets enabled flag after execution
 *  • resellToken        — only decrements _itemsSold when item was actually sold
 *  • Errors renamed NFTMarketplace__ prefix (Cyfrin convention)
 */
contract NFTMarketplace is
    ERC721URIStorage,
    ReentrancyGuard,
    Pausable,
    Ownable,
    IERC2981
{
    using SafeERC20 for IERC20;
    using Address   for address payable;

    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_ROYALTY_BPS  = 1_000;  // 10 %
    uint256 public constant BPS_BASE         = 10_000; // 100 %
    uint256 public constant MAX_LISTING_FEE  = 1 ether;
    uint256 public constant EMERGENCY_DELAY  = 7 days;

    /*//////////////////////////////////////////////////////////////
                          MUTABLE STATE
    //////////////////////////////////////////////////////////////*/

    uint256 public listingPrice   = 0.001 ether;
    uint256 public platformFeeBps = 250;            // 2.5 %
    address public feeRecipient;

    // Emergency
    bool    public emergencyWithdrawEnabled;
    uint256 public emergencyWithdrawUnlockAt;

    /*//////////////////////////////////////////////////////////////
                           IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    /// @dev No separate usdcAddress / usdtAddress — use address(USDC) / address(USDT)
    IERC20 public immutable USDC;
    IERC20 public immutable USDT;

    /*//////////////////////////////////////////////////////////////
                             COUNTERS
    //////////////////////////////////////////////////////////////*/

    uint256 private _tokenIds;
    uint256 private _itemsSold;

    /*//////////////////////////////////////////////////////////////
                              ENUMS
    //////////////////////////////////////////////////////////////*/

    enum PaymentToken { ETH, USDC, USDT }

    /*//////////////////////////////////////////////////////////////
                       GAS-PACKED STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * Storage layout (7 slots instead of original 10):
     *
     *  slot 1  tokenId           uint256
     *  slot 2  ethPrice          uint256
     *  slot 3  usdcPrice         uint256
     *  slot 4  usdtPrice         uint256
     *  slot 5  seller            address (20) + sold bool (1) = 21 bytes
     *  slot 6  owner             address (20)
     *  slot 7  royaltyRecipient  address (20) + listedAt uint64 (8)
     *                            + royaltyBps uint16 (2) = 30 bytes
     */
    struct MarketItem {
        uint256 tokenId;            // slot 1
        uint256 ethPrice;           // slot 2
        uint256 usdcPrice;          // slot 3
        uint256 usdtPrice;          // slot 4
        address seller;             // slot 5 ─┐ packed
        bool    sold;               //          ┘
        address owner;              // slot 6
        address royaltyRecipient;   // slot 7 ─┐ packed
        uint64  listedAt;           //          │
        uint16  royaltyBps;         //          ┘
    }

    struct TokenPrices {
        uint256 ethPrice;
        uint256 usdcPrice;
        uint256 usdtPrice;
    }

    /*//////////////////////////////////////////////////////////////
                            MAPPINGS
    //////////////////////////////////////////////////////////////*/

    mapping(uint256 => MarketItem) private s_marketItems;
    mapping(address => bool)       public  blacklistedUsers;
    mapping(uint256 => bool)       public  blacklistedTokens;

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    event MarketItemCreated(
        uint256 indexed tokenId,
        address indexed seller,
        uint256 ethPrice,
        uint256 usdcPrice,
        uint256 usdtPrice,
        uint16  royaltyBps,
        address royaltyRecipient
    );
    event MarketItemSold(
        uint256 indexed tokenId,
        address indexed seller,
        address indexed buyer,
        uint256 price,
        PaymentToken paymentToken,
        uint256 platformFee,
        uint256 royaltyFee
    );
    event MarketItemRelisted(
        uint256 indexed tokenId,
        address indexed seller,
        uint256 ethPrice,
        uint256 usdcPrice,
        uint256 usdtPrice
    );
    event ListingCancelled(uint256 indexed tokenId, address indexed seller);
    event PricesUpdated(uint256 indexed tokenId, uint256 ethPrice, uint256 usdcPrice, uint256 usdtPrice);
    event ListingPriceUpdated(uint256 oldPrice,     uint256 newPrice);
    event PlatformFeeUpdated(uint256  oldBps,       uint256 newBps);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event UserBlacklisted(address indexed user,     bool blacklisted);
    event TokenBlacklisted(uint256 indexed tokenId, bool blacklisted);
    event EmergencyWithdrawInitiated(uint256 unlockAt);
    event EmergencyWithdrawExecuted(address indexed token, uint256 amount);
    event EmergencyWithdrawCancelled();

    /*//////////////////////////////////////////////////////////////
                         CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error NFTMarketplace__InvalidPrice();
    error NFTMarketplace__InvalidListingFee();
    error NFTMarketplace__InvalidPlatformFee();
    error NFTMarketplace__InvalidRoyaltyBps();
    error NFTMarketplace__InsufficientPayment();
    error NFTMarketplace__NotForSale();
    error NFTMarketplace__NotTokenOwner();
    error NFTMarketplace__NotItemSeller();
    error NFTMarketplace__BlacklistedUser();
    error NFTMarketplace__BlacklistedToken();
    error NFTMarketplace__TokenDoesNotExist();
    error NFTMarketplace__EmergencyNotReady();
    error NFTMarketplace__InvalidAddress();
    error NFTMarketplace__AlreadySold();

    /*//////////////////////////////////////////////////////////////
                           MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier tokenExists(uint256 tokenId) {
        _tokenExists(tokenId);
        _;
    }

    function _tokenExists(uint256 tokenId) internal view {
        if (tokenId == 0 || tokenId > _tokenIds)
            revert NFTMarketplace__TokenDoesNotExist();
    }

    modifier notBlacklisted() {
        _notBlacklisted();
        _;
    }

    function _notBlacklisted() internal view {
        if (blacklistedUsers[msg.sender]) revert NFTMarketplace__BlacklistedUser();
    }

    modifier tokenNotBlacklisted(uint256 tokenId) {
        _tokenNotBlacklisted(tokenId);
        _;
    }

    function _tokenNotBlacklisted(uint256 tokenId) internal view {
        if (blacklistedTokens[tokenId]) revert NFTMarketplace__BlacklistedToken();
    }

    modifier validAddress(address addr) {
        _validAddress( addr);
        _;
    }

    function _validAddress(address addr) internal pure {
        if (addr == address(0)) revert NFTMarketplace__InvalidAddress();
    }

    /*//////////////////////////////////////////////////////////////
                          CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _usdc,
        address _usdt,
        address _feeRecipient,
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) Ownable(msg.sender) {
        if (_usdc == address(0) || _usdt == address(0) || _feeRecipient == address(0))
            revert NFTMarketplace__InvalidAddress();

        USDC         = IERC20(_usdc);
        USDT         = IERC20(_usdt);
        feeRecipient = _feeRecipient;
    }

    /*//////////////////////////////////////////////////////////////
                          ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function updateListingPrice(uint256 _listingPrice) external onlyOwner {
        if (_listingPrice > MAX_LISTING_FEE) revert NFTMarketplace__InvalidListingFee();
        emit ListingPriceUpdated(listingPrice, _listingPrice);
        listingPrice = _listingPrice;
    }

    function updatePlatformFee(uint256 _bps) external onlyOwner {
        if (_bps > 1_000) revert NFTMarketplace__InvalidPlatformFee(); // max 10 %
        emit PlatformFeeUpdated(platformFeeBps, _bps);
        platformFeeBps = _bps;
    }

    function updateFeeRecipient(address _feeRecipient)
        external onlyOwner validAddress(_feeRecipient)
    {
        emit FeeRecipientUpdated(feeRecipient, _feeRecipient);
        feeRecipient = _feeRecipient;
    }

    function setUserBlacklisted(address user, bool _blacklisted)
        external onlyOwner validAddress(user)
    {
        blacklistedUsers[user] = _blacklisted;
        emit UserBlacklisted(user, _blacklisted);
    }

    function setTokenBlacklisted(uint256 tokenId, bool _blacklisted)
        external onlyOwner tokenExists(tokenId)
    {
        blacklistedTokens[tokenId] = _blacklisted;
        emit TokenBlacklisted(tokenId, _blacklisted);
    }

    function pause()   external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    /*//////////////////////////////////////////////////////////////
                        EMERGENCY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function initiateEmergencyWithdraw() external onlyOwner {
        uint256 unlockAt         = block.timestamp + EMERGENCY_DELAY;
        emergencyWithdrawUnlockAt = unlockAt;
        emergencyWithdrawEnabled  = true;
        emit EmergencyWithdrawInitiated(unlockAt);
    }

    function cancelEmergencyWithdraw() external onlyOwner {
        emergencyWithdrawEnabled  = false;
        emergencyWithdrawUnlockAt = 0;
        emit EmergencyWithdrawCancelled();
    }

    /// @notice FIX: flag is reset after execution (original left it `true`)
    function emergencyWithdrawETH() external onlyOwner {
        _assertEmergencyReady();
        _resetEmergency();
        uint256 bal = address(this).balance;
        payable(owner()).sendValue(bal);
        emit EmergencyWithdrawExecuted(address(0), bal);
    }

    /// @notice FIX: flag is reset after execution (original left it `true`)
    function emergencyWithdrawToken(IERC20 token) external onlyOwner {
        _assertEmergencyReady();
        _resetEmergency();
        uint256 bal = token.balanceOf(address(this));
        token.safeTransfer(owner(), bal);
        emit EmergencyWithdrawExecuted(address(token), bal);
    }

    /*//////////////////////////////////////////////////////////////
                     CORE MARKETPLACE — LISTING
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Mint a new NFT and list it on the marketplace.
     * @param tokenURI        IPFS / arweave metadata URI
     * @param prices          Per-token price struct (set unused ones to 0)
     * @param royaltyBps      Royalty in basis points (max 1 000 = 10 %)
     * @param royaltyRecipient Royalty receiver (0 → msg.sender)
     */
    function createToken(
        string   calldata tokenURI,
        TokenPrices calldata prices,
        uint16   royaltyBps,
        address  royaltyRecipient
    )
        external payable
        nonReentrant whenNotPaused notBlacklisted
        returns (uint256 newTokenId)
    {
        if (msg.value != listingPrice)      revert NFTMarketplace__InvalidListingFee();
        if (!_hasValidPrice(prices))        revert NFTMarketplace__InvalidPrice();
        if (royaltyBps > MAX_ROYALTY_BPS)   revert NFTMarketplace__InvalidRoyaltyBps();
        if (royaltyRecipient == address(0)) royaltyRecipient = msg.sender;

        unchecked { newTokenId = ++_tokenIds; }

        _mint(msg.sender, newTokenId);
        _setTokenURI(newTokenId, tokenURI);
        _transfer(msg.sender, address(this), newTokenId);

        s_marketItems[newTokenId] = MarketItem({
            tokenId:          newTokenId,
            ethPrice:         prices.ethPrice,
            usdcPrice:        prices.usdcPrice,
            usdtPrice:        prices.usdtPrice,
            seller:           msg.sender,
            sold:             false,
            owner:            address(this),
            royaltyRecipient: royaltyRecipient,
            listedAt:         uint64(block.timestamp),
            royaltyBps:       royaltyBps
        });

        emit MarketItemCreated(
            newTokenId, msg.sender,
            prices.ethPrice, prices.usdcPrice, prices.usdtPrice,
            royaltyBps, royaltyRecipient
        );
    }

    /// @notice Update prices for an active listing (seller only).
    function updateItemPrices(uint256 tokenId, TokenPrices calldata prices)
        external
        nonReentrant whenNotPaused notBlacklisted
        tokenExists(tokenId) tokenNotBlacklisted(tokenId)
    {
        MarketItem storage item = s_marketItems[tokenId];
        if (item.sold)                 revert NFTMarketplace__AlreadySold();
        if (item.seller != msg.sender) revert NFTMarketplace__NotItemSeller();
        if (!_hasValidPrice(prices))   revert NFTMarketplace__InvalidPrice();

        item.ethPrice  = prices.ethPrice;
        item.usdcPrice = prices.usdcPrice;
        item.usdtPrice = prices.usdtPrice;

        emit PricesUpdated(tokenId, prices.ethPrice, prices.usdcPrice, prices.usdtPrice);
    }

    /**
     * @notice FIX (new function): Seller cancels their listing and gets the NFT back.
     *         Original contract had no way to delist — this was a critical missing feature.
     */
    function cancelListing(uint256 tokenId)
        external
        nonReentrant whenNotPaused notBlacklisted
        tokenExists(tokenId)
    {
        MarketItem storage item = s_marketItems[tokenId];
        if (item.sold)                 revert NFTMarketplace__AlreadySold();
        if (item.seller != msg.sender) revert NFTMarketplace__NotItemSeller();

        // Mark as sold so it disappears from market; owner is restored to seller.
        item.sold   = true;
        item.seller = address(0);
        item.owner  = msg.sender;
        unchecked { ++_itemsSold; }

        _transfer(address(this), msg.sender, tokenId);

        emit ListingCancelled(tokenId, msg.sender);
    }

    /**
     * @notice Re-list a previously bought (or cancelled) NFT.
     * @dev    FIX: only decrements _itemsSold if item.sold was true before call.
     */
    function resellToken(uint256 tokenId, TokenPrices calldata prices)
        external payable
        nonReentrant whenNotPaused notBlacklisted
        tokenExists(tokenId) tokenNotBlacklisted(tokenId)
    {
        if (ownerOf(tokenId) != msg.sender) revert NFTMarketplace__NotTokenOwner();
        if (msg.value != listingPrice)      revert NFTMarketplace__InvalidListingFee();
        if (!_hasValidPrice(prices))        revert NFTMarketplace__InvalidPrice();

        MarketItem storage item = s_marketItems[tokenId];
        bool wasSold = item.sold;

        item.sold      = false;
        item.ethPrice  = prices.ethPrice;
        item.usdcPrice = prices.usdcPrice;
        item.usdtPrice = prices.usdtPrice;
        item.seller    = msg.sender;
        item.owner     = address(this);
        item.listedAt  = uint64(block.timestamp);

        // FIX: guard against underflow when token reached owner via path other than marketplace sale
        if (wasSold) {unchecked { --_itemsSold; }}

        _transfer(msg.sender, address(this), tokenId);

        emit MarketItemRelisted(
            tokenId, msg.sender,
            prices.ethPrice, prices.usdcPrice, prices.usdtPrice
        );
    }

    /*//////////////////////////////////////////////////////////////
                      CORE MARKETPLACE — SALES
    //////////////////////////////////////////////////////////////*/

    function createMarketSaleETH(uint256 tokenId)
        external payable
        nonReentrant whenNotPaused notBlacklisted
        tokenExists(tokenId) tokenNotBlacklisted(tokenId)
    {
        MarketItem storage item = s_marketItems[tokenId];
        if (item.ethPrice == 0)           revert NFTMarketplace__NotForSale();
        if (msg.value != item.ethPrice)   revert NFTMarketplace__InsufficientPayment();
        _executeSaleETH(tokenId, item);
    }

    function createMarketSaleUSDC(uint256 tokenId)
        external
        nonReentrant whenNotPaused notBlacklisted
        tokenExists(tokenId) tokenNotBlacklisted(tokenId)
    {
        MarketItem storage item = s_marketItems[tokenId];
        if (item.usdcPrice == 0) revert NFTMarketplace__NotForSale();
        _executeSaleERC20(tokenId, item, item.usdcPrice, PaymentToken.USDC, USDC);
    }

    function createMarketSaleUSDT(uint256 tokenId)
        external
        nonReentrant whenNotPaused notBlacklisted
        tokenExists(tokenId) tokenNotBlacklisted(tokenId)
    {
        MarketItem storage item = s_marketItems[tokenId];
        if (item.usdtPrice == 0) revert NFTMarketplace__NotForSale();
        _executeSaleERC20(tokenId, item, item.usdtPrice, PaymentToken.USDT, USDT);
    }

    /*//////////////////////////////////////////////////////////////
                       INTERNAL SALE LOGIC
    //////////////////////////////////////////////////////////////*/

    function _executeSaleETH(uint256 tokenId, MarketItem storage item) private {
        // Cache all reads before state mutation (CEI + gas)
        address seller       = item.seller;
        address royaltyRecip = item.royaltyRecipient;
        uint256 price        = item.ethPrice;
        uint256 platformFee  = (price * platformFeeBps) / BPS_BASE;
        uint256 royaltyFee   = (price * item.royaltyBps) / BPS_BASE;
        uint256 sellerAmount;
        unchecked { sellerAmount = price - platformFee - royaltyFee; }

        // Effects
        item.owner  = msg.sender;
        item.sold   = true;
        item.seller = address(0);
        unchecked { ++_itemsSold; }

        // Interactions — NFT first, then ETH (reentrancy guard is active)
        _transfer(address(this), msg.sender, tokenId);

        if (platformFee  > 0) payable(feeRecipient).sendValue(platformFee);
        if (royaltyFee   > 0) payable(royaltyRecip).sendValue(royaltyFee);
        if (sellerAmount > 0) payable(seller).sendValue(sellerAmount);

        emit MarketItemSold(
            tokenId, seller, msg.sender, price,
            PaymentToken.ETH, platformFee, royaltyFee
        );
    }

    function _executeSaleERC20(
        uint256 tokenId,
        MarketItem storage item,
        uint256 price,
        PaymentToken paymentToken,
        IERC20 token
    ) private {
        address seller       = item.seller;
        address royaltyRecip = item.royaltyRecipient;
        uint256 platformFee  = (price * platformFeeBps) / BPS_BASE;
        uint256 royaltyFee   = (price * item.royaltyBps) / BPS_BASE;
        uint256 sellerAmount;
        unchecked { sellerAmount = price - platformFee - royaltyFee; }

        item.owner  = msg.sender;
        item.sold   = true;
        item.seller = address(0);
        unchecked { ++_itemsSold; }

        _transfer(address(this), msg.sender, tokenId);

        if (platformFee  > 0) token.safeTransferFrom(msg.sender, feeRecipient, platformFee);
        if (royaltyFee   > 0) token.safeTransferFrom(msg.sender, royaltyRecip,  royaltyFee);
        if (sellerAmount > 0) token.safeTransferFrom(msg.sender, seller,        sellerAmount);

        emit MarketItemSold(
            tokenId, seller, msg.sender, price,
            paymentToken, platformFee, royaltyFee
        );
    }

    /*//////////////////////////////////////////////////////////////
                    VIEW / QUERY FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice FIX: Original had array over-allocated (blacklisted tokens skipped but
     *         counted), leaving trailing zero-value structs. Now uses two-pass count.
     */
    function fetchMarketItems() external view returns (MarketItem[] memory) {
        uint256 total = _tokenIds;
        uint256 count = 0;
        for (uint256 i = 1; i <= total;) {
            if (s_marketItems[i].owner == address(this) && !blacklistedTokens[i]) {
                unchecked { ++count; }}
            unchecked { ++i; }
        }

        MarketItem[] memory items = new MarketItem[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i <= total;) {
            if (s_marketItems[i].owner == address(this) && !blacklistedTokens[i])
                items[idx++] = s_marketItems[i];
            unchecked { ++i; }
        }
        return items;
    }

    function fetchMyNFTs() external view returns (MarketItem[] memory) {
        uint256 total = _tokenIds;
        uint256 count = 0;
        for (uint256 i = 1; i <= total;) {
            if (s_marketItems[i].owner == msg.sender) {unchecked { ++count; }}
            unchecked { ++i; }
        }

        MarketItem[] memory items = new MarketItem[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i <= total;) {
            if (s_marketItems[i].owner == msg.sender) items[idx++] = s_marketItems[i];
            unchecked { ++i; }
        }
        return items;
    }

    function fetchItemsListed() external view returns (MarketItem[] memory) {
        uint256 total = _tokenIds;
        uint256 count = 0;
        for (uint256 i = 1; i <= total;) {
            if (s_marketItems[i].seller == msg.sender) {unchecked { ++count; }}
            unchecked { ++i; }
        }

        MarketItem[] memory items = new MarketItem[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i <= total;) {
            if (s_marketItems[i].seller == msg.sender) items[idx++] = s_marketItems[i];
            unchecked { ++i; }
        }
        return items;
    }

    function getMarketItem(uint256 tokenId)
        external view tokenExists(tokenId)
        returns (MarketItem memory)
    {
        return s_marketItems[tokenId];
    }

    function getListingPrice() external view returns (uint256) { return listingPrice; }
    function getTotalTokens()  external view returns (uint256) { return _tokenIds;    }
    function getTotalSold()    external view returns (uint256) { return _itemsSold;   }

    /*//////////////////////////////////////////////////////////////
                         EIP-2981 ROYALTIES
    //////////////////////////////////////////////////////////////*/

    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external view override
        returns (address receiver, uint256 royaltyAmount)
    {
        MarketItem storage item = s_marketItems[tokenId];
        receiver      = item.royaltyRecipient;
        royaltyAmount = (salePrice * item.royaltyBps) / BPS_BASE;
    }

    /*//////////////////////////////////////////////////////////////
                       INTERFACE SUPPORT
    //////////////////////////////////////////////////////////////*/

    function supportsInterface(bytes4 interfaceId)
        public view override(ERC721URIStorage, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC2981).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /*//////////////////////////////////////////////////////////////
                      PRIVATE HELPERS
    //////////////////////////////////////////////////////////////*/

    function _hasValidPrice(TokenPrices calldata p) private pure returns (bool) {
        return p.ethPrice > 0 || p.usdcPrice > 0 || p.usdtPrice > 0;
    }

    function _assertEmergencyReady() private view {
        if (!emergencyWithdrawEnabled || block.timestamp < emergencyWithdrawUnlockAt)
            revert NFTMarketplace__EmergencyNotReady();
    }

    function _resetEmergency() private {
        emergencyWithdrawEnabled  = false;
        emergencyWithdrawUnlockAt = 0;
    }

    /// @dev Accept ETH (listing fees accumulate here)
    receive() external payable {}
}
