// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./ILock.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import "hardhat/console.sol";

contract FeeLockToken is ERC20Burnable, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IUniswapV2Router02 public uniswapV2Router;
    address public lockContract;
    address public  uniswapV2Pair;
    bool public keepBalance;

    address immutable deadWallet = 0x000000000000000000000000000000000000dEaD;

    address payable public feeWallet;
    address public lqWallet;
    uint256 public sellFeeRate;
    uint256 public buyFeeRate;
    uint256 public sellBurnFeeRate;
    uint256 public buyBurnFeeRate;
    uint256 public buyLqFeeRate;
    uint256 public sellLqFeeRate;
    address[] public swapPairsList;
    mapping (address => bool) public swapPairs;
    mapping (address => bool) public sellFeeWhiteList;
    mapping (address => bool) public buyFeeWhiteList;

    event SetFeeWallet(address oldWallet, address newWallet);
    event SetLqWallet(address oldWallet, address newWallet);
    event SetFeeRate(uint256 oldSellRate, uint256 oldBuyRate, uint256 newSellRate, uint256 newBuyRate);
    event SetBurnFeeRate(uint256 oldSellRate, uint256 oldBuyRate, uint256 newSellRate, uint256 newBuyRate);
    event SetLqFeeRate(uint256 oldSellRate, uint256 oldBuyRate, uint256 newSellRate, uint256 newBuyRate);
    event SetSwapPair(address addr, bool isPair);
    event SetFeeWhiteList(address account, bool isWhite, uint256 side);

    constructor(string memory name_, 
        string memory symbol_, 
        uint256 totalSupply_, 
        address payable feeWallet_, 
        address lqWallet_, 
        address routerAddr_
    ) ERC20(name_, symbol_)
    {
        require(feeWallet_ != address(0));
        require(lqWallet_ != address(0));
        require(routerAddr_ != address(0));
        if (totalSupply_ > 0) {
            _mint(_msgSender(), totalSupply_);
        }
        feeWallet = feeWallet_;
        lqWallet = lqWallet_;

        setFeeWhiteList(address(this), true, 1);
        setFeeWhiteList(address(this), true, 2);
        setFeeWhiteList(feeWallet, true, 1);
        setFeeWhiteList(feeWallet, true, 2);
        setFeeWhiteList(lqWallet, true, 1);
        setFeeWhiteList(lqWallet, true, 2);

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(routerAddr_);
         // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;
        swapPairs[_uniswapV2Pair] = true;
        swapPairsList.push(_uniswapV2Pair);

        emit SetSwapPair(_uniswapV2Pair, true);
    }

    receive() external payable {}

    function mint(address recipient, uint256 amount) external onlyOwner returns (bool)
    {
        _mint(recipient, amount);
        return true;
    }

    function multiMint(address[] memory recipients_, uint256[] memory amounts_) external onlyOwner returns (bool) {
        for (uint256 i = 0; i < recipients_.length; i++) {
            _mint(recipients_[i], amounts_[i]);
        }
        return true;
    }

    function transferToken(address token, address to, uint256 value) external onlyOwner returns (bool) {
        IERC20 tokenCon = IERC20(token);
        tokenCon.safeTransfer(to, value);
        return true;
    }

    function setLockContract(address con) external onlyOwner returns (bool) {
        require(lockContract == address(0), "Cannot set.");
        lockContract = con;
        return true;
    }

    function setKeepBalance(bool keepBalance_) external onlyOwner returns (bool) {
        require(keepBalance != keepBalance_, "Cannot set.");
        keepBalance = keepBalance_;
        return true;
    }

    function setLqWallet(address addr) external onlyOwner returns (bool) {
        require(addr != address(0));
        address oldWallet = lqWallet;
        lqWallet = addr;

        emit SetFeeWallet(oldWallet, addr);
        return true;
    }

    function setFeeWallet(address payable addr) external onlyOwner returns (bool) {
        require(addr != address(0));
        address oldWallet = feeWallet;
        feeWallet = addr;

        emit SetLqWallet(oldWallet, addr);
        return true;
    }

    function setFeeRate(uint256 sellFeeRate_, uint256 buyFeeRate_) external onlyOwner returns (bool) {
        require(sellFeeRate_ >= sellBurnFeeRate + sellLqFeeRate, "sellFeeRate too low");
        require(buyFeeRate_ >= buyBurnFeeRate + buyLqFeeRate, "buyFeeRate too low");
        uint256 oldSellRate = sellFeeRate;
        uint256 oldBuyRate = buyFeeRate;
        sellFeeRate = sellFeeRate_;
        buyFeeRate = buyFeeRate_;

        emit SetFeeRate(oldSellRate, oldBuyRate, sellFeeRate_, buyFeeRate_);
        return true;
    }

    function setBurnFeeRate(uint256 sellBurnFeeRate_, uint256 buyBurnFeeRate_) external onlyOwner returns (bool) {
        require(sellBurnFeeRate_ + sellLqFeeRate <= sellFeeRate, "sellBurnFeeRate overflow");
        require(buyBurnFeeRate_ + buyLqFeeRate <= buyFeeRate, "buyBurnFeeRate overflow");
        uint256 oldSellBurnRate = sellBurnFeeRate;
        uint256 oldBuyBurnRate = buyBurnFeeRate;
        sellBurnFeeRate = sellBurnFeeRate_;
        buyBurnFeeRate = buyBurnFeeRate_;

        emit SetBurnFeeRate(oldSellBurnRate, oldBuyBurnRate, sellBurnFeeRate_, buyBurnFeeRate_);
        return true;
    }

    function setLqFeeRate(uint256 sellLqFeeRate_, uint256 buyLqFeeRate_) external onlyOwner returns (bool) {
        require(sellLqFeeRate_ + sellBurnFeeRate <= sellFeeRate, "sellLqFeeRate overflow");
        require(buyLqFeeRate_ + buyBurnFeeRate <= buyFeeRate, "buyLqFeeRate overflow");
        uint256 oldSellLqRate = sellLqFeeRate;
        uint256 oldBuyLqRate = buyLqFeeRate;
        sellLqFeeRate = sellLqFeeRate_;
        buyLqFeeRate = buyLqFeeRate_;

        emit SetLqFeeRate(oldSellLqRate, oldBuyLqRate, sellLqFeeRate, buyLqFeeRate);
        return true;
    }

    function setSwapPair(address addr) external onlyOwner returns (bool) {
        require(addr != address(0));
        require(!swapPairs[addr], "Cannot set.");
        swapPairs[addr] = true;
        swapPairsList.push(addr);

        emit SetSwapPair(addr, true);
        return true;
    }

    function setFeeWhiteList(address account, bool isWhite, uint256 side) public onlyOwner returns (bool) {
        require(account != address(0));
        if (side == 1) {
            require(sellFeeWhiteList[account] != isWhite, "Cannot set.");
            sellFeeWhiteList[account] = isWhite;
        } else if (side == 2) {
            require(buyFeeWhiteList[account] != isWhite, "Cannot set.");
            buyFeeWhiteList[account] = isWhite;
        }
        
        emit SetFeeWhiteList(account, isWhite, side);
        return true;
    }

    function multiTransfer(address[] memory recipients_, uint256[] memory amounts_) external returns (bool) {
        require(recipients_.length==amounts_.length, "FeeLockToken: recipients_.length and amounts_.length are not same");
        for (uint256 i = 0; i < recipients_.length; i++) {
            _transfer(_msgSender(), recipients_[i], amounts_[i]);
        }
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        if (keepBalance && amount == balanceOf(sender)) {
            amount = amount.sub(1);
        }

        require(amount > 0, "Transfer amount must be positive.");

        if (sellFeeRate > 0 && swapPairs[recipient] && !sellFeeWhiteList[sender]) {
            //sell
            uint256 fee = amount.mul(sellFeeRate).div(1000);
            super._transfer(sender, address(this), fee);
            if (sellBurnFeeRate > 0) {
                uint256 burnAmount = amount.mul(sellBurnFeeRate).div(1000);
                super._transfer(address(this), deadWallet, burnAmount);
            }
            if (sellLqFeeRate > 0) {
                uint256 lqAmount = amount.mul(sellLqFeeRate).div(1000);
                super._transfer(address(this), lqWallet, lqAmount);
            }
            if (balanceOf(address(this)) > 0) {
                super._transfer(address(this), feeWallet, balanceOf(address(this)));
            }

            amount = amount - fee;
        } else if (buyFeeRate > 0 && swapPairs[sender] && !buyFeeWhiteList[recipient]) {
            //buy
            uint256 fee = amount.mul(buyFeeRate).div(1000);
            super._transfer(sender, address(this), fee);
            if (buyBurnFeeRate > 0) {
                uint256 burnAmount = amount.mul(buyBurnFeeRate).div(1000);
                super._transfer(address(this), deadWallet, burnAmount);
            }
            if (buyLqFeeRate > 0) {
                uint256 lqAmount = amount.mul(buyLqFeeRate).div(1000);
                super._transfer(address(this), lqWallet, lqAmount);
            }
            if (balanceOf(address(this)) > 0) {
                super._transfer(address(this), feeWallet, balanceOf(address(this)));
            }
            
            amount = amount - fee;
        }

        super._transfer(sender, recipient, amount);

        if (lockContract != address(0)) {
            ILock lock = ILock(lockContract);
            uint256 lockAmount = lock.getLockAmount(address(this), sender);
            require(balanceOf(sender) >= lockAmount, "Transfer amount exceeds available balance.");
        }
    }
}

