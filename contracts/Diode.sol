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

    uint256 public startTime;
    uint256 public finalTime;
    uint256 public duration;
    uint256 public endPrice;
    uint256 public totalRewards;
    uint256 public tokenCount;
    uint256 public totalDeposits;
    uint256 public totalDepositsLONG;
    uint256 public totalDepositsSHORT;
    uint256 public totalReturnedFromStrat;
    uint256 public feesCollected;
    /// @dev in BIPS
    uint256 public withdrawFees;
    uint256[2] public capLongShort;

    /// @dev Base 18 variables
    uint256 public alphaLongs;
    uint256 public alphaShorts;

    /// @dev Base 9 variables
    uint256 public strikePrice;
    uint256 public deltaPrice;

    address public stratContract;
    address public suppliedAsset;
    address public chainlinkPriceFeed;

    bool public poolIsClosed;   
    bool public strategyActivated;

    struct UserDeposit {
        uint256 amount;
        // 9 decimals for assetPrice
        uint256 assetPrice;
        bool longOrShort;
        // 18 decimals for alpha
        uint256 alpha;
    }

    mapping(uint256 => UserDeposit) public tokenToPosition;


    // -----------------
    //    Constructor
    // -----------------


    /// @notice Initializes the Iode pool.
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
        transferOwnership(tx.origin);
    }


    // -----------------
    //    Functions
    // -----------------


    function setStrategy(address _strat) external {
        require(strategyActivated == false);
        strategyActivated = true;
        stratContract = _strat;
    }

    function depositFunds(uint256 amount, bool longShort) public returns (
        uint256 _computedRisk, 
        uint256 _alpha, 
        uint256 _standardizedPrice, 
        uint256 _standardizedAmount
    ) 
    {
        require(block.timestamp >= startTime);
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

        //TODO: ask why issue when replacing with "amount" below (stack too deep error)
        IERC20(suppliedAsset).safeTransferFrom(_msgSender(), address(this), memoryAmount);
        IERC20(suppliedAsset).safeApprove(stratContract, memoryAmount);
        IStrategy(stratContract).deposit(suppliedAsset, memoryAmount);
        _safeMint(_msgSender(), newTokenID);

        return (computedPriceRisk, alpha, standardizedPrice, standardizedAmount);
    }


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

    function closePool() external onlyOwner {
        require(block.timestamp > finalTime);
        poolIsClosed = true;
        (,int price,,,) = AggregatorV3Interface(chainlinkPriceFeed).latestRoundData();
        require(price > 0);
        endPrice = standardizeBase9Chainlink(uint256(price));
        uint256 returnedAmount = IStrategy(stratContract).withdraw();
        if (returnedAmount <= totalDeposits) {
            totalReturnedFromStrat = returnedAmount;
        } else if (returnedAmount > totalDeposits) {
            totalRewards = returnedAmount - totalDeposits;
        }

    }

    function getReward(uint256 tokenID) external returns (uint256 _amountOwed) {
        require(block.timestamp > finalTime && poolIsClosed == true);
        require(ownerOf(tokenID) == _msgSender(), "user is not Owner of token ID");

        uint256 amountOwed;
        uint256 alpha;
        uint256 fees;

        if (totalReturnedFromStrat > 0) {
            amountOwed = (tokenToPosition[tokenID].amount * totalReturnedFromStrat) / totalDeposits;
            IERC20(suppliedAsset).safeTransfer(_msgSender(), amountOwed);
            return amountOwed;
        } else {
            if (endPrice >= strikePrice && tokenToPosition[tokenID].longOrShort == true) {
                alpha = tokenToPosition[tokenID].alpha;
                amountOwed =  totalRewards.mulDiv(alpha, alphaLongs, Math.Rounding.Down);
                fees = amountOwed.mulDiv(withdrawFees, 10**4, Math.Rounding.Up);
                amountOwed -= fees;
                feesCollected += fees;
            }
        
            if (endPrice < strikePrice && tokenToPosition[tokenID].longOrShort == false) {
                alpha = tokenToPosition[tokenID].alpha;
                amountOwed =  totalRewards.mulDiv(alpha, alphaShorts, Math.Rounding.Down);
                fees = amountOwed.mulDiv(withdrawFees, 10**4, Math.Rounding.Up);
                amountOwed -= fees;
                feesCollected += fees;
             }

            amountOwed += tokenToPosition[tokenID].amount;
            IERC20(suppliedAsset).safeTransfer(_msgSender(), amountOwed);

            return amountOwed;
        }
    }

    function collectFees() external onlyOwner {
        require(feesCollected > 0, "not enough fees to withdraw");
        uint256 amountToSend = feesCollected;
        feesCollected = 0;
        IERC20(suppliedAsset).safeTransfer(_msgSender(), amountToSend);
    }

    function standardizeBase9Chainlink(uint256 amount) private view returns (uint256 standardizedAmount) {
        standardizedAmount = amount;
        
        if (AggregatorV3Interface(chainlinkPriceFeed).decimals() < 9) {
            standardizedAmount *= 10 ** (9 - AggregatorV3Interface(chainlinkPriceFeed).decimals());
        } else if (AggregatorV3Interface(chainlinkPriceFeed).decimals() > 9) {
            standardizedAmount /= 10 ** (AggregatorV3Interface(chainlinkPriceFeed).decimals() - 9);
        }
    }

    function standardizeBase9(uint256 amount, address asset) private view returns (uint256 standardizedAmount) {
        standardizedAmount = amount;
        
        if (IERC20Metadata(asset).decimals() < 9) {
            standardizedAmount *= 10 ** (9 - IERC20Metadata(asset).decimals());
        } else if (IERC20Metadata(asset).decimals() > 9) {
            standardizedAmount /= 10 ** (IERC20Metadata(asset).decimals() - 9);
        }
    }

    function apyBoosterLong() public view returns (uint256 standardizedMultiplicator) {

        if (totalDepositsLONG > 0) {
            uint256 APY_multiplicator = (totalDeposits * 10** IERC20Metadata(suppliedAsset).decimals()) / totalDepositsLONG;
            standardizedMultiplicator = standardizeBase9(APY_multiplicator, suppliedAsset);
            
        } else {
            standardizedMultiplicator = 0;
        }
    }

    function apyBoosterShort() public view returns (uint256 standardizedMultiplicator) {

        if (totalDepositsSHORT > 0) {
            uint256 APY_multiplicator = (totalDeposits * 10** IERC20Metadata(suppliedAsset).decimals()) / totalDepositsSHORT;
            standardizedMultiplicator = standardizeBase9(APY_multiplicator, suppliedAsset);
        } else {
            standardizedMultiplicator = 0;
        }
    }

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
