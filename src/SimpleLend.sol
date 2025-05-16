//SPDX-License-Identifier: MIT

pragma solidity 0.8.26;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SToken} from "./SToken.sol";
import {Test, console} from "forge-std/Test.sol";

/**
 * @title SimpleLend
 * @author D
 * @notice This contract implements a basic lending protocol.
 */

//to dos
//natspecler
//readme

contract SimpleLend is Ownable {
    error SimpleLend__SupplyFailed(address user, address token, uint256 amount);
    error SimpleLend__WithdrawFailed(
        address user,
        address token,
        uint256 amount
    );
    error SimpleLend__AddCollateralFailed(
        address user,
        address token,
        uint256 amount
    );
    error SimpleLend__TokenIsNotSupportedForSupply(address token);
    error SimpleLend__InsufficientBalanceForWithdraw(
        address user,
        address token,
        uint256 userBalance
    );
    error SimpleLend__InsufficientCollateral(
        address user,
        uint256 healthFactor
    );
    error SimpleLend__BorrowingFailed(
        address user,
        address borrowToken,
        address collateralToken
    );
    error SimpleLend__LiquidationFailed(address user, address liquidator);
    error SimpleLend__RepayFailed(
        address user,
        address borrowToken,
        address collateralToken
    );
    error SimpleLend__TokenIsNotSupportedForCollateral(address token);
    error SimpleLend__TokenIsNotSupportedForBorrow(address token);
    error SimpleLend__CollateralAndBorrowTokenMismatch(
        address collateral,
        address borrow
    );
    error SimpleLend__CantUseSameCollateral(address user, address collateral);
    error SimpleLend__WithdrawCollateralFailed(
        address user,
        address token,
        uint256 amount
    );
    error SimpleLend__LiquidationFailedUsersPositionCantLiquidate(
        address user,
        address liquidator,
        uint256 healthFactor
    );
    error SimpleLend__BorrowTokenMismatch(address user, address token);

    //EVENTS
    event UserSupplied(
        address user,
        address supplyTokenAddress,
        uint256 amount
    );
    event UserWithdrawed(
        address user,
        address withdrawTokenAddress,
        uint256 amount
    );
    event UserLiquidated(
        address liquidator,
        address user,
        uint256 healthFactor
    );
    event UserBorrowed(
        address user,
        address collateralAddress,
        address borrowAddress,
        uint256 collateralAmount,
        uint256 borrowAmount
    );
    event UserAddedCollateral(
        address user,
        address collateralAddress,
        uint256 collateralAmount
    );
    event UserSwitchedSupplyToCollateral(
        address user,
        address token,
        uint256 amount
    );
    event UserRepaid(
        address user,
        address collateralAddress,
        address borrowAddress
    );
    event UserWithdrawedCollateral(address user, address token, uint256 amount);

    mapping(address collateralToken => address priceFeed) public s_priceFeeds;
    mapping(address user => mapping(address supplyTokenAddress => uint256 amount))
        public s_userDeposited;
    mapping(address user => mapping(address supplyTokenAddress => uint256 time))
        public s_userDepositTime;
    mapping(address user => mapping(address borrowTokenAddress => uint256 time))
        public s_userBorrowTime;
    mapping(address token => address sToken) public s_tokenToSToken;
    mapping(address token => bool isAllowed) public s_allowedCollateralTokens;
    mapping(address token => bool isAllowed) public s_allowedBorrowTokens;
    mapping(address => uint256) public s_collateralRatios;
    mapping(address => bool) public s_allowedCollaterals;
    mapping(address user => mapping(address token => uint256 amount))
        public s_collateralInUse;
    mapping(address user => mapping(address token => uint256 amount))
        public s_userBorrows;
    mapping(address user => mapping(address collateral => address borrow))
        public s_userCollateralTokenToBorrowToken;

    uint256 public constant INTEREST_PRECISION = 1_000;
    uint256 public constant INTEREST_FOR_SUPPLY = 300;
    uint256 public constant INTEREST_FOR_BORROW = 5;
    uint256 public constant HEALTH_FACTOR = 1e18;

    uint256 private constant LIQUIDATION_BONUS = 110;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant FEED_PRECISION = 1e8;

    modifier isAllowedTokenForCollateral(address token) {
        if (!s_allowedCollateralTokens[token]) {
            revert SimpleLend__TokenIsNotSupportedForCollateral(token);
        }
        _;
    }

    modifier isAllowedTokenForBorrow(address token) {
        if (!s_allowedBorrowTokens[token]) {
            revert SimpleLend__TokenIsNotSupportedForBorrow(token);
        }
        _;
    }

    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses
    ) Ownable(msg.sender) {
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
    }

    /**
     * @param supplyTokenAddress Address of the Supply Token
     *  @param amount Amount of the Supply Token
     */
    function supply(address supplyTokenAddress, uint256 amount) external {
        if (s_tokenToSToken[supplyTokenAddress] == address(0)) {
            revert SimpleLend__TokenIsNotSupportedForSupply(supplyTokenAddress);
        }

        s_userDeposited[msg.sender][supplyTokenAddress] += amount;
        s_userDepositTime[msg.sender][supplyTokenAddress] = block.timestamp;

        emit UserSupplied(msg.sender, supplyTokenAddress, amount);

        address sToken = s_tokenToSToken[supplyTokenAddress];

        SToken(sToken).mint(msg.sender, amount);

        bool success = IERC20(supplyTokenAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );

        require(
            success,
            SimpleLend__SupplyFailed(msg.sender, supplyTokenAddress, amount)
        );
    }

    /**
     * @param withdrawTokenAddress Address of the token the user wants to withdraw.
     * @param amount Amount of the withdraw token.
     */
    function withdraw(address withdrawTokenAddress, uint256 amount) external {
        address sToken = s_tokenToSToken[withdrawTokenAddress];

        require(
            sToken != address(0),
            SimpleLend__TokenIsNotSupportedForSupply(withdrawTokenAddress)
        );

        uint256 userSupplyInterest = getInterestRateForSupply(
            msg.sender,
            withdrawTokenAddress
        );

        if (userSupplyInterest > 0)
            SToken(sToken).mint(msg.sender, userSupplyInterest);

        uint256 userBalance = SToken(sToken).balanceOf(msg.sender);

        if (amount == type(uint256).max) {
            amount = userBalance;
        }

        require(
            userBalance >= amount,
            SimpleLend__InsufficientBalanceForWithdraw(
                msg.sender,
                withdrawTokenAddress,
                userBalance
            )
        );

        SToken(sToken).burnFrom(msg.sender, amount);

        emit UserWithdrawed(msg.sender, withdrawTokenAddress, amount);

        bool success = IERC20(withdrawTokenAddress).transfer(
            msg.sender,
            amount
        );

        require(
            success,
            SimpleLend__WithdrawFailed(msg.sender, withdrawTokenAddress, amount)
        );
    }

    /**
     * @param borrowTokenAddress The address of the token the user wants to borrow.
     * @param borrowTokenAmount Amount of the borrow.
     * @param collateralAddress The address of the user's collateral
     * @param collateralAmountForBorrow Amount of the collateral.
     */
    function borrow(
        address borrowTokenAddress,
        uint256 borrowTokenAmount,
        address collateralAddress,
        uint256 collateralAmountForBorrow
    )
        external
        isAllowedTokenForBorrow(borrowTokenAddress)
        isAllowedTokenForCollateral(collateralAddress)
    {
        require(
            s_collateralInUse[msg.sender][collateralAddress] == 0,
            SimpleLend__CantUseSameCollateral(msg.sender, collateralAddress)
        );

        uint256 userHealthFactor = getHealthFactorWithAmounts(
            collateralAddress,
            collateralAmountForBorrow,
            borrowTokenAddress,
            borrowTokenAmount
        );

        require(
            userHealthFactor >= HEALTH_FACTOR,
            SimpleLend__InsufficientCollateral(msg.sender, userHealthFactor)
        );

        s_userCollateralTokenToBorrowToken[msg.sender][
            collateralAddress
        ] = borrowTokenAddress;

        s_collateralInUse[msg.sender][
            collateralAddress
        ] += collateralAmountForBorrow;

        s_userBorrowTime[msg.sender][borrowTokenAddress] = block.timestamp;

        s_userBorrows[msg.sender][borrowTokenAddress] += borrowTokenAmount;

        emit UserBorrowed(
            msg.sender,
            collateralAddress,
            borrowTokenAddress,
            collateralAmountForBorrow,
            borrowTokenAmount
        );

        bool successForCollateral = IERC20(collateralAddress).transferFrom(
            msg.sender,
            address(this),
            collateralAmountForBorrow
        );

        require(
            successForCollateral,
            SimpleLend__BorrowingFailed(
                msg.sender,
                borrowTokenAddress,
                collateralAddress
            )
        );

        bool success = IERC20(borrowTokenAddress).transfer(
            msg.sender,
            borrowTokenAmount
        );

        require(
            success,
            SimpleLend__BorrowingFailed(
                msg.sender,
                borrowTokenAddress,
                collateralAddress
            )
        );
    }

    /**
     * @param borrowTokenAddress The address of the token the user wants to borrow.
     * @param borrowTokenAmount Amount of the borrow.
     * @param collateralAddress The address of the user's collateral
     * @notice Users can only use this function if they have already borrowed the token, and they should borrow the same one.
     */
    function borrowMore(
        address borrowTokenAddress,
        uint256 borrowTokenAmount,
        address collateralAddress
    )
        external
        isAllowedTokenForBorrow(borrowTokenAddress)
        isAllowedTokenForCollateral(collateralAddress)
    {
        require(
            s_userCollateralTokenToBorrowToken[msg.sender][collateralAddress] ==
                borrowTokenAddress,
            SimpleLend__BorrowTokenMismatch(msg.sender, borrowTokenAddress)
        );

        uint256 collateralAmountForBorrow = s_collateralInUse[msg.sender][
            collateralAddress
        ];

        uint256 userAlreadyBorrow = s_userBorrows[msg.sender][
            borrowTokenAddress
        ];

        if (userAlreadyBorrow == 0) {
            revert SimpleLend__BorrowingFailed(
                msg.sender,
                borrowTokenAddress,
                collateralAddress
            );
        }

        uint256 userHealthFactor = getHealthFactorWithAmounts(
            collateralAddress,
            collateralAmountForBorrow,
            borrowTokenAddress,
            borrowTokenAmount + userAlreadyBorrow
        );

        require(
            userHealthFactor >= HEALTH_FACTOR,
            SimpleLend__InsufficientCollateral(msg.sender, userHealthFactor)
        );

        s_userBorrows[msg.sender][borrowTokenAddress] += borrowTokenAmount;

        bool success = IERC20(borrowTokenAddress).transfer(
            msg.sender,
            borrowTokenAmount
        );

        require(
            success,
            SimpleLend__BorrowingFailed(
                msg.sender,
                borrowTokenAddress,
                collateralAddress
            )
        );
    }

    /**
     * @param collateralAddress The address of the user's collateral
     * @param borrowToken The address of the token the user wants to borrow.
     * @param amount Amount of the collateral.
     * @notice Users can only use this function if they have already borrowed the token, and they should deposit the collateral to the same one.
     */
    function addCollateralForBorrow(
        address collateralAddress,
        address borrowToken,
        uint256 amount
    ) external isAllowedTokenForCollateral(collateralAddress) {
        require(
            s_userCollateralTokenToBorrowToken[msg.sender][collateralAddress] ==
                borrowToken,
            SimpleLend__CollateralAndBorrowTokenMismatch(
                collateralAddress,
                borrowToken
            )
        );
        s_collateralInUse[msg.sender][collateralAddress] += amount;

        emit UserAddedCollateral(msg.sender, collateralAddress, amount);

        bool success = IERC20(collateralAddress).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(
            success,
            SimpleLend__AddCollateralFailed(
                msg.sender,
                collateralAddress,
                amount
            )
        );
    }

    /**
     * @param supplyTokenAddress The address of the supply token.
     * @param borrowAddress The address of the token the user's borrow.
     * @param amount Amount of the collateral.
     * @notice Users can only use this function if they have already borrowed the token, and they should switch supply to the same one.
     */
    function switchSupplyToCollateral(
        address supplyTokenAddress,
        address borrowAddress,
        uint256 amount
    ) public isAllowedTokenForCollateral(supplyTokenAddress) {
        require(
            s_userCollateralTokenToBorrowToken[msg.sender][
                supplyTokenAddress
            ] == borrowAddress,
            SimpleLend__CollateralAndBorrowTokenMismatch(
                supplyTokenAddress,
                borrowAddress
            )
        );

        s_collateralInUse[msg.sender][supplyTokenAddress] += amount;
        emit UserSwitchedSupplyToCollateral(
            msg.sender,
            supplyTokenAddress,
            amount
        );

        SToken(s_tokenToSToken[supplyTokenAddress]).burnFrom(
            msg.sender,
            amount
        );
    }

    /**
     * @param collateralAddress The address of the user's collateral.
     * @param borrowToken The address of the token the user's borrow.
     */
    function repay(address collateralAddress, address borrowToken) external {
        require(
            s_userCollateralTokenToBorrowToken[msg.sender][collateralAddress] ==
                borrowToken,
            SimpleLend__CollateralAndBorrowTokenMismatch(
                collateralAddress,
                borrowToken
            )
        );

        uint256 borrowAmount = s_userBorrows[msg.sender][borrowToken];
        uint256 collateralAmount = s_collateralInUse[msg.sender][
            collateralAddress
        ];

        uint256 borrowInterest = getInterestRateForBorrow(
            msg.sender,
            borrowToken
        );

        emit UserRepaid(msg.sender, collateralAddress, borrowToken);

        bool success = IERC20(borrowToken).transferFrom(
            msg.sender,
            address(this),
            borrowAmount + borrowInterest
        );
        require(
            success,
            SimpleLend__RepayFailed(msg.sender, borrowToken, collateralAddress)
        );

        bool successCollateral = IERC20(collateralAddress).transfer(
            msg.sender,
            collateralAmount
        );
        require(
            successCollateral,
            SimpleLend__RepayFailed(msg.sender, borrowToken, collateralAddress)
        );

        delete s_collateralInUse[msg.sender][collateralAddress];
        delete s_userBorrows[msg.sender][borrowToken];
        delete s_userCollateralTokenToBorrowToken[msg.sender][
            collateralAddress
        ];
    }

    /**
     * @param user The user who will be liquidated.
     * @param collateralAddress The address of the user's collateral
     * @param borrowAddress The address of the token the user's borrow.
     * @notice Liquidators can only liquidate someone if they're below the health factor and if their collateral's value is not below their borrow's value.
     */
    function liquidate(
        address user,
        address collateralAddress,
        address borrowAddress
    ) external {
        require(
            s_userCollateralTokenToBorrowToken[user][collateralAddress] ==
                borrowAddress,
            SimpleLend__CollateralAndBorrowTokenMismatch(
                collateralAddress,
                borrowAddress
            )
        );

        uint256 collateralAmount = s_collateralInUse[user][collateralAddress];
        uint256 borrowAmount = s_userBorrows[user][borrowAddress];

        (
            uint256 userCollateralInUsd,
            uint256 userBorrowInUsd
        ) = getUserBorrowAndCollateralInUsd(
                collateralAddress,
                borrowAddress,
                collateralAmount,
                borrowAmount
            );

        uint256 healthFactor = getHealthFactorWithAmounts(
            collateralAddress,
            collateralAmount,
            borrowAddress,
            borrowAmount
        );

        require(
            healthFactor < HEALTH_FACTOR,
            SimpleLend__LiquidationFailedUsersPositionCantLiquidate(
                user,
                msg.sender,
                healthFactor
            )
        );

        uint256 collateralTokenPrice = getPriceFeedInUsd(collateralAddress, 1);

        uint256 borrowAmountWithBonusInUsd = (userBorrowInUsd *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        require(
            userCollateralInUsd > borrowAmountWithBonusInUsd,
            SimpleLend__LiquidationFailedUsersPositionCantLiquidate(
                user,
                msg.sender,
                healthFactor
            )
        );

        uint256 liquidatorWillHave = (borrowAmountWithBonusInUsd) /
            collateralTokenPrice;

        emit UserLiquidated(msg.sender, user, healthFactor);

        bool succesBorrow = IERC20(borrowAddress).transferFrom(
            msg.sender,
            address(this),
            borrowAmount
        );

        require(succesBorrow, SimpleLend__LiquidationFailed(user, msg.sender));

        bool success = IERC20(collateralAddress).transfer(
            msg.sender,
            liquidatorWillHave
        );

        require(success, SimpleLend__LiquidationFailed(user, msg.sender));

        delete s_collateralInUse[user][collateralAddress];
        delete s_userBorrows[user][borrowAddress];
        delete s_userCollateralTokenToBorrowToken[user][collateralAddress];
    }

    /**
     * @param collateralAddress The address of the user's collateral.
     * @param borrowAddress The address of the token the user's borrow.
     * @param collateralAmount Amount of the collateral for withdraw.
     * @notice Users can only use this function if they have already borrowed the token and will not be below the health factor.
     */
    function withdrawCollateral(
        address collateralAddress,
        address borrowAddress,
        uint256 collateralAmount
    ) external isAllowedTokenForCollateral(collateralAddress) {
        require(
            s_userCollateralTokenToBorrowToken[msg.sender][collateralAddress] ==
                borrowAddress,
            SimpleLend__CollateralAndBorrowTokenMismatch(
                collateralAddress,
                borrowAddress
            )
        );

        uint256 borrowAmount = s_userBorrows[msg.sender][borrowAddress];
        uint256 userCollateralAmount = s_collateralInUse[msg.sender][
            collateralAddress
        ];

        uint256 healthFactor = getHealthFactorWithAmounts(
            collateralAddress,
            userCollateralAmount - collateralAmount,
            borrowAddress,
            borrowAmount
        );

        require(
            healthFactor >= HEALTH_FACTOR,
            SimpleLend__InsufficientCollateral(msg.sender, healthFactor)
        );

        s_collateralInUse[msg.sender][collateralAddress] -= collateralAmount;

        emit UserWithdrawedCollateral(
            msg.sender,
            collateralAddress,
            collateralAmount
        );

        bool success = IERC20(collateralAddress).transfer(
            msg.sender,
            collateralAmount
        );

        require(
            success,
            SimpleLend__WithdrawCollateralFailed(
                msg.sender,
                collateralAddress,
                collateralAmount
            )
        );
    }

    function calculateHealthFactor(
        address collateralAddress,
        uint256 collateralInUsd,
        uint256 borrowAmountInUsd
    ) public view returns (uint256 healthFactor) {
        uint256 collateralRatio = s_collateralRatios[collateralAddress];
        uint256 userCollateral = ((collateralInUsd * collateralRatio) / 100);
        healthFactor = (userCollateral * PRECISION) / borrowAmountInUsd;
    }

    function getInterestRateForBorrow(
        address user,
        address borrowToken
    ) public view returns (uint256 borrowInterest) {
        uint256 borrowAmount = s_userBorrows[user][borrowToken];
        uint256 borrowTime = s_userBorrowTime[user][borrowToken];
        uint256 dayPassed = (block.timestamp - borrowTime) / 1 days;
        if (dayPassed < 1) dayPassed = 1;

        borrowInterest =
            ((borrowAmount * INTEREST_FOR_BORROW) / INTEREST_PRECISION) *
            dayPassed;
    }

    function getInterestRateForSupply(
        address user,
        address supplyToken
    ) public view returns (uint256 interestAmount) {
        uint256 userSTokenBalance = SToken(supplyToken).balanceOf(user);
        uint256 userDepositTime = s_userDepositTime[user][supplyToken];
        uint256 dayPassed = (block.timestamp - userDepositTime) / 1 days;

        interestAmount =
            ((userSTokenBalance * INTEREST_FOR_SUPPLY) / INTEREST_PRECISION) *
            dayPassed;
    }

    function getPriceFeedInUsd(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return
            ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getHealthFactorWithAmounts(
        address collateralAddress,
        uint256 collateralAmount,
        address borrowAddress,
        uint256 borrowAmount
    ) public view returns (uint256 userHealthFactor) {
        (
            uint256 userCollateralInUsd,
            uint256 userBorrowInUsd
        ) = getUserBorrowAndCollateralInUsd(
                collateralAddress,
                borrowAddress,
                collateralAmount,
                borrowAmount
            );

        userHealthFactor = calculateHealthFactor(
            collateralAddress,
            userCollateralInUsd,
            userBorrowInUsd
        );
    }

    function getUserBorrowAndCollateralInUsd(
        address collateralAddress,
        address borrowAddress,
        uint256 collateralAmount,
        uint256 borrowAmount
    )
        public
        view
        returns (uint256 userCollateralInUsd, uint256 userBorrowInUsd)
    {
        userCollateralInUsd = getPriceFeedInUsd(
            collateralAddress,
            collateralAmount
        );
        userBorrowInUsd = getPriceFeedInUsd(borrowAddress, borrowAmount);
    }

    function getUserHealthFactor(
        address user,
        address borrowToken,
        address collateralToken
    ) public view returns (uint256 healthFactor) {
        require(
            s_userCollateralTokenToBorrowToken[user][collateralToken] ==
                borrowToken,
            SimpleLend__CollateralAndBorrowTokenMismatch(
                collateralToken,
                borrowToken
            )
        );

        uint256 borrowAmount = s_userBorrows[user][borrowToken];
        uint256 collateralAmount = s_collateralInUse[user][collateralToken];

        healthFactor = getHealthFactorWithAmounts(
            collateralToken,
            collateralAmount,
            borrowToken,
            borrowAmount
        );
    }

    //OWNER FUNCTIONS
    function deploySToken(
        address token,
        address tokenPriceFeedAddress,
        string memory symbol,
        string memory name
    ) external onlyOwner returns (address) {
        require(s_tokenToSToken[token] == address(0), "revert");
        SToken _sToken = new SToken(token, symbol, name);
        s_tokenToSToken[token] = address(_sToken);

        if (s_priceFeeds[token] == address(0)) {
            s_priceFeeds[token] = tokenPriceFeedAddress;
        }

        return address(_sToken);
    }

    function setAllowedCollateralToken(
        address tokenAddress,
        address tokenPriceFeedAddress,
        bool isAllowed
    ) external onlyOwner {
        s_allowedCollateralTokens[tokenAddress] = isAllowed;
        if (s_priceFeeds[tokenAddress] == address(0)) {
            s_priceFeeds[tokenAddress] = tokenPriceFeedAddress;
        }
    }

    function setAllowedBorrowToken(
        address tokenAddress,
        address tokenPriceFeedAddress,
        bool isAllowed
    ) external onlyOwner {
        s_allowedBorrowTokens[tokenAddress] = isAllowed;
        if (s_priceFeeds[tokenAddress] == address(0)) {
            s_priceFeeds[tokenAddress] = tokenPriceFeedAddress;
        }
    }

    function setTokenCollateralRatio(
        address token,
        uint256 ratio
    ) external onlyOwner {
        s_collateralRatios[token] = ratio;
    }
}
