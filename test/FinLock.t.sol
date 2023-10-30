// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/FinLock.sol";
import "./test_contracts/FinTestToken.sol";
import "./test_contracts/LpToken.sol";

contract FinLockTest is Test {
    FinLock public finLock;
    FinTestToken public erc20;
    UniswapV2ERC20 public lpToken;

    address public bob = address(1);

    function setUp() public {
        finLock = new FinLock(0.1 ether);
        erc20 = new FinTestToken(10000);
        erc20.approve(address(finLock), 10000);
        erc20.mint(bob, 100000);
        vm.prank(bob);
        erc20.approve(address(finLock), 10000);

        lpToken = new UniswapV2ERC20(10000);
        lpToken.setFactory(address(lpToken));
        lpToken.approve(address(finLock), 10000);
        vm.deal(bob, 1 ether);
    }

    function testNormalLock() public {
        uint256 id1 = finLock.lock{value: 0.1 ether}(
            address(this), 
            address(erc20), 
            false, 
            1, 
            1686082242
        );

        uint256 id2 = finLock.lock{value: 0.1 ether}(
            address(this), 
            address(erc20), 
            false, 
            2, 
            1686082242
        );

        assertEq(id1, 0);
        assertEq(id2, 1);
        assertEq(finLock.getTotalLockCount(), 2);
        assertEq(finLock.getLockAt(0).amount, 1);
        assertEq(finLock.getLockAt(1).token, address(erc20));
        // assertEq(finLock.getLockById(0).amount, 1);
        assertEq(finLock.allLpTokenLockedCount(), 0);
        assertEq(finLock.allNormalTokenLockedCount(), 1);
        // assertEq(finLock.getCumulativeLpTokenLockInfoAt(0).amount, 0);
        assertEq(finLock.getCumulativeNormalTokenLockInfoAt(0).amount, 3);
        // assertEq(finLock.getCumulativeLpTokenLockInfo(0, 2)[0].amount, 0);
        assertEq(finLock.getCumulativeNormalTokenLockInfo(0,2)[0].amount, 3);
        assertEq(finLock.totalTokenLockedCount(), 1);
        // assertEq(finLock.lpLockCountForUser(address(this)), 0);
        // assertEq(finLock.lpLocksForUser(address(this))[1].amount, 0);
        // assertEq(finLock.lpLockForUserAtIndex(address(this), 1).amount, 0);
        assertEq(finLock.normalLockCountForUser(address(this)), 2);
        assertEq(finLock.normalLocksForUser(address(this))[1].amount, 2);
        assertEq(finLock.normalLockForUserAtIndex(address(this), 1).amount, 2);
        assertEq(finLock.totalLockCountForUser(address(this)), 2);
        assertEq(finLock.totalLockCountForToken(address(erc20)), 2);
        assertEq(finLock.getLocksForToken(address(erc20), 0, 2)[1].amount, 2);
    }

    function testLpLock() public {
        uint256 id1 = finLock.lock{value: 0.1 ether}(
            address(this), 
            address(lpToken), 
            true, 
            1, 
            1686082242
        );

        uint256 id2 = finLock.lock{value: 0.1 ether}(
            address(this), 
            address(lpToken), 
            true, 
            2, 
            1685158898
        );

        assertEq(id1, 0);
        assertEq(id2, 1);
        assertEq(finLock.getTotalLockCount(), 2);
        assertEq(finLock.getLockAt(0).amount, 1);
        assertEq(finLock.getLockAt(1).token, address(lpToken));
        // assertEq(finLock.getLockById(0).amount, 1);
        assertEq(finLock.allLpTokenLockedCount(), 1);
        assertEq(finLock.allNormalTokenLockedCount(), 0);
        assertEq(finLock.getCumulativeLpTokenLockInfoAt(0).amount, 3);
        // assertEq(finLock.getCumulativeNormalTokenLockInfoAt(0).amount, 3);
        assertEq(finLock.getCumulativeLpTokenLockInfo(0, 2)[0].amount, 3);
        // assertEq(finLock.getCumulativeNormalTokenLockInfo(0,2)[0].amount, 3);
        assertEq(finLock.totalTokenLockedCount(), 1);
        assertEq(finLock.lpLockCountForUser(address(this)), 2);
        assertEq(finLock.lpLocksForUser(address(this))[1].amount, 2);
        assertEq(finLock.lpLockForUserAtIndex(address(this), 0).amount, 1);
        // assertEq(finLock.normalLockCountForUser(address(this)), 2);
        // assertEq(finLock.normalLocksForUser(address(this))[1].amount, 2);
        // assertEq(finLock.normalLockForUserAtIndex(address(this), 1).amount, 2);
        assertEq(finLock.totalLockCountForUser(address(this)), 2);
        assertEq(finLock.totalLockCountForToken(address(lpToken)), 2);
        assertEq(finLock.getLocksForToken(address(lpToken), 0, 2)[1].amount, 2);
    }

    function testSetFee() public {
        finLock.lock{value: 0.1 ether}(
            address(this), 
            address(erc20), 
            false, 
            1, 
            1686082242
        );

        finLock.setFee(0.2 ether);
        assertEq(finLock.fee(), 0.2 ether);
    }

    function testWithdrawFee() public {
        uint256 preNum = address(this).balance;
        // console.log(preNum);

        finLock.setFee(20 ether);
        assertEq(finLock.fee(), 20 ether);

        finLock.lock{value: 20 ether}(
            address(this), 
            address(erc20), 
            false, 
            1, 
            1686082242
        );
        assertEq(finLock.owner(), address(this));
        uint256 ethNum = address(this).balance;
        // console.log(ethNum);

        assertEq(ethNum, preNum - 20 ether);

        finLock.withdrawFee();
        assertEq(address(this).balance, preNum);
        // console.log(address(this).balance);


    }

    function testUnLock() public {
        
        uint256 id1 = finLock.lock{value: 0.1 ether}(
            address(this), 
            address(erc20), 
            false, 
            1, 
            2
        );
        uint256 preLock = erc20.balanceOf(address(this));
        vm.warp(3);
        finLock.unlock(id1);
        // console.log(erc20.balanceOf(address(this)));
        assertEq(erc20.balanceOf(address(this)), preLock + 1);
    }

    function testTransferLockOwnership() public {
        vm.prank(bob);
        uint256 id1 = finLock.lock{value: 0.1 ether}(
            bob, 
            address(erc20), 
            false, 
            1, 
            2
        );
        
        vm.prank(bob);
        finLock.renounceLockOwnership(id1);

        assertEq(finLock.getLockAt(id1).owner, address(this));
    }


    receive() external payable {
    }




}
