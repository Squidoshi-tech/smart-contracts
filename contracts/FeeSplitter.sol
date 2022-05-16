// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import './utils/Ownable.sol';

import "@openzeppelin/contracts/math/SafeMath.sol";

contract FeeSplitter is Ownable {
    using SafeMath for uint256;

    address public charityWallet;
    address public marketingWallet;
    address public teamWallet;

    constructor(address _charityWallet, address _marketingWallet, address _teamWallet) public {
        charityWallet = _charityWallet;
        marketingWallet = _marketingWallet;
        teamWallet = _teamWallet;
    }

    function split(IERC20 token) external {
        uint256 total = token.balanceOf(address(this));

        uint256 charityShare = total.div(9);
        uint256 marketingShare = total.mul(2).div(3);
        uint256 teamShare = total.sub(charityShare).sub(marketingShare);

        token.transfer(charityWallet, charityShare);
        token.transfer(marketingWallet, marketingShare);
        token.transfer(teamWallet, teamShare);
    }

    function setCharityWallet(address newWallet) external onlyOwner {
        charityWallet = newWallet;
    }

    function setMarketingWallet(address newWallet) external onlyOwner {
        marketingWallet = newWallet;
    }

    function setTeamWallet(address newWallet) external onlyOwner {
        teamWallet = newWallet;
    }
}
