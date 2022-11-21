// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

//standard test libs
import "../../../lib/forge-std/src/Test.sol";
import "../../../lib/forge-std/src/Vm.sol";

//librairies
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

//Contract under test
import {Diode} from "../../../contracts/Diode.sol";
import {CurveBeefy} from "../../../contracts/Strategies/Polygon/CurveBeefy.sol";

interface IEulerMarkets {
    function underlyingToEToken(address) external returns (address);
}

interface IEulerStrat {
    function deposit(address token, uint256 amount) external;
    function getSupplyAPY() external returns (uint256);
}

interface IEulerEToken {
    function deposit(uint, uint) external;
    function withdraw(uint, uint) external;
    function balanceOf(address) external returns (uint);
}

contract Diode_test_Polygon is Test {

    using SafeERC20 for IERC20;

    //Variable for contract instance
    Diode private diode;
    CurveBeefy private curveBeefy;

    // init users
    address random = 0xe7804c37c13166fF0b37F5aE0BB07A3aEbb6e245; // 4600 WMATIC 
    address user1 = 0xC070A61D043189D99bbf4baA58226bf0991c7b11; //  WMATIC
    address user2 = 0x5845D86e4420ddff360b5d1c1dBC9Bcd293F9121; //  WMATIC
    address user3 = 0xF977814e90dA44bFA03b6295A0616a897441aceC; //  WMATIC

    // init tokens
    address WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
    address stMATIC = 0x3A58a54C066FdC0f2D55FC9C89F0415C92eBf3C4;

    // Beefy addresses
    address beefyVault = 0xE0570ddFca69E5E90d83Ea04bb33824D3BbE6a85;

    //Curve addresses
    address curvePool = 0xFb6FE7802bA9290ef8b00CA16Af4Bc26eb663a28;
    address curveLPToken = 0xe7CEA2F6d7b120174BF3A9Bc98efaF1fF72C997d;

    constructor() { 
        
    }

    // Verify equality within difference
    function withinDiff(uint256 val0, uint256 val1, uint256 expectedDiff) public {
        uint256 actualDiff = val0 > val1 ? val0 - val1 : val1 - val0;
        bool check = actualDiff <= expectedDiff;

        if (!check) {
            emit log_named_uint("Error: approx a == b not satisfied, accuracy difference ", expectedDiff);
            emit log_named_uint("  Expected", val0);
            emit log_named_uint("    Actual", val1);
            fail();
        }
    }

    function setUp() public {

        uint256[2] memory cap;
        cap[0] = 10_000 * 10**18;
        cap[1] = 10_000 * 10**18;
        uint256 strikePrice = 10**9;
        uint256 duration = 2629743; // 30.44 days UNIX time
        uint256 deltaPrice = 2 * 10**8;
        address chainlinkPriceFeed = 0xAB594600376Ec9fD91F8e885dADF0CE036862dE0; // MATIC/USD price feed

        //Instantiate new contract instance
        diode = new Diode(
            strikePrice,
            WMATIC,
            duration,
            block.timestamp,
            deltaPrice,
            chainlinkPriceFeed,
            1000,
            cap,
            "Diode_stETH",
            "DIO1"
        );

        //Instantiate new contract instance
        curveBeefy = new CurveBeefy(
            WMATIC,
            address(diode),
            curvePool,
            curveLPToken,
            beefyVault
        );

        diode.setStrategy(address(curveBeefy));
    }

    function test_DiodePoly_init() public {
        assertEq(diode.suppliedAsset(),                    0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270);
        assertEq(diode.strikePrice(),                      10**9);
        assertEq(diode.duration(),                         2629743);
        assertEq(diode.chainlinkPriceFeed(),               0xAB594600376Ec9fD91F8e885dADF0CE036862dE0);
        assertEq((diode.finalTime() - diode.startTime()),  diode.duration());
        assertEq(diode.deltaPrice(),                       2 * 10**8);

        withinDiff(diode.startTime(),                      block.timestamp, 100);

        emit log_named_address("Diode contract address:",  address(diode));

    }

    function test_CurveBeefyPoly_init() public {
        assertEq(curveBeefy.underlyingToken(),             WMATIC);
        assertEq(curveBeefy.owner(),                       address(diode));
        emit log_named_address("Strategy contract address:",  address(curveBeefy));
    }


    function test_DiodePoly_DepositFunds() public {

        // +1 hour
        vm.warp(block.timestamp + 1 hours);

        // random user deposit
        vm.startPrank(random);

        IERC20(WMATIC).safeApprove(address(diode), 1000 ether);

        IERC20(WMATIC).safeTransfer(user1, 500 ether);

        (uint256 random_computedPriceRisk,
         uint256 random_alpha,
         uint256 random_standardizedPrice, 
         uint256 random_standardizedAmount) = diode.depositFunds(1000 ether, false);

        vm.stopPrank();

        // + 15 days

        vm.warp(block.timestamp + 15 days);

        // user1 deposit
        vm.startPrank(user1);

        IERC20(WMATIC).safeApprove(address(diode), 500 ether);
        
        (uint256 user1_computedPriceRisk,
         uint256 user1_alpha,
         uint256 user1_standardizedPrice, 
         uint256 user1_standardizedAmount) = diode.depositFunds(500 ether, true);

        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);

        emit log_string("FTX results:");

        emit log_named_uint("computedPriceRisk", random_computedPriceRisk);
        emit log_named_uint("alpha:", random_alpha);
        emit log_named_uint("standardizedPrice:", random_standardizedPrice);
        emit log_named_uint("standardizedAmount:", random_standardizedAmount);

        emit log_string("user1 results:");

        emit log_named_uint("computedPriceRisk", user1_computedPriceRisk);
        emit log_named_uint("alpha:", user1_alpha);
        emit log_named_uint("standardizedPrice:", user1_standardizedPrice);
        emit log_named_uint("standardizedAmount:", user1_standardizedAmount);

        emit log_named_address("Owner of token 1:", diode.ownerOf(1));
        emit log_named_address("Owner of token 2:", diode.ownerOf(2));

        emit log_named_uint("Beefy Strat Balance before:", curveBeefy.stratBalance());

        emit log_named_uint("expected APY longs:", diode.apyBoosterLong());
        emit log_named_uint("expected APY shorts:", diode.apyBoosterShort());

        assert(curveBeefy.stratBalance() > 0);

        vm.startPrank(address(diode));
        emit log_named_uint("get APY Booster Strategy:", curveBeefy.getSupplyAPY());
        uint256 returnedAmount = curveBeefy.withdraw();
        //uint256 returned = curveBeefy.unstakeFromCurve();
        vm.stopPrank();
        emit log_named_uint("returnedAmount:", returnedAmount);
        emit log_named_uint("WMATIC contract balance:", IERC20(WMATIC).balanceOf(address(curveBeefy)));

        emit log_named_uint("curve LP token strat balance:", IERC20(curveLPToken).balanceOf(address(curveBeefy)));
        emit log_named_uint("Beefy Strat Balance after:", curveBeefy.stratBalance());
        assert(curveBeefy.stratBalance() == 0);
    }


    function test_DiodePoly_DepositAndWithdrawFunds() public {

        // +1 hour
        vm.warp(block.timestamp + 1 hours);

        // Random deposit
        vm.startPrank(random);

        IERC20(WMATIC).safeApprove(address(diode), 1000 ether);

        // Send 500 WMATIC to user1,2,3
        IERC20(WMATIC).safeTransfer(user1, 500 ether);
        IERC20(WMATIC).safeTransfer(user2, 500 ether);
        IERC20(WMATIC).safeTransfer(user3, 500 ether);

        diode.depositFunds(1000 ether, true);

        vm.stopPrank();

        //////////////////////////////////////////////////////// + 15 days
        vm.warp(block.timestamp + 15 days);
        //////////////////////////////////////////////////////// 

        // user1 deposit
        vm.startPrank(user1);

        IERC20(WMATIC).safeApprove(address(diode), 500 ether);

        diode.depositFunds(500 ether, false);

        vm.stopPrank();

        //////////////////////////////////////////////////////// + 7 days
        vm.warp(block.timestamp + 7 days);
        //////////////////////////////////////////////////////// 

        // user2 deposit
        vm.startPrank(user2);

        IERC20(WMATIC).safeApprove(address(diode), 500 ether);

        diode.depositFunds(500 ether, true);

        vm.stopPrank();  

        //////////////////////////////////////////////////////// + 2 days
        vm.warp(block.timestamp + 2 days);
        //////////////////////////////////////////////////////// 

        // user3 deposit
        vm.startPrank(user3);

        IERC20(WMATIC).safeApprove(address(diode), 500 ether);
        
        diode.depositFunds(500 ether, false);

        vm.stopPrank(); 

        //////////////////////////////////////////////////////// + 8 days
        vm.warp(block.timestamp + 8 days);
        //////////////////////////////////////////////////////// 

        vm.startPrank(random);
        IERC20(WMATIC).safeTransfer(address(curveBeefy), 500 ether);
        vm.stopPrank();

        vm.prank(diode.owner());
        diode.closePool();

        //////////////////////////////////////////////////////// 
        //   GET REWARDS
        //////////////////////////////////////////////////////// 

        // FTX
        emit log_string("FTX initial data");
        emit log_named_uint("total Rewards:", diode.totalRewards());
        emit log_named_uint("total assets:", diode.totalDeposits());
        emit log_named_uint("endPrice:", diode.endPrice());

        vm.startPrank(random);
        uint256 random_amount = diode.getReward(1);
        vm.stopPrank();

        // user 1
        vm.startPrank(user1);
        uint256 user1_amount = diode.getReward(2);
        vm.stopPrank();

        // user 2
        vm.startPrank(user2);
        uint256 user2_amount = diode.getReward(3);
        vm.stopPrank();  

        // user 3
        vm.startPrank(user3);
        uint256 user3_amount = diode.getReward(4);
        vm.stopPrank();

        emit log_named_uint("random amount:", random_amount);
        emit log_named_uint("user1 amount:", user1_amount);
        emit log_named_uint("user 2 amount:", user2_amount);
        emit log_named_uint("user 3 amount:", user3_amount);
        emit log_named_uint("remaining contract balance:", IERC20(diode.suppliedAsset()).balanceOf(address(diode)));

        emit log_named_uint("total longs:", diode.alphaLongs());
        emit log_named_uint("total shorts:", diode.alphaShorts());
    }


}