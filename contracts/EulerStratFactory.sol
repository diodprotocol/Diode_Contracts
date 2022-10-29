// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import "./EulerStrat.sol";


    // ============================ Contract ==========================


/// @title Diode Protocol Strategy Factory
/// @author Diode Protocol core team 

contract EulerStratFactory {


    // ============================ Events ==========================


    event NewEulerStrategy(address _underlyingToken, address _pool);


    // ============================ State Variables ==========================

    /// @notice List of all Diode Pools contract addresses
    address[] public eulerStrategyList;

    // ============================ Constructor ==========================


    constructor() {
    }


    // ============================ Functions ==========================

    /// @notice Deploys a Diode Pool for `asset` with withdrawal fees of `fees` and a vesting period of
    /// `vestingPeriod`
    function deployEulerStrategy(address _underlyingToken, address _pool) external returns (address deployedStrategy) {

        deployedStrategy = address(new EulerStrat(_underlyingToken, _pool));

        eulerStrategyList.push(deployedStrategy);
        emit NewEulerStrategy(_underlyingToken, _pool);
    }

    // ============================ View Functions ==========================


    /// @notice Returns all the Diode Pools
    /// @dev Helper for UIs
    function getAllEulerStrategies() external view returns (address[] memory) {
        return eulerStrategyList;
    }

}