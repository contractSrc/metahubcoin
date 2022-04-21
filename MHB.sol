// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "./ILock.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import '@openzeppelin/contracts/utils/math/SafeMath.sol';

contract MetahubCoin is ERC20Burnable, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct lockMsg {
        bool exists;
        uint256 startTime;
        uint256 endTime;
        uint256 cycle;
        uint256 times;
    }
    uint256 public startLockTime;
    mapping(address => lockMsg) public lockRecord;
    mapping(address => uint256) public speedLockAmount;

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
    mapping(address => bool) public isFrozen;

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

        setFeeWhiteList(address(this), true, 12);
        setFeeWhiteList(feeWallet, true, 12);
        setFeeWhiteList(lqWallet, true, 12);

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(routerAddr_);
         // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;
        swapPairs[_uniswapV2Pair] = true;
        swapPairsList.push(_uniswapV2Pair);

        lockMsg memory lockData;
        lockData.exists = true;
        lockData.startTime = 1660060800;
        lockData.endTime = 1660060800+8640000;
        lockData.cycle = 86400;
        lockData.times = 100;
        lockRecord[address(0)] = lockData;

        emit SetSwapPair(_uniswapV2Pair, true);
    }

    function setDefaultLockRule(
        uint256 releaseStartTime,
        uint256 releaseCycle,
        uint256 releaseTimes
    ) external onlyOwner returns (bool) {
        lockMsg memory lockData;
        lockData.exists = true;
        lockData.startTime = releaseStartTime;
        lockData.endTime = releaseStartTime.add(releaseCycle.mul(releaseTimes));
        lockData.cycle = releaseCycle;
        lockData.times = releaseTimes;
        lockRecord[address(0)] = lockData;
        return true;
    }

    function setStartLockTime(uint256 newTime) external onlyOwner returns (bool) {
        startLockTime = newTime;
        return true;
    }

    function setAccountLockRule(
        address account,
        uint256 releaseStartTime,
        uint256 releaseCycle,
        uint256 releaseTimes
    ) external onlyOwner returns (bool) {
        speedLockAmount[account] = getSpeedLockAmount(account);
        lockMsg memory lockData;
        lockData.exists = true;
        lockData.startTime = releaseStartTime;
        lockData.endTime = releaseStartTime.add(releaseCycle.mul(releaseTimes));
        lockData.cycle = releaseCycle;
        lockData.times = releaseTimes;
        lockRecord[account] = lockData;
        return true;
    }

    function freeze(address account) external onlyOwner returns (bool) {
        require(account != address(0), "account cannot be zero");
        require(!isFrozen[account], "already be frozen");
        isFrozen[account] = true;
        return true;
    }

    function unfreeze(address account) external onlyOwner returns (bool) {
        require(isFrozen[account], "account is not frozen");
        isFrozen[account] = false;
        return true;
    }

    // function transferToken(address token, address to, uint256 value) external onlyOwner returns (bool) {
    //     IERC20 tokenCon = IERC20(token);
    //     tokenCon.safeTransfer(to, value);
    //     return true;
    // }

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
        } else if (side == 12) {
            require(sellFeeWhiteList[account] != isWhite, "Cannot set sell.");
            require(buyFeeWhiteList[account] != isWhite, "Cannot set buy.");
            sellFeeWhiteList[account] = isWhite;
            buyFeeWhiteList[account] = isWhite;
        } else {
            require(false, "Wrong side.");
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

    function getSpeedLockAmount(address account) public view returns (uint256) {
        if (block.timestamp < startLockTime) {
            return 0;
        }
        if (speedLockAmount[account] == 0) {
            return 0;
        }
        bool exists = lockRecord[account].exists;
        if (!exists) {
            uint256 amount = speedLockAmount[account];
            uint256 startTime = lockRecord[address(0)].startTime;
            if (startTime >= block.timestamp) {
                return amount;
            }
            uint256 endTime = lockRecord[address(0)].endTime;
            if (endTime <= block.timestamp) {
                return 0;
            }
            uint256 cycle = lockRecord[address(0)].cycle;
            uint256 releasedTimes = block.timestamp.sub(startTime).div(cycle);
            uint256 releaseTimes = lockRecord[address(0)].times;
            return amount.sub(releasedTimes.mul(amount).div(releaseTimes));
        } else {
            uint256 amount = speedLockAmount[account];
            uint256 startTime = lockRecord[account].startTime;
            if (startTime >= block.timestamp) {
                return amount;
            }
            uint256 endTime = lockRecord[account].endTime;
            if (endTime <= block.timestamp) {
                return 0;
            }
            uint256 cycle = lockRecord[account].cycle;
            uint256 releasedTimes = block.timestamp.sub(startTime).div(cycle);
            uint256 releaseTimes = lockRecord[account].times;
            return amount.sub(releasedTimes.mul(amount).div(releaseTimes));
        }
    }

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        require(!isFrozen[sender], "from is frozen");
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

        uint256 lockAmount = 0;
        if (lockContract != address(0)) {
            ILock lock = ILock(lockContract);
            lockAmount = lock.getLockAmount(address(this), sender);
            require(balanceOf(sender) >= lockAmount, "Transfer amount exceeds available balance.");
        }

        if (block.timestamp < startLockTime) {
            speedLockAmount[sender] = balanceOf(sender).sub(lockAmount);
            speedLockAmount[recipient] = balanceOf(recipient).sub(lockAmount);
        } else {
            lockAmount = lockAmount.add(getSpeedLockAmount(sender));
        }
        require(balanceOf(sender) >= lockAmount, "Transfer amount exceeds available balance.");
    }
}