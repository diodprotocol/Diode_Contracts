// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "../Diode.sol";


    // ============================ Contract ==========================


/// @title Diode protocol Pool Factory
/// @author Diode Protocol core team 

contract DiodeFactory {


    // ============================ Events ==========================


    event NewDiodePool(       
        uint256 _strikePrice, 
        address _asset,
        uint256 _duration,
        uint256 _startTime,
        uint256 _deltaPrice,
        address _chainlinkPriceFeed,
        uint256 _fees,
        string  _name,
        string  _symbol
    );


    // ============================ State Variables ==========================

    /// @notice List of all Diode Pools contract addresses
    address[] public diodePoolsList;

    // ============================ Constructor ==========================

    constructor() {
    }

    // ============================ Functions ==========================

    /// @notice Deploys a Diode Pool for `asset` with withdrawal fees of `fees` and a vesting period of
    /// `vestingPeriod`
    function deployDiodePool(
        uint256 _strikePrice, 
        address _asset,
        uint256 _duration,
        uint256 _startTime,
        uint256 _deltaPrice,
        address _chainlinkPriceFeed,
        uint256 _fees,
        string memory _name,
        string memory _symbol
    ) 
    external 
    returns (address deployedPool)
    {
  
        deployedPool = address(new Diode(
            _strikePrice,
            _asset,
            _duration,
            _startTime,
            _deltaPrice,
            _chainlinkPriceFeed,
            _fees,
            _name,
            _symbol
            ));

        diodePoolsList.push(deployedPool);
        emit NewDiodePool(_strikePrice, _asset, _duration, _startTime, _deltaPrice, _chainlinkPriceFeed, _fees, _name, _symbol);
    }



    // ============================ View Functions ==========================


    /// @notice Returns all the Diode Pools
    /// @dev Helper for UIs
    function getAllDiodePools() external view returns (address[] memory) {
        return diodePoolsList;
    }



}