// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

// Uncomment this line to use console.log
import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";


interface IEulerMarkets {
    function underlyingToEToken(address) external returns (address);
}

interface IEulerSimpleLens {
    function interestRates(address underlying) external view returns (uint, uint, uint);
}

interface IEulerEToken {
    function deposit(uint, uint) external;
    function withdraw(uint, uint) external;
    function balanceOf(address) external returns (uint);
}

contract EulerStrat is Ownable {
    
    using SafeERC20 for IERC20;

    // -----------------
    //  State Variables
    // -----------------

    address EULER_MAINNET = 0x27182842E098f60e3D576794A5bFFb0777E025d3;
    address EULER_MAINNET_MARKETS = 0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3;
    address EULER_SIMPLELENS_MAINNET = 0x5077B7642abF198b4a5b7C4BdCE4f03016C7089C;
    
    //address EULER_GOERLI = 0x931172BB95549d0f29e10ae2D079ABA3C63318B3;
    //address EULER_GOERLI_MARKETS = 0x3EbC39b84B1F856fAFE9803A9e1Eae7Da016Da36;   
    IEulerMarkets markets = IEulerMarkets(EULER_MAINNET_MARKETS);
    
    address public underlyingToken;


    // -----------------
    //    Constructor
    // -----------------


    /// @notice Initializes the Euler strategy.
    constructor(address _underlyingToken, address _pool) {

        underlyingToken = _underlyingToken;
        transferOwnership(_pool);
    }


    // -----------------
    //    Functions
    // -----------------


    function deposit (address token, uint256 amount) external onlyOwner {
        require(token == underlyingToken, "token supplied not supported by this contract");
        IERC20(underlyingToken).safeTransferFrom(_msgSender(), address(this), amount);
        IERC20(underlyingToken).safeApprove(EULER_MAINNET, amount);
        markets = IEulerMarkets(EULER_MAINNET_MARKETS);
        IEulerEToken eToken = IEulerEToken(markets.underlyingToEToken(underlyingToken));
        eToken.deposit(0, amount);
    }

    //TODO: check if there are extra rewards distributed.
    function withdraw() external onlyOwner returns (uint256 returnedAmount) {
        IEulerEToken eToken = IEulerEToken(markets.underlyingToEToken(underlyingToken));
        eToken.withdraw(0, stratBalance());
        returnedAmount = IERC20(underlyingToken).balanceOf(address(this));
        IERC20(underlyingToken).safeTransfer(owner(), IERC20(underlyingToken).balanceOf(address(this)));
    }

    function stratBalance() public returns (uint256 totalInvested) {
        IEulerEToken eToken = IEulerEToken(markets.underlyingToEToken(underlyingToken));
        totalInvested = eToken.balanceOf(address(this));
    }


    function getSupplyAPY() external view onlyOwner returns (uint256 _apy) {

        // Not active on Goerli
        (,,_apy) = (IEulerSimpleLens(EULER_SIMPLELENS_MAINNET).interestRates(underlyingToken));

        _apy /= 10**11;

/*         uint256 Lido_stETH_APY = 5400000000;
        uint256 WBTC_APY = 2888888888;
        uint256 USDT_APY = 3410000000;
        uint256 WETH_APY = 1900000000;

        address Lido_stETH_Goerli = 0x1643E812aE58766192Cf7D2Cf9567dF2C37e9B7F;
        address WBTC_Goerli = 0xC04B0d3107736C32e19F1c62b2aF67BE61d63a05;
        address USDT_Goerli = 0xe583769738b6dd4E7CAF8451050d1948BE717679;
        address WETH_Goerli = 0xa3401DFdBd584E918f59fD1C3a558467E373DacC; */

       
/*         // if underlyingToken = Lido stETH add LIDO APY. Hardcoded, not enough time to calculate.
        if (underlyingToken == Lido_stETH_Goerli) {
            _apy +=  Lido_stETH_APY;
        }

        // if underlyingToken = WBTC add LIDO APY. Hardcoded, not enough time to calculate.
        if (underlyingToken == WBTC_Goerli) {
            _apy +=  WBTC_APY;
        }

        // if underlyingToken = USDT add LIDO APY. Hardcoded, not enough time to calculate.
        if (underlyingToken == USDT_Goerli) {
            _apy +=  USDT_APY;
        }

        // if underlyingToken = WETH add LIDO APY. Hardcoded, not enough time to calculate.
        if (underlyingToken == WETH_Goerli) {
            _apy += WETH_APY;
        } */
    }
}
