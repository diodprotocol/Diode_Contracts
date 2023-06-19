// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

// Uncomment this line to use console.log
import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";


    // -----------------
    //  Interfaces
    // -----------------


interface AggregatorV3Interface {
    function latestRoundData() external view returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

interface IStrategy {
    function deposit(address token, uint256 amount) external;
    function withdraw() external returns (uint256);
    function getSupplyAPY() external view returns (uint256);
}

    // -----------------
    //  Contract
    // -----------------


contract Diode is ERC721, Ownable {

    using SafeERC20 for IERC20;
    using Math for uint256;


    // -----------------
    //  State Variables
    // -----------------

    uint256 public startTime;                /// @dev Time when pool will be open for deposits.
    uint256 public finalTime;                /// @dev Time at which pool will be closed (and open for withdrawals).
    uint256 public duration;                 /// @dev Total duration of the pool.
    uint256 public endPrice;                 /// @dev Price of underlying asset at "finalTime".
    uint256 public totalRewards;             /// @dev Rewards earned over period (finalTime - startTime) from the underlying strategy.
    uint256 public tokenCount;               /// @dev Will increase with each ERC721 token minted.
    uint256 public totalDeposits;            /// @dev Total amount of underlying asset provided to the pool.
    uint256 public totalDepositsLONG;        /// @dev Total amount of underlying asset which were provided with a 'long' position.
    uint256 public totalDepositsSHORT;       /// @dev Total amount of underlying asset which were provided with a 'short' position.
    uint256 public totalReturnedFromStrat;   /// @dev Amount returned from strategy at "finalTime" if: amount received < totalDeposits.
    uint256 public feesCollected;            /// @dev Fees collected upon withdrawal from pool.
    uint256[2] public capLongShort;          /// @dev Max "long" and max "shorts" amounts possible to provide to the pool.

    /// @dev in BIPS
    uint256 public withdrawFees;             /// @dev Fees percentage in BIPS.

    /// @dev Base 18 variables
    uint256 public alphaLongs;               /// @dev Total long deposits weighted according to their contracted option.
                                             /// i.e. related to their time of deposit and risk taken on price position.
    uint256 public alphaShorts;              /// @dev Total short deposits weighted according to their contracted option.
                                             /// i.e. related to their time of deposit and risk taken on price position.

    /// @dev Base 9 variables
    uint256 public strikePrice;              /// @dev The price on which long and short positions will be settled at "finalTime". 
    uint256 public deltaPrice;               /// @dev Factor of risk taken on price position.

    address public stratContract;            /// @dev Address of the contract of the underlying strategy.
    address public suppliedAsset;            /// @dev Asset provided to the pool.
    address public chainlinkPriceFeed;       /// @dev Address of Chainlink's price feed.

    bool public poolIsClosed;                /// @dev Returns "true" when pool is closed after "finalTime".
    bool public strategyActivated;           /// @dev Returns "true" when the underlying strategy has been set.

    struct UserDeposit {
        uint256 amount;                      /// @dev Amount of underlying token deposited. 
        uint256 assetPrice;                  /// @dev Price of underlying asset at moment of deposit (9 decimals).
        bool longOrShort;                    /// @dev true = long position, false = short position.
        uint256 alpha;                       /// @dev Deposit amount weighted according to the contracted option (18 decimals).
                                             /// i.e. related to their time of deposit and risk taken on price position.
    }

    mapping(uint256 => UserDeposit) public tokenToPosition;  /// @dev The order is tokenID -> UserDeposit.


    // -----------------
    //    Constructor
    // -----------------


    /// @notice Initializes the Diode pool.
    /// @param _strikePrice strike price for the supplied asset at the end of duration of the pool, (base 9).
    /// @param _asset address of the asset supplied to the pool.
    /// @param _duration duration for this contract in seconds.
    /// @param _deltaPrice the risk factor used by the contract to scale the pricing risk (base 9)
    /// @param _chainlinkPriceFeed  contract address of the chainlink price feed for supplied asset.
    /// @param _fees fees in BIPS to collect on withdrawal (only collected on "winning" withdrawals).
    /// @param _capLongShort max amount of tokens investable in either long or short position.
    /// @param _name name of the ERC721 token.
    /// @param _symbol symbol of the ERC721 token.


    constructor(
        uint256 _strikePrice, 
        address _asset,
        uint256 _duration,
        uint256 _startTime,
        uint256 _deltaPrice,
        address _chainlinkPriceFeed,
        uint256 _fees,
        uint256[2] memory _capLongShort,
        string memory _name,
        string memory _symbol
    ) 
        ERC721(_name, _symbol)
    {
        require(_fees <= 3000, "Max fee is 30%");
        require(_startTime >= block.timestamp, "startTime can't be in the past");
        suppliedAsset = _asset;
        strikePrice = _strikePrice;
        chainlinkPriceFeed = _chainlinkPriceFeed;
        duration = _duration;
        startTime = _startTime;
        finalTime = _startTime + _duration;
        deltaPrice = _deltaPrice;
        withdrawFees = _fees;
        capLongShort = _capLongShort;
        // Here we are using tx.origin as pools are being deployed via a factory
        transferOwnership(tx.origin);
    }


    // -----------------
    //    Functions
    // -----------------

    /// @notice Will set the address of the strategy of the pool.
    /// @param _strat address of the underlying strategy.
    /// @dev This function should only be called once.
    function setStrategy(address _strat) external {
        require(strategyActivated == false, "Strategy already set for pool");
        strategyActivated = true;
        stratContract = _strat;
    }

    /// @notice Deposits funds in the contract and mints an ERC721 with details of contracted option.
    /// @param  amount               Amount of underlying token to deposit.
    /// @param  longShort            Long or short position on "strikePrice".
    /// @return _computedRisk        Price risk taken on the position.
    /// @return _alpha               Deposit amount weighted according to the contracted option (price and time-risk).
    /// @return _standardizedPrice   Price returned from Chainlink in 9 decimals.
    /// @return _standardizedAmount  Amount of underlying asset deposited with 9 decimals.
    function depositFunds(uint256 amount, bool longShort) public returns (
        uint256 _computedRisk, 
        uint256 _alpha, 
        uint256 _standardizedPrice, 
        uint256 _standardizedAmount
    ) 
    {
        require(block.timestamp >= startTime, "block.timestamp <= startTime");
        if (longShort == true) {
            require(totalDepositsLONG + amount <= capLongShort[0], "Max amount for long positions exceeded");
        } else {
            require(totalDepositsSHORT + amount <= capLongShort[1], "Max amount for short positions exceeded");
        }
        (,int price,,,) = AggregatorV3Interface(chainlinkPriceFeed).latestRoundData();
        require(price > 0);
        totalDeposits += amount;
        uint256 convertedPrice = uint256(price);
        uint256 memoryAmount = amount;
        uint256 standardizedPrice = standardizeBase9Chainlink(convertedPrice);
        uint256 computedPriceRisk = computePriceRisk(standardizedPrice, longShort);
        uint256 standardizedAmount = standardizeBase9(amount, suppliedAsset);
        uint256 alpha = (standardizedAmount * computedPriceRisk * (finalTime - block.timestamp)) / duration;

        tokenCount++;
        uint256 newTokenID = tokenCount;

        UserDeposit storage d = tokenToPosition[newTokenID];

        d.amount = amount;
        d.assetPrice = standardizedPrice;
        d.longOrShort = longShort;
        d.alpha = alpha;

        if (longShort == true) {
            alphaLongs += alpha;
            totalDepositsLONG += amount;
        } else if (longShort == false) {
            alphaShorts += alpha;
            totalDepositsSHORT += amount;
        }

        IERC20(suppliedAsset).safeTransferFrom(_msgSender(), address(this), memoryAmount);
        IERC20(suppliedAsset).safeApprove(stratContract, memoryAmount);
        IStrategy(stratContract).deposit(suppliedAsset, memoryAmount);
        _safeMint(_msgSender(), newTokenID);

        return (computedPriceRisk, alpha, standardizedPrice, standardizedAmount);
    }

    /// @notice Calculates the price risk based on deviation from actual price vs "strikePrice" and weighted through "deltaPrice".
    /// @param price        Actual price with 9 decimals returned from Chainlink price-feed.
    /// @param longOrShort  True = Long position, False = short position.
    /// @return rho         The computed price risk.
    function computePriceRisk(uint256 price, bool longOrShort) private view returns (uint256 rho) {
        if (longOrShort == true) {
            if (price > strikePrice) {
                return 10**9;
            } else if (price <= strikePrice) {
                rho = 10**9 + (((strikePrice - price) * 10**9) / deltaPrice);
                return rho;
            }
        }

        if (longOrShort == false) {
            if (strikePrice > price) {
                return 10**9;
            } else if (strikePrice <= price) {
                rho = 10**9 + (((price - strikePrice) * 10**9) / deltaPrice);
                return  rho;
            }
        }
    }

    /// @notice Called at "finalTime" to close the pool and determine the "endPrice".
    /// @dev    Only callable by the owner of the pool.
    function closePool() external onlyOwner {
        require(block.timestamp > finalTime, "Pool not yet ended");
        poolIsClosed = true;
        (,int price,,,) = AggregatorV3Interface(chainlinkPriceFeed).latestRoundData();
        require(price > 0);
        endPrice = standardizeBase9Chainlink(uint256(price));
        uint256 returnedAmount = IStrategy(stratContract).withdraw();
        returnedAmount <= totalDeposits ? totalReturnedFromStrat = returnedAmount : totalRewards = returnedAmount - totalDeposits;
        if (returnedAmount <= totalDeposits) {
            totalReturnedFromStrat = returnedAmount;
        } else if (returnedAmount > totalDeposits) {
            totalRewards = returnedAmount - totalDeposits;
        }

    }

    /// @notice Function to claim tokens and rewards (if any) after pool is closed.
    /// @param tokenID Token ID to claim for.
    /// @return _amountOwed Amount of underlying token to transfer to tokenholder.
    function getReward(uint256 tokenID) external returns (uint256 _amountOwed) {
        require(block.timestamp > finalTime && poolIsClosed == true, "Pool not yet ended");
        require(ownerOf(tokenID) == _msgSender(), "user is not Owner of token ID");

        uint256 amountOwed;
        uint256 alpha;
        uint256 fees;

        if (totalReturnedFromStrat > 0) {
            amountOwed = (tokenToPosition[tokenID].amount * totalReturnedFromStrat) / totalDeposits;
            _burn(tokenID);
            IERC20(suppliedAsset).safeTransfer(_msgSender(), amountOwed);
            return amountOwed;
        } else {
            if (endPrice >= strikePrice && tokenToPosition[tokenID].longOrShort == true) {
                alpha = tokenToPosition[tokenID].alpha;
                amountOwed =  totalRewards.mulDiv(alpha, alphaLongs, Math.Rounding.Down);
                fees = amountOwed.mulDiv(withdrawFees, 10**4, Math.Rounding.Up);
                amountOwed -= fees;
                feesCollected += fees;
            } else if (endPrice < strikePrice && tokenToPosition[tokenID].longOrShort == false) {
                alpha = tokenToPosition[tokenID].alpha;
                amountOwed =  totalRewards.mulDiv(alpha, alphaShorts, Math.Rounding.Down);
                fees = amountOwed.mulDiv(withdrawFees, 10**4, Math.Rounding.Up);
                amountOwed -= fees;
                feesCollected += fees;
             }

            amountOwed += tokenToPosition[tokenID].amount;
            _burn(tokenID);
            IERC20(suppliedAsset).safeTransfer(_msgSender(), amountOwed);

            return amountOwed;
        }
    }

    /// @notice Will transfer the fees collected to the owner.
    /// @dev Only callable by owner().
    function collectFees() external onlyOwner {
        require(feesCollected > 0, "not enough fees to withdraw");
        uint256 amountToSend = feesCollected;
        feesCollected = 0;
        IERC20(suppliedAsset).safeTransfer(_msgSender(), amountToSend);
    }

    /// @notice Will standardize the price returned from Chainlink to 9 decimals.
    /// @return standardizedAmount The price returned in 9 decimals.
    function standardizeBase9Chainlink(uint256 amount) private view returns (uint256 standardizedAmount) {
        standardizedAmount = amount;
        
        if (AggregatorV3Interface(chainlinkPriceFeed).decimals() < 9) {
            standardizedAmount *= 10 ** (9 - AggregatorV3Interface(chainlinkPriceFeed).decimals());
        } else if (AggregatorV3Interface(chainlinkPriceFeed).decimals() > 9) {
            standardizedAmount /= 10 ** (AggregatorV3Interface(chainlinkPriceFeed).decimals() - 9);
        }
    }

    /// @notice Will standardize the amount of a given asset to 9 decimals.
    /// @return standardizedAmount The amount returned in 9 decimals.
    function standardizeBase9(uint256 amount, address asset) private view returns (uint256 standardizedAmount) {
        standardizedAmount = amount;
        
        if (IERC20Metadata(asset).decimals() < 9) {
            standardizedAmount *= 10 ** (9 - IERC20Metadata(asset).decimals());
        } else if (IERC20Metadata(asset).decimals() > 9) {
            standardizedAmount /= 10 ** (IERC20Metadata(asset).decimals() - 9);
        }
    }

    /// @notice Returns the factor of multiplication for the APY with current pool composition.
    /// (APY multiplicatior on remaining period for longs if no change in TVL).
    /// @return standardizedMultiplicator Multiplication factor standardized to 9 decimals. 
    function apyBoosterLong() public view returns (uint256 standardizedMultiplicator) {

        if (totalDepositsLONG > 0) {
            uint256 APY_multiplicator = (totalDeposits * 10** IERC20Metadata(suppliedAsset).decimals()) / totalDepositsLONG;
            standardizedMultiplicator = standardizeBase9(APY_multiplicator, suppliedAsset);
            
        } else {
            standardizedMultiplicator = 0;
        }
    }

    /// @notice Returns the factor of multiplication for the APY with current pool composition.
    /// (APY multiplicatior on remaining period for shorts if no change in TVL).
    /// @return standardizedMultiplicator Multiplication factor standardized to 9 decimals. 
    function apyBoosterShort() public view returns (uint256 standardizedMultiplicator) {

        if (totalDepositsSHORT > 0) {
            uint256 APY_multiplicator = (totalDeposits * 10** IERC20Metadata(suppliedAsset).decimals()) / totalDepositsSHORT;
            standardizedMultiplicator = standardizeBase9(APY_multiplicator, suppliedAsset);
        } else {
            standardizedMultiplicator = 0;
        }
    }

    /// @notice Returns the factor of multiplication for the APY based on long/short position
    /// and actual price.
    /// @param _longOrShort True = long position, False = short position.
    /// @return apyMultiplicator Returned APY multiplicator based on position and actual price.
    function actualAPYBooster(bool _longOrShort) public view returns (uint256 apyMultiplicator) {
        (,int price,,,) = AggregatorV3Interface(chainlinkPriceFeed).latestRoundData();
        require(price > 0);
        uint256 actualPrice = standardizeBase9Chainlink(uint256(price));

        if (_longOrShort == true) {
            if (actualPrice >= strikePrice) {
                apyMultiplicator = apyBoosterLong();
            } else {
                apyMultiplicator = 0;
            } 
        }

        if (_longOrShort == false) {
            if (actualPrice < strikePrice) {
                apyMultiplicator = apyBoosterShort();
            } else {
                apyMultiplicator = 0;
            }
        }
    }
}
