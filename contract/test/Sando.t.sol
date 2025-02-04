// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "foundry-huff/HuffDeployer.sol";
import "v3-core/interfaces/IUniswapV3Pool.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/tokens/WETH.sol";

import "./misc/GeneralHelper.sol";
import "./misc/V2SandoUtility.sol";
import "./misc/V3SandoUtility.sol";
import "./misc/SandoCommon.sol";

// Need custom interface cause USDT does not return a bool after swap
// see more here: https://github.com/d-xo/weird-erc20#missing-return-values
interface IUSDT {
    function transfer(address to, uint256 value) external;
}

/// @title SandoTest
/// @author 0xmouseless
/// @notice Test suite for the huff sando contract
contract SandoTest is Test {
    // wallet associated with private key 0x1
    address constant searcher = 0x22505ae1c8A0fd9fa7968d49fde27eE6475Be007;
    WETH weth = WETH(payable(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2));
    uint256 wethFundAmount = 100 ether;
    address sando;

    function setUp() public {
        // change this if ur node isn't hosted on localhost:8545
        vm.createSelectFork("http://172.31.3.140:8888", 17401879);
        sando = HuffDeployer.deploy("sando");

        // fund sando
        weth.deposit{value: wethFundAmount}();
        weth.transfer(sando, wethFundAmount);

        payable(searcher).transfer(100 ether);
    }

    function testRecoverEth() public {
        vm.startPrank(searcher);

        uint256 sandoBalanceBefore = address(sando).balance;
        uint256 eoaBalanceBefore = address(searcher).balance;

        (bool s,) = sando.call(abi.encodePacked(SandoCommon.getJumpDestFromSig("recoverEth")));
        assertTrue(s, "calling recoverEth failed");

        assertTrue(address(sando).balance == 0, "sando ETH balance should be zero after calling recover eth");
        assertTrue(
            address(searcher).balance == eoaBalanceBefore + sandoBalanceBefore,
            "searcher should gain all eth from sando"
        );
    }

    function testSepukku() public {
        vm.startPrank(searcher);
        (bool s,) = sando.call(abi.encodePacked(SandoCommon.getJumpDestFromSig("seppuku")));
        assertTrue(s, "calling seppuku failed");
    }

    function testRecoverWeth() public {
        vm.startPrank(searcher);

        uint256 sandoBalanceBefore = weth.balanceOf(sando);
        uint256 searcherBalanceBefore = weth.balanceOf(searcher);

        (bool s,) = sando.call(abi.encodePacked(SandoCommon.getJumpDestFromSig("recoverWeth"), sandoBalanceBefore));
        assertTrue(s, "failed to call recoverWeth");

        assertTrue(weth.balanceOf(sando) == 0, "sando WETH balance should be zero after calling recoverWeth");
        assertTrue(
            weth.balanceOf(searcher) == searcherBalanceBefore + sandoBalanceBefore,
            "searcher should gain all weth from sando after calling recoverWeth"
        );
    }

    function testUnauthorizedAccessToCallback(address trespasser, bytes32 fakePoolKeyHash) public {
        vm.startPrank(trespasser);
        vm.deal(address(trespasser), 5 ether);
        /*
           function uniswapV3SwapCallback(
             int256 amount0Delta,
             int256 amount1Delta,
             bytes data
           ) external

           custom data = abi.encodePacked(isZeroForOne, input_token, pool_key_hash)
        */
        bytes memory payload =
            abi.encodePacked(uint8(250), uint256(5 ether), uint256(5 ether), uint8(1), address(weth), fakePoolKeyHash); // 0xfa = 250
        (bool s,) = sando.call(payload);
        assertFalse(s, "only pools should be able to call callback");
    }

    function testV3FrontrunWeth1(uint256 inputWethAmount) public {
        IUniswapV3Pool pool = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640); // USDC - WETH
        (, address outputToken) = (pool.token1(), pool.token0());

        // make sure fuzzed value is within bounds
        inputWethAmount = bound(inputWethAmount, WethEncodingUtils.encodeMultiple(), weth.balanceOf(sando));

        (bytes memory payload, uint256 encodedValue) =
            V3SandoUtility.v3CreateFrontrunPayload(pool, outputToken, int256(inputWethAmount));

        vm.prank(searcher, searcher);
        (bool s,) = address(sando).call{value: encodedValue}(payload);

        assertTrue(s, "calling swap failed");
    }

    function testV3FrontrunWeth0(uint256 inputWethAmount) public {
        IUniswapV3Pool pool = IUniswapV3Pool(0x7379e81228514a1D2a6Cf7559203998E20598346); // ETH - STETH
        (address outputToken,) = (pool.token1(), pool.token0());

        // make sure fuzzed value is within bounds
        inputWethAmount = bound(inputWethAmount, WethEncodingUtils.encodeMultiple(), weth.balanceOf(sando));

        (bytes memory payload, uint256 encodedValue) =
            V3SandoUtility.v3CreateFrontrunPayload(pool, outputToken, int256(inputWethAmount));

        vm.prank(searcher, searcher);
        (bool s,) = address(sando).call{value: encodedValue}(payload);

        assertTrue(s, "calling swap failed");
    }

    function testV3BackrunWeth0(uint256 inputBttAmount) public {
        IUniswapV3Pool pool = IUniswapV3Pool(0x64A078926AD9F9E88016c199017aea196e3899E1);
        (address inputToken,) = (pool.token1(), pool.token0());

        // make sure fuzzed value is within bounds
        address sugarDaddy = 0x9277a463A508F45115FdEaf22FfeDA1B16352433;
        inputBttAmount = bound(inputBttAmount, 1, ERC20(inputToken).balanceOf(sugarDaddy));

        // fund sando contract
        vm.startPrank(sugarDaddy);
        IUSDT(inputToken).transfer(sando, uint256(inputBttAmount));

        bytes memory payload = V3SandoUtility.v3CreateBackrunPayload(pool, inputToken, int256(inputBttAmount));

        changePrank(searcher, searcher);
        (bool s,) = address(sando).call(payload);
        assertTrue(s, "calling swap failed");
    }

    function testV3BackrunWeth1(uint256 inputDaiAmount) public {
        IUniswapV3Pool pool = IUniswapV3Pool(0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8);
        (address inputToken,) = (pool.token0(), pool.token1());

        // make sure fuzzed value is within bounds
        address sugarDaddy = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
        inputDaiAmount = bound(inputDaiAmount, 1, ERC20(inputToken).balanceOf(sugarDaddy));

        // fund sando contract
        vm.startPrank(sugarDaddy);
        ERC20(inputToken).transfer(sando, uint256(inputDaiAmount));

        bytes memory payload = V3SandoUtility.v3CreateBackrunPayload(pool, inputToken, int256(inputDaiAmount));

        changePrank(searcher, searcher);
        (bool s,) = address(sando).call(payload);
        assertTrue(s, "calling swap failed");
    }

    // +-------------------------------+
    // |        Generic Tests          |
    // +-------------------------------+
    // could decompose further but ran into issues with vm.assume/vm.bound when fuzzing
    function testV2FrontrunWeth0(uint256 inputWethAmount) public {
        address usdtAddress = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

        // make sure fuzzed value is within bounds
        inputWethAmount = bound(inputWethAmount, WethEncodingUtils.encodeMultiple(), weth.balanceOf(sando));

        // capture pre swap state
        uint256 preSwapWethBalance = weth.balanceOf(sando);
        uint256 preSwapUsdtBalance = ERC20(usdtAddress).balanceOf(sando);

        // calculate expected values
        uint256 actualWethInput = WethEncodingUtils.decode(WethEncodingUtils.encode(inputWethAmount));
        uint256 actualUsdtOutput = GeneralHelper.getAmountOut(address(weth), usdtAddress, actualWethInput);
        uint256 expectedUsdtOutput = FiveBytesEncodingUtils.decode(FiveBytesEncodingUtils.encode(actualUsdtOutput));

        // need this to pass because: https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L160
        vm.assume(expectedUsdtOutput > 0);

        (bytes memory calldataPayload, uint256 wethEncodedValue) =
            V2SandoUtility.v2CreateFrontrunPayload(usdtAddress, inputWethAmount);
        vm.prank(searcher);
        (bool s,) = address(sando).call{value: wethEncodedValue}(calldataPayload);
        assertTrue(s);

        // check values after swap
        assertEq(
            ERC20(usdtAddress).balanceOf(sando) - preSwapUsdtBalance,
            expectedUsdtOutput,
            "did not get expected usdt amount out from swap"
        );
        assertEq(preSwapWethBalance - weth.balanceOf(sando), actualWethInput, "unexpected amount of weth used in swap");
    }

    function testV2FrontrunWeth1(uint256 inputWethAmount) public {
        address usdcAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

        // make sure fuzzed value is within bounds
        inputWethAmount = bound(inputWethAmount, WethEncodingUtils.encodeMultiple(), weth.balanceOf(sando));

        // capture pre swap state
        uint256 preSwapWethBalance = weth.balanceOf(sando);
        uint256 preSwapUsdcBalance = ERC20(usdcAddress).balanceOf(sando);

        // calculate expected values
        uint256 actualWethInput = WethEncodingUtils.decode(WethEncodingUtils.encode(inputWethAmount));
        uint256 actualUsdcOutput = GeneralHelper.getAmountOut(address(weth), usdcAddress, actualWethInput);
        uint256 expectedUsdcOutput = FiveBytesEncodingUtils.decode(FiveBytesEncodingUtils.encode(actualUsdcOutput));

        // need this to pass because: https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L160
        vm.assume(expectedUsdcOutput > 0);

        (bytes memory calldataPayload, uint256 wethEncodedValue) =
            V2SandoUtility.v2CreateFrontrunPayload(usdcAddress, inputWethAmount);
        vm.prank(searcher);
        (bool s,) = address(sando).call{value: wethEncodedValue}(calldataPayload);
        assertTrue(s);

        // check values after swap
        assertEq(
            ERC20(usdcAddress).balanceOf(sando) - preSwapUsdcBalance,
            expectedUsdcOutput,
            "did not get expected usdc amount out from swap"
        );
        assertEq(preSwapWethBalance - weth.balanceOf(sando), actualWethInput, "unexpected amount of weth used in swap");
    }

    function testV2BackrunWeth0(uint256 inputSuperAmount) public {
        address superAddress = 0xe53EC727dbDEB9E2d5456c3be40cFF031AB40A55; // superfarm token
        address sugarDaddy = 0xF977814e90dA44bFA03b6295A0616a897441aceC;

        // make sure fuzzed value is within bounds
        inputSuperAmount = bound(inputSuperAmount, 1, ERC20(superAddress).balanceOf(sugarDaddy));

        // fund sando
        vm.prank(sugarDaddy);
        IUSDT(superAddress).transfer(sando, inputSuperAmount);

        // capture pre swap state
        uint256 preSwapWethBalance = weth.balanceOf(sando);
        uint256 preSwapSuperBalance = ERC20(superAddress).balanceOf(sando);

        // calculate expected values
        uint256 actualFarmInput = FiveBytesEncodingUtils.decode(FiveBytesEncodingUtils.encode(preSwapSuperBalance));
        uint256 actualWethOutput = GeneralHelper.getAmountOut(superAddress, address(weth), actualFarmInput);
        uint256 expectedWethOutput = WethEncodingUtils.decode(WethEncodingUtils.encode(actualWethOutput));

        // need this to pass because: https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L160
        vm.assume(expectedWethOutput > 0);

        // perform swap
        (bytes memory calldataPayload, uint256 wethEncodedValue) =
            V2SandoUtility.v2CreateBackrunPayload(superAddress, inputSuperAmount);
        vm.prank(searcher);
        (bool s,) = address(sando).call{value: wethEncodedValue}(calldataPayload);
        assertTrue(s, "swap failed");

        // check values after swap
        assertEq(
            weth.balanceOf(sando) - preSwapWethBalance,
            expectedWethOutput,
            "did not get expected weth amount out from swap"
        );
        assertEq(
            preSwapSuperBalance - ERC20(superAddress).balanceOf(sando),
            actualFarmInput,
            "unexpected amount of superFarm used in swap"
        );
    }

    function testV2BackrunWeth1(uint256 inputDaiAmount) public {
        address daiAddress = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // DAI
        address sugarDaddy = 0x47ac0Fb4F2D84898e4D9E7b4DaB3C24507a6D503;

        // make sure fuzzed value is within bounds
        inputDaiAmount = bound(inputDaiAmount, 1, ERC20(daiAddress).balanceOf(sugarDaddy));

        // fund sando
        vm.prank(sugarDaddy);
        ERC20(daiAddress).transfer(sando, inputDaiAmount);

        // capture pre swap state
        uint256 preSwapWethBalance = weth.balanceOf(sando);
        uint256 preSwapDaiBalance = ERC20(daiAddress).balanceOf(sando);

        // calculate expected values
        uint256 actualDaiInput = FiveBytesEncodingUtils.decode(FiveBytesEncodingUtils.encode(preSwapDaiBalance));
        uint256 actualWethOutput = GeneralHelper.getAmountOut(daiAddress, address(weth), actualDaiInput);
        uint256 expectedWethOutput = WethEncodingUtils.decode(WethEncodingUtils.encode(actualWethOutput));

        // need this to pass because: https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Pair.sol#L160
        vm.assume(expectedWethOutput > 0);

        // perform swap
        (bytes memory calldataPayload, uint256 wethEncodedValue) =
            V2SandoUtility.v2CreateBackrunPayload(daiAddress, inputDaiAmount);
        vm.prank(searcher);
        (bool s,) = address(sando).call{value: wethEncodedValue}(calldataPayload);
        assertTrue(s, "swap failed");

        // check values after swap
        assertEq(
            weth.balanceOf(sando) - preSwapWethBalance,
            expectedWethOutput,
            "did not get expected weth amount out from swap"
        );
        assertEq(
            preSwapDaiBalance - ERC20(daiAddress).balanceOf(sando),
            actualDaiInput,
            "unexpected amount of dai used in swap"
        );
    }
}
