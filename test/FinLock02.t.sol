// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/FinLockV2.sol";
import "./test_contracts/FinTestToken.sol";
import "./test_contracts/LpToken.sol";

contract FinLockV2Test is Test {
    FinLock02 public finLock;
    FinTestToken public erc20;
    UniswapV2ERC20 public lpToken;

    function setUp() public {
        finLock = new FinLock02();
        erc20 = new FinTestToken(10000);
        erc20.approve(address(finLock), 10000);

        lpToken = new UniswapV2ERC20(10000);
        lpToken.setFactory(address(lpToken));
        lpToken.approve(address(finLock), 10000);
    }

    function testNormalLock() public {
        uint256 id1 = finLock.lock(
            address(this), 
            address(erc20), 
            false, 
            1, 
            1686082242, 
            "test1"
        );

        uint256 id2 = finLock.lock(
            address(this), 
            address(erc20), 
            false, 
            2, 
            1686082242, 
            "test2"
        );
        assertEq(id1, 0);
        assertEq(id2, 1);
        assertEq(finLock.getTotalLockCount(), 2);
        assertEq(finLock.getLockAt(0).id, 0);
        assertEq(finLock.getLockAt(0).token, address(erc20));
        assertEq(finLock.getLockById(0).amount, 1);
        assertEq(finLock.allLpTokenLockedCount(), 0);
        assertEq(finLock.allNormalTokenLockedCount(), 1);
        assertEq(finLock.getCumulativeNormalTokenLockInfoAt(0).token, address(erc20));
        assertEq(finLock.getCumulativeNormalTokenLockInfo(0, 2)[0].amount, 3);
        assertEq(finLock.totalTokenLockedCount(), 1);
        assertEq(finLock.normalLockCountForUser(address(this)), 2);
        assertEq(finLock.normalLocksForUser(address(this))[1].amount, 2);
        assertEq(finLock.normalLockForUserAtIndex(address(this),1).amount, 2);
        assertEq(finLock.totalLockCountForUser(address(this)), 2);
        assertEq(finLock.totalLockCountForToken(address(erc20)), 2);
        assertEq(finLock.getLocksForToken(address(erc20), 0, 2)[1].amount, 2);
    }

    function testLpLock() public {
        uint256 id1 = finLock.lock(
            address(this), 
            address(lpToken), 
            true, 
            1, 
            1686082242, 
            "test1"
        );

        uint256 id2 = finLock.lock(
            address(this), 
            address(lpToken), 
            true, 
            2, 
            1686082242, 
            "test2"
        );

        assertEq(lpToken.factory(), address(lpToken));
        assertEq(id1, 0);
        assertEq(id2, 1);
        assertEq(finLock.getTotalLockCount(), 2);
        assertEq(finLock.getLockAt(0).id, 0);
        assertEq(finLock.getLockAt(0).token, address(lpToken));
        assertEq(finLock.getLockById(0).amount, 1);
        assertEq(finLock.allLpTokenLockedCount(), 1);
        assertEq(finLock.allNormalTokenLockedCount(), 0);
        assertEq(finLock.getCumulativeLpTokenLockInfoAt(0).amount, 3);
        assertEq(finLock.getCumulativeLpTokenLockInfo(0, 2)[0].amount, 3);
        assertEq(finLock.totalTokenLockedCount(), 1);
        assertEq(finLock.lpLockCountForUser(address(this)), 2);
        assertEq(finLock.lpLocksForUser(address(this))[1].amount, 2);
        assertEq(finLock.lpLockForUserAtIndex(address(this), 1).amount, 2);
        assertEq(finLock.totalLockCountForUser(address(this)), 2);
        assertEq(finLock.totalLockCountForToken(address(lpToken)), 2);
        assertEq(finLock.getLocksForToken(address(lpToken), 0, 2)[1].amount, 2);
    }

// token : 0xe7f1725e7734ce288f8367e1bb143e90bb3f0512
// lock : 0x5fbdb2315678afecb367f032d93f642f64180aa3
// owner:0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266


}
