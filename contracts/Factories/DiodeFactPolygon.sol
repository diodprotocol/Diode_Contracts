// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../Diode.sol";
import "../Strategies/Polygon/CurveBeefy.sol";

    // ============================ Interfaces ========================

    interface IDiodePool {
        function setStrategy(address) external;
    }


    // ============================ Contract ==========================


/// @title Diode protocol Pool Factory Polygon Curve-Beefy
/// @author Diode Protocol core team 

contract DiodeFactPolygon is Ownable {


    // ============================ Events ==========================


    event NewDiodePool(       
        uint256 _strikePrice, 
        address _asset,
        uint256 _duration,
        uint256 _startTime,
        uint256 _deltaPrice,
        address _chainlinkPriceFeed,
        uint256 _fees,
        uint256[2] _capLongShort,
        string  _name,
        string  _symbol
    );

    event NewStrategy(
        address _underlyingToken,
        address _pool,
        address _curvePool,
        address _curveLPToken,
        address _beefyVault
    );


    // ============================ State Variables ==========================

    /// @notice List of all Diode Pools contract addresses
    address[] public diodePoolsList;

    /// @notice List of Euler Strategy addresses
    address[] public strategiesList;

    struct PoolInfo {
        uint256[3] strikeDeltaFees;
        uint256[2] durationAndStart;
        uint256[2] capLongShort;
        address asset;
        address chainlinkPriceFeed;
        string name;
        string symbol;
    }


    // ============================ Constructor ==========================

    constructor() {
    }

    // ============================ Functions ==========================

    /// @notice Deploys a Diode Pool and links a strategy to the pool.
    /// @param _strikeDeltaFees [0] = strikePrice (base 9), [1] = deltaPrice (base 9), [2] = fees (in BIPS).
    /// @param _durationAndStart [0] = duration of pool, [1] = start time (both in UNIX).
    /// @param _capLongShort [0] = max amount for longs in pool, [1] = max amount for shorts.
    /// @param _asset the asset to invest.
    /// @param _chainlinkPriceFeed the Chainlink oracle contract address for provided asset.
    /// @param _curveAddresses [0] = Curve Pool, [1] = Curve Pool LP Token.
    /// @param _beefyVault the contract address of the Beefy vault.
    /// @param _name name for the ERC721 token contract.
    /// @param _symbol symbol for ERC721 token.

    function deployDiodePool(
        uint256[3] memory _strikeDeltaFees, 
        uint256[2] memory _durationAndStart,
        uint256[2] memory _capLongShort,
        address _asset,
        address _chainlinkPriceFeed,
        address[2] memory _curveAddresses,
        address _beefyVault,
        string memory _name,
        string memory _symbol
    ) external onlyOwner returns (address deployedPool, address deployedStrategy) {

        /// @dev we're setting up a struct to avoid stack too deep error,
        ///      and run below code between brackets to have it run separately.
        PoolInfo memory pool;

        {
            pool.strikeDeltaFees = _strikeDeltaFees;
            pool.durationAndStart = _durationAndStart;
            pool.capLongShort = _capLongShort;
            pool.asset = _asset;
            pool.chainlinkPriceFeed = _chainlinkPriceFeed;
            pool.name = _name;
            pool.symbol = _symbol;
        }


        deployedPool = address(new Diode(
            pool.strikeDeltaFees[0],
            pool.asset,
            pool.durationAndStart[0],
            pool.durationAndStart[1],
            pool.strikeDeltaFees[1],
            pool.chainlinkPriceFeed,
            pool.strikeDeltaFees[2],
            pool.capLongShort,
            pool.name,
            pool.symbol
        ));

        diodePoolsList.push(deployedPool);

        emit NewDiodePool(
            pool.strikeDeltaFees[0],
            pool.asset,
            pool.durationAndStart[0],
            pool.durationAndStart[1],
            pool.strikeDeltaFees[1],
            pool.chainlinkPriceFeed,
            pool.strikeDeltaFees[2],
            pool.capLongShort,
            pool.name,
            pool.symbol
        );

        deployedStrategy = address(new CurveBeefy(
            _asset,
            deployedPool,
            _curveAddresses[0],
            _curveAddresses[1],
            _beefyVault
        ));

        strategiesList.push(deployedStrategy);

        emit NewStrategy(
            _asset, 
            deployedPool, 
            _curveAddresses[0], 
            _curveAddresses[1], 
            _beefyVault
        );

        IDiodePool(deployedPool).setStrategy(deployedStrategy);
    }

    // ============================ View Functions ==========================


    /// @notice Returns all the Diode Pools
    /// @dev Helper for UIs
    function getAllDiodePools() external view returns (address[] memory) {
        return diodePoolsList;
    }


    /// @notice Returns all the Diode Pools
    /// @dev Helper for UIs
    function getAllStrategies() external view returns (address[] memory) {
        return strategiesList;
    }

}