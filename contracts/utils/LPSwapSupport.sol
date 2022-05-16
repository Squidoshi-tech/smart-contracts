// SPDX-License-Identifier: MIT
pragma solidity >=0.6.0;

/**
There are far too many uses for the LP swapping pool.
Rather than rewrite them, this contract performs them for us and uses both generic and specific calls.
-The Dev
*/

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
//import '@pancakeswap-libs/pancake-swap-core/contracts/interfaces/IPancakePair.sol';
//import '@pancakeswap-libs/pancake-swap-core/contracts/interfaces/IPancakeFactory.sol';
import "./pancakeswap-peripheral/contracts/interfaces/IPancakeRouter02.sol";
import "./AuthorizedList.sol";

contract TempRewardReceiver is Ownable {
    function transfer(
        address token,
        address recipient,
        uint256 amount
    ) external onlyOwner {
        IERC20(token).transfer(recipient, amount);
    }
}

interface IPancakePair {
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;
}

interface IPancakeFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint256);

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;
}

abstract contract LPSwapSupport is AuthorizedList {
    using SafeMath for uint256;
    event UpdateRouter(address indexed newAddress, address indexed oldAddress);
    event UpdatePair(address indexed newAddress, address indexed oldAddress);
    event UpdateLPReceiver(address indexed newAddress, address indexed oldAddress);
    event SwapAndLiquifyEnabledUpdated(bool enabled);

    event SwapAndLiquify(uint256 tokensSwapped, uint256 currencyReceived, uint256 tokensIntoLiqudity);

    modifier lockTheSwap() {
        inSwap = true;
        _;
        inSwap = false;
    }

    bool internal inSwap;
    bool public swapsEnabled = true;

    uint256 public minSpendAmount = 1 ether;
    uint256 public maxSpendAmount = 1000 ether;

    IPancakeRouter02 public pancakeRouter;
    IERC20 public BUSD;
    address public pancakePair;
    address public liquidityReceiver = deadAddress;
    address public deadAddress = 0x000000000000000000000000000000000000dEaD;
    TempRewardReceiver public tempRewardReceiver;

    constructor() public {
        tempRewardReceiver = new TempRewardReceiver();
    }

    function _approve(
        address owner,
        address spender,
        uint256 tokenAmount
    ) internal virtual;

    function addBUSDAddress(address newAddress) public authorized {
        require(newAddress != address(0));
        BUSD = IERC20(newAddress);
    }

    function updateRouter(address newAddress) public authorized {
        require(newAddress != address(pancakeRouter));
        emit UpdateRouter(newAddress, address(pancakeRouter));
        pancakeRouter = IPancakeRouter02(newAddress);
    }

    function updateLiquidityReceiver(address receiverAddress) external onlyOwner {
        require(receiverAddress != liquidityReceiver);
        emit UpdateLPReceiver(receiverAddress, liquidityReceiver);
        liquidityReceiver = receiverAddress;
    }

    // function updateRouterAndPair(address newAddress) public virtual authorized {
    //     if (newAddress != address(pancakeRouter)) {
    //         updateRouter(newAddress);
    //     }
    //     address _pancakeswapV2Pair = IPancakeFactory(pancakeRouter.factory()).createPair(
    //         address(this),
    //         pancakeRouter.WETH()
    //     );
    //     if (_pancakeswapV2Pair != pancakePair) {
    //         updateLPPair(_pancakeswapV2Pair);
    //     }
    // }

    function updateLPPair(address newAddress) public virtual authorized {
        require(newAddress != pancakePair);
        emit UpdatePair(newAddress, pancakePair);
        pancakePair = newAddress;
    }

    function setSwapAndLiquifyEnabled(bool _enabled) public authorized {
        swapsEnabled = _enabled;
        emit SwapAndLiquifyEnabledUpdated(_enabled);
    }

    function swapAndLiquify(uint256 tokens) internal {
        // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = BUSD.balanceOf(address(this));

        // swap tokens for
        swapTokensForCurrency(half);

        // how much did we just swap into?
        uint256 newBalance = BUSD.balanceOf(address(this)).sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);
        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function swapTokensForCurrency(uint256 tokenAmount) internal {
        swapTokensForCurrencyAdv(address(this), tokenAmount, address(this));
    }

    function swapTokensForCurrencyAdv(
        address tokenAddress,
        uint256 tokenAmount,
        address destination
    ) internal {
        if (tokenAddress != address(this)) {
            IERC20(tokenAddress).approve(address(pancakeRouter), tokenAmount);
        } else {
            _approve(address(this), address(pancakeRouter), tokenAmount);
        }

        swapTokens(tokenAddress, address(BUSD), tokenAmount, destination);
    }

    function swapTokens(
        address token0,
        address token1,
        uint256 tokenAmount,
        address destination
    ) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = token0;
        path[1] = token1;
        bool shouldUseTempWallet = token0 == destination || token1 == destination;
        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            shouldUseTempWallet ? address(tempRewardReceiver) : destination,
            block.timestamp
        );

        // transfer tokens back to the this address
        if (shouldUseTempWallet)
            tempRewardReceiver.transfer(token1, destination, IERC20(token1).balanceOf(address(tempRewardReceiver)));
    }

    function addLiquidity(uint256 _tokenAmount, uint256 _BUSDAmount) public authorized {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(pancakeRouter), _tokenAmount);
        // approve token transfer to cover all possible scenarios
        BUSD.approve(address(pancakeRouter), _BUSDAmount);

        pancakeRouter.addLiquidity(
            address(this),
            address(BUSD),
            _tokenAmount,
            _BUSDAmount,
            0,
            0,
            address(this),
            block.timestamp
        );
    }

    function swapCurrencyForTokens(uint256 amount) internal {
        swapCurrencyForTokensAdv(address(this), amount, address(this));
    }

    function swapCurrencyForTokensAdv(
        address tokenAddress,
        uint256 tokenAmount,
        address destination
    ) internal {
        if (tokenAmount > BUSD.balanceOf(address(this))) {
            tokenAmount = BUSD.balanceOf(address(this));
        }
        if (tokenAmount > maxSpendAmount) {
            tokenAmount = maxSpendAmount;
        }
        if (tokenAmount < minSpendAmount) {
            return;
        }

        // approve token transfer to cover all possible scenarios
        BUSD.approve(address(pancakeRouter), tokenAmount);

        swapTokens(address(BUSD), tokenAddress, tokenAmount, destination);
    }

    function updateSwapRange(uint256 minAmount, uint256 maxAmount) external authorized {
        require(minAmount <= maxAmount);
        minSpendAmount = minAmount;
        maxSpendAmount = maxAmount;
    }
}
