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
    function remove_liquidity_one_coin(uint256 token_amount, int128 index, uint min_amount) external;
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

    
    address public underlyingToken;
    address public curvePool;
    address public beefyVault;
    address public curveLP;
    int128 public assetCurveIndex;


    // -----------------
    //    Constructor
    // -----------------


    /// @notice Initializes Curve-Beefy strategy.
    constructor(
        address _underlyingToken, 
        address _diodePool,
        address _curvePool,
        address _curveLP,
        address _beefyVault
    ) 
    {
        require(ICRVPlainPool(_curvePool).coins(0) == _underlyingToken || ICRVPlainPool(_curvePool).coins(1) == _underlyingToken,
        "pool does not contain provided asset");
        underlyingToken = _underlyingToken;
        curvePool = _curvePool;
        beefyVault = _beefyVault;
        curveLP = _curveLP;

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
        IERC20(curveLP).safeApprove(beefyVault, IERC20(curveLP).balanceOf(address(this)));
        IBeefyVault(beefyVault).deposit(IERC20(curveLP).balanceOf(address(this)));
    }

    function withdraw() external onlyOwner returns (uint256 returnedAmount) {
        IBeefyVault(beefyVault).withdrawAll();
        ICRVPlainPool(curvePool).remove_liquidity_one_coin(IERC20(curveLP).balanceOf(address(this)), assetCurveIndex, 0);
        returnedAmount = IERC20(underlyingToken).balanceOf(address(this));
        IERC20(underlyingToken).safeTransfer(owner(), IERC20(underlyingToken).balanceOf(address(this)));
    }

    function stratBalance() public view returns (uint256 totalInvested) {
        totalInvested = IBeefyVault(beefyVault).balanceOf(address(this));
    }

    function getSupplyAPY() external view onlyOwner returns (uint256 _apy) {
        _apy = 0;
    }
}