//SPDX-License-Identifier:MIT

pragma solidity ^0.8.19;

import {DefiStableCoin} from "./DefiStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCLogic is ReentrancyGuard {
    ////////////////
    // Errors  //
    ///////////////
    error DSCLogic__NeedsMoreThanZero();
    error DSCLogic__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCLogic__NotAllowedToken();
    error DSCLogic__TransferFailed();
    error DSCLogic__BreaksHealthFactor(uint256 healthFactor);
    error DSCLogic__MintFailed();

    /////////////////
    // State Variables //
    ///////////////

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; 
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // need to be 200 % over collateral 
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    // token address is match to priceFeed address

    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    // map user balances to mapping of token which map to amount token that they have.

    mapping(address user => uint256 amountDscMinted ) private s_DSCMinted; 
    // keep track of how much DSC is being minted by an user. 
    address[] private s_collateralTokens;

    DefiStableCoin private immutable i_dsc;

    /////////////////
    // Events //
    ///////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);


    /////////////////
    // Modifiers  //
    ///////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCLogic__NeedsMoreThanZero();
        }

        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCLogic__NotAllowedToken();
        }
        _;
    }

    /////////////////
    // Functions  //
    ///////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCLogic__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }
        // loop through token address array
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i]; // set price feed so token of i EQUAL priceFeed of I .. Set up what tokens are allow.
                // if token have a priceFeed then it's allow..
                s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DefiStableCoin(dscAddress);
    }

    /////////////////
    // External Functions  //
    ///////////////

    function depositCollateralAndMintDsc() external {}

    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        // Emit an event since we are updated a State .  Updated collateral, internally 
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        // emit collateral deposited the person who is deposited, token address and colllateral amount 
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this),amountCollateral);
        if (!success){
            revert DSCLogic__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function burnDsc() external {}
    /*
    * @param amountDscToMint = The amount of Decentralized stablecoin to mint
    * must have more collateral value than min Threshold.
    // check if Collateral value is greater than DSC amount.
    // need to check price feed , values, and etc. 
    */ 
    function mintDsc(uint256 amountDscToMint) external moreThanZero (amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCLogic__MintFailed();
        }

    }

    function liquidate() external {}

    function getHealthFactor() external view {}

    /////////////////
    // Private & Internal View Functions  //
    ///////////////

    /*
    * _health factor Returns how CLOSE to liquidation a user is
    *If a user goes below 1, then they can get liquidated. 
    * this is use to figure out ratio of Collateral to USDC that a user can have. 
    */

    function _getAccountInformation (address user) private view returns (uint256 totalDscMinted, uint256 collateralValueInUsd){
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);

    }

    function _healthFactor(address user) private view returns (uint256){

        // total DSC minted
        // total collateral VALUE
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted; 

    }
    function _revertIfHealthFactorIsBroken(address user) internal view {
        //1. Check health Factor ( do they have enough collateral ?)
        //2. Revert if they don't have a good health factor 
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCLogic__BreaksHealthFactor(userHealthFactor);
        }

    }
       /////////////////
    // Public & External View Functions  //
    ///////////////
    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for(uint256 i = 0; i < s_collateralTokens.length; i++){
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
        
    }
    function getUsdValue(address token, uint256 amount) public view returns(uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.latestRoundData();
        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / 1e18;

        // 1 ETH = $1000
        // The returned value from CL will be 1000 * 1e18
        

    }

}
