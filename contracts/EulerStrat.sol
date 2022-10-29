// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

// Uncomment this line to use console.log
import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/safeERC20.sol";


interface IEulerMarkets {
    function underlyingToEToken(address) external returns (address);
}

interface IEulerSimpleLens {
    function interestRates(address underlying) external returns (uint, uint, uint);
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
    address EULER_SIMPLELENS = 0x5077B7642abF198b4a5b7C4BdCE4f03016C7089C;
    IEulerMarkets markets = IEulerMarkets(EULER_MAINNET_MARKETS);
    // not enough time to calculate APY so hardcoded.
    uint256 Lido_stETH_APY = 5400000000;

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

    function getSupplyAPY() external onlyOwner returns (uint256 _apy) {
        (,,_apy) = (IEulerSimpleLens(EULER_SIMPLELENS).interestRates(underlyingToken));

        _apy /= 10**16;
       
        // if underlyingToken = Lido stETH add LIDO APY. Hardcoded, not enough time to calculate.
        if (underlyingToken == 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84) {
            _apy +=  Lido_stETH_APY;
        }


    }


}
