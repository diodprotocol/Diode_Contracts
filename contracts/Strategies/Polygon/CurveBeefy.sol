// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

// Uncomment this line to use console.log
import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


interface ICRVPlainPool {
    function add_liquidity(uint256[2] memory amounts_in, uint256 min_mint_amount) external returns (uint256);
    function calc_withdraw_one_coin(uint256 _token_amount, int128 i) external view returns (uint256);
    function coins(uint256 i) external view returns (address);
    function balances(uint256 i) external view returns (uint256);
    function remove_liquidity(uint256 amount, uint256[2] memory min_amounts_out) external returns (uint256[2] memory);
    function remove_liquidity_one_coin(uint256 token_amount, uint256 index, uint256 min_amount) external returns (uint256);
}

interface IBeefyVault {
    function deposit(uint256 _amount) external;
    function withdrawAll() external;
    function balanceOf(address) external view returns (uint256);
}



contract CurveBeefy is Ownable {
    
    using SafeERC20 for IERC20;

    // -----------------
    //  State Variables
    // -----------------

    
    address public underlyingToken;         /// @dev Token supplied in this strategy.
    address public curvePool;               /// @dev Address of the Curve Pool of this strategy.
    address public curveLPToken;            /// @dev Address of the LP Token of the Curve Pool.
    address public beefyVault;              /// @dev Address of Beefy vault where to deposit Curve LP tokens.
    uint256 public assetCurveIndex;         /// @dev The index of the underlying token in the Curve Pool.


    // -----------------
    //    Constructor
    // -----------------


    /// @notice Initializes Curve-Beefy strategy for a specific Diode Pool.
    constructor(
        address _underlyingToken, 
        address _diodePool,
        address _curvePool,
        address _curveLPToken,
        address _beefyVault
    ) 
    {
        require(ICRVPlainPool(_curvePool).coins(0) == _underlyingToken || ICRVPlainPool(_curvePool).coins(1) == _underlyingToken,
        "pool does not contain provided asset");
        underlyingToken = _underlyingToken;
        curvePool = _curvePool;
        beefyVault = _beefyVault;
        curveLPToken = _curveLPToken;

        if (ICRVPlainPool(_curvePool).coins(0) == _underlyingToken) {
            assetCurveIndex = 0;
        } else {
            assetCurveIndex = 1;
        }
        transferOwnership(_diodePool);
    }


    // -----------------
    //    Functions
    // -----------------


    /// @notice This function will deposit the supplied asset in a Curve Pool and then deposit the LP
    /// tokens received in the corresponding Beefy vault.
    /// @dev This function should only be called by owner() which is the Diode pool.
    /// @param token Address of the supplied token.
    /// @param amount The amount of tokens to deposit.
    function deposit (address token, uint256 amount) external onlyOwner {
        require(token == underlyingToken, "token supplied not supported by this strategy");
        IERC20(underlyingToken).safeTransferFrom(_msgSender(), address(this), amount);
        IERC20(underlyingToken).safeApprove(curvePool, amount);

        uint256[2] memory depositsCurve;
        if (assetCurveIndex == 0) {
            depositsCurve[0] = amount;
        } else {
            depositsCurve[1] = amount;
        }

        ICRVPlainPool(curvePool).add_liquidity(depositsCurve, 0);
        IERC20(curveLPToken).safeApprove(beefyVault, IERC20(curveLPToken).balanceOf(address(this)));
        IBeefyVault(beefyVault).deposit(IERC20(curveLPToken).balanceOf(address(this)));
    }


    /// @notice This function will remove liquidity in this order Beefy -> Curve.
    /// And transfer the underlying assets to the underlying Diode Pool.
    /// @dev Should only be called by owner(), which is the Diode Pool.
    /// @return returnedAmount The amount of underlying tokens received when removing liquidity.
    function withdraw() external onlyOwner returns (uint256 returnedAmount) {
        IBeefyVault(beefyVault).withdrawAll();
        ICRVPlainPool(curvePool).remove_liquidity_one_coin(IERC20(curveLPToken).balanceOf(address(this)), assetCurveIndex, 0);
        returnedAmount = IERC20(underlyingToken).balanceOf(address(this));
        IERC20(underlyingToken).safeTransfer(owner(), IERC20(underlyingToken).balanceOf(address(this)));
    }

    /// @notice This function will return the total amount of Curve LP tokens staked on Beefy.
    /// @return stratLpBalance The amount of Curve LP tokens deposited by this this strategy in Beefy Vault.
    function stratBalance() public view returns (uint256 stratLpBalance) {
        stratLpBalance = IBeefyVault(beefyVault).balanceOf(address(this));
    }

}