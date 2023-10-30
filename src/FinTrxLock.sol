// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IPoolManager.sol";
import "./interfaces/IPinkLock.sol";

contract FinLock is IPinkLock, Ownable {
    using Address for address payable;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;

    struct Lock {
        uint256 id;
        address token;
        address owner;
        uint256 amount;
        uint256 lockDate;
        uint256 unlockDate;
    }

    struct CumulativeLockInfo {
        address token;
        address factory;
        uint256 amount;
    }

    uint256 public fee;

    Lock[] private _locks;
    mapping(address => EnumerableSet.UintSet) private _userLpLockIds;
    mapping(address => EnumerableSet.UintSet) private _userNormalLockIds;

    EnumerableSet.AddressSet private _lpLockedTokens;
    EnumerableSet.AddressSet private _normalLockedTokens;
    mapping(address => CumulativeLockInfo) public cumulativeLockInfo;
    mapping(address => EnumerableSet.UintSet) private _tokenToLockIds;

    address public usdtAddr = 0xa614f803B6FD780986A42c78Ec9c7f77e6DeD13C;

    event LockAdded(
        uint256 indexed id,
        address token,
        address owner,
        uint256 amount,
        uint256 unlockDate
    );
    event LockUpdated(
        uint256 indexed id,
        address token,
        address owner,
        uint256 newAmount,
        uint256 newUnlockDate
    );
    event LockRemoved(
        uint256 indexed id,
        address token,
        address owner,
        uint256 amount,
        uint256 unlockedAt
    );

    event LockOwnerChanged(
        uint256 lockId, 
        address owner, 
        address newOwner
    );

    modifier feePaid() {
        require(msg.value == fee, "Fee");
        _;
    }

    modifier validLock(uint256 lockId) {
        require(lockId < _locks.length, "Invalid lock id");
        _;
    }

    constructor(uint256 _fee) {
        fee = _fee;
    }

    function setFee(uint256 newFee) external onlyOwner {
        fee = newFee;
    }

    function withdrawFee() external onlyOwner {
        payable(owner()).sendValue(address(this).balance);
    }

    function lock(
        address owner,
        address token,
        bool isLpToken,
        uint256 amount,
        uint256 unlockDate
    ) external payable override feePaid returns (uint256 id) {
        require(
            unlockDate > block.timestamp,
            "Unlock date should be after current time"
        );
        require(amount > 0, "Amount should be greater than 0");
        if (isLpToken) {
            address possibleFactoryAddress;
            try IUniswapV2Pair(token).factory() returns (address factory) {
                possibleFactoryAddress = factory;
            } catch {
                revert("This token is not a LP token");
            }
            require(
                possibleFactoryAddress != address(0) &&
                    _isValidLpToken(token, possibleFactoryAddress),
                "This token is not a LP token."
            );
            id = _lockLpToken(
                owner,
                token,
                possibleFactoryAddress,
                amount,
                unlockDate
            );
        } else {
            id = _lockNormalToken(owner, token, amount, unlockDate);
        }
        _safeTransferFromEnsureExactAmount(
            token,
            msg.sender,
            address(this),
            amount
        );

        emit LockAdded(id, token, owner, amount, unlockDate);
        return id;
    }

    function _lockLpToken(
        address owner,
        address token,
        address factory,
        uint256 amount,
        uint256 unlockDate
    ) private returns (uint256 id) {
        id = _addLock(owner, token, amount, unlockDate);
        _userLpLockIds[owner].add(id);
        _lpLockedTokens.add(token);

        CumulativeLockInfo storage tokenInfo = cumulativeLockInfo[token];
        if (tokenInfo.token == address(0)) {
            tokenInfo.token = token;
            tokenInfo.factory = factory;
        }
        tokenInfo.amount = tokenInfo.amount + amount;

        _tokenToLockIds[token].add(id);
    }

    function _lockNormalToken(
        address owner,
        address token,
        uint256 amount,
        uint256 unlockDate
    ) private returns (uint256 id) {
        id = _addLock(owner, token, amount, unlockDate);
        _userNormalLockIds[owner].add(id);
        _normalLockedTokens.add(token);

        CumulativeLockInfo storage tokenInfo = cumulativeLockInfo[token];
        if (tokenInfo.token == address(0)) {
            tokenInfo.token = token;
            tokenInfo.factory = address(0);
        }
        tokenInfo.amount = tokenInfo.amount + amount;

        _tokenToLockIds[token].add(id);
    }

    function _addLock(
        address owner,
        address token,
        uint256 amount,
        uint256 unlockDate
    ) private returns (uint256 id) {
        id = _locks.length;
        Lock memory newLock = Lock({
            id: id,
            token: token,
            owner: owner,
            amount: amount,
            lockDate: block.timestamp,
            unlockDate: unlockDate
        });
        _locks.push(newLock);
    }

    function unlock(uint256 lockId) external override validLock(lockId) {
        Lock storage userLock = _locks[lockId];
        require(
            userLock.owner == msg.sender,
            "You are not the owner of this lock"
        );
        require(
            block.timestamp >= userLock.unlockDate,
            "It is not time to unlock"
        );
        require(userLock.amount > 0, "Nothing to unlock");

        CumulativeLockInfo storage tokenInfo = cumulativeLockInfo[
            userLock.token
        ];
        bool isLpToken = tokenInfo.factory != address(0);

        if (isLpToken) {
            _userLpLockIds[msg.sender].remove(lockId);
        } else {
            _userNormalLockIds[msg.sender].remove(lockId);
        }

        uint256 unlockAmount = userLock.amount;

        if (tokenInfo.amount <= unlockAmount) {
            tokenInfo.amount = 0;
        } else {
            tokenInfo.amount = tokenInfo.amount - unlockAmount;
        }

        if (tokenInfo.amount == 0) {
            if (isLpToken) {
                _lpLockedTokens.remove(userLock.token);
            } else {
                _normalLockedTokens.remove(userLock.token);
            }
        }
        userLock.amount = 0;

        _tokenToLockIds[userLock.token].remove(userLock.id);

        _safeTransfer(userLock.token, msg.sender, unlockAmount);

        emit LockRemoved(
            userLock.id,
            userLock.token,
            msg.sender,
            unlockAmount,
            block.timestamp
        );
    }

    function editLock(
        uint256 lockId,
        uint256 newAmount,
        uint256 newUnlockDate
    ) external payable override feePaid validLock(lockId) {
        Lock storage userLock = _locks[lockId];
        require(
            userLock.owner == msg.sender,
            "You are not the owner of this lock"
        );
        require(userLock.amount > 0, "Lock was unlocked");
        if (newUnlockDate > 0) {
            require(
                newUnlockDate >= userLock.unlockDate &&
                    newUnlockDate > block.timestamp,
                "New unlock time should not be before old unlock time or current time"
            );
            userLock.unlockDate = newUnlockDate;
        }

        if (newAmount > 0) {
            require(
                newAmount >= userLock.amount,
                "New amount should not be less than current amount"
            );

            uint256 diff = newAmount - userLock.amount;

            if (diff > 0) {
                _safeTransferFromEnsureExactAmount(
                    userLock.token,
                    msg.sender,
                    address(this),
                    diff
                );

                userLock.amount = newAmount;

                CumulativeLockInfo storage tokenInfo = cumulativeLockInfo[
                    userLock.token
                ];
                tokenInfo.amount = tokenInfo.amount + diff;
            }
        }

        emit LockUpdated(
            userLock.id,
            userLock.token,
            userLock.owner,
            userLock.amount,
            userLock.unlockDate
        );
    }

    function _transferLockOwnership(uint256 lockId, address newOwner)
        internal
        validLock(lockId)
    {
        Lock storage userLock = _locks[lockId];
        address currentOwner = userLock.owner;
        require(
            currentOwner == msg.sender,
            "You are not the owner of this lock"
        );

        require(
            userLock.amount != 0,
            "The lock has no value"
        );

        userLock.owner = newOwner;

        CumulativeLockInfo storage tokenInfo = cumulativeLockInfo[
            userLock.token
        ];

        bool isLpToken = tokenInfo.factory != address(0);

        if (isLpToken) {
            _userLpLockIds[currentOwner].remove(lockId);
            _userLpLockIds[newOwner].add(lockId);
        } else {
            _userNormalLockIds[currentOwner].remove(lockId);
            _userNormalLockIds[newOwner].add(lockId);
        }

        emit LockOwnerChanged(lockId, currentOwner, newOwner);
    }

    function renounceLockOwnership(uint256 lockId) external {
        _transferLockOwnership(lockId, owner());
    }

    function _safeTransferFromEnsureExactAmount(
        address token,
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        uint256 oldRecipientBalance = IERC20(token).balanceOf(recipient);
        IERC20(token).safeTransferFrom(sender, recipient, amount);
        uint256 newRecipientBalance = IERC20(token).balanceOf(recipient);
        require(
            newRecipientBalance - oldRecipientBalance == amount,
            "Not enough token was transfered"
        );
    }

    function allLocks() public view returns (Lock[] memory) {
        return _locks;
    }

    function getTotalLockCount() public view returns (uint256) {
        return _locks.length;
    }

    function getLockAt(uint256 index) public view returns (Lock memory) {
        return _locks[index];
    }

    function allLpTokenLockedCount() public view returns (uint256) {
        return _lpLockedTokens.length();
    }

    function allNormalTokenLockedCount() public view returns (uint256) {
        return _normalLockedTokens.length();
    }

    function getCumulativeLpTokenLockInfoAt(uint256 index)
        public
        view
        returns (CumulativeLockInfo memory)
    {
        return cumulativeLockInfo[_lpLockedTokens.at(index)];
    }

    function getCumulativeNormalTokenLockInfoAt(uint256 index)
        public
        view
        returns (CumulativeLockInfo memory)
    {
        return cumulativeLockInfo[_normalLockedTokens.at(index)];
    }

    function getCumulativeLpTokenLockInfo(uint256 start, uint256 end)
        public
        view
        returns (CumulativeLockInfo[] memory)
    {
        if (end >= _lpLockedTokens.length()) {
            end = _lpLockedTokens.length() - 1;
        }
        uint256 length = end - start + 1;
        CumulativeLockInfo[] memory lockInfo = new CumulativeLockInfo[](length);
        uint256 currentIndex = 0;
        for (uint256 i = start; i <= end; i++) {
            lockInfo[currentIndex] = cumulativeLockInfo[_lpLockedTokens.at(i)];
            currentIndex++;
        }
        return lockInfo;
    }

    function getCumulativeNormalTokenLockInfo(uint256 start, uint256 end)
        public
        view
        returns (CumulativeLockInfo[] memory)
    {
        if (end >= _normalLockedTokens.length()) {
            end = _normalLockedTokens.length() - 1;
        }
        uint256 length = end - start + 1;
        CumulativeLockInfo[] memory lockInfo = new CumulativeLockInfo[](length);
        uint256 currentIndex = 0;
        for (uint256 i = start; i <= end; i++) {
            lockInfo[currentIndex] = cumulativeLockInfo[
                _normalLockedTokens.at(i)
            ];
            currentIndex++;
        }
        return lockInfo;
    }

    function totalTokenLockedCount() public view returns (uint256) {
        return allLpTokenLockedCount() + allNormalTokenLockedCount();
    }

    function lpLockCountForUser(address user) public view returns (uint256) {
        return _userLpLockIds[user].length();
    }

    function lpLocksForUser(address user) public view returns (Lock[] memory) {
        uint256 length = _userLpLockIds[user].length();
        Lock[] memory userLocks = new Lock[](length);
        for (uint256 i = 0; i < length; i++) {
            userLocks[i] = _locks[_userLpLockIds[user].at(i)];
        }
        return userLocks;
    }

    function lpLockForUserAtIndex(address user, uint256 index)
        public
        view
        returns (Lock memory)
    {
        require(lpLockCountForUser(user) > index, "Invalid index");
        return _locks[_userLpLockIds[user].at(index)];
    }

    function normalLockCountForUser(address user)
        public
        view
        returns (uint256)
    {
        return _userNormalLockIds[user].length();
    }

    function normalLocksForUser(address user)
        public
        view
        returns (Lock[] memory)
    {
        uint256 length = _userNormalLockIds[user].length();
        Lock[] memory userLocks = new Lock[](length);
        for (uint256 i = 0; i < length; i++) {
            userLocks[i] = _locks[_userNormalLockIds[user].at(i)];
        }
        return userLocks;
    }

    function normalLockForUserAtIndex(address user, uint256 index)
        public
        view
        returns (Lock memory)
    {
        require(normalLockCountForUser(user) > index, "Invalid index");
        return _locks[_userNormalLockIds[user].at(index)];
    }

    function totalLockCountForUser(address user) public view returns (uint256) {
        return normalLockCountForUser(user) + lpLockCountForUser(user);
    }

    function totalLockCountForToken(address token)
        public
        view
        returns (uint256)
    {
        return _tokenToLockIds[token].length();
    }

    function getLocksForToken(
        address token,
        uint256 start,
        uint256 end
    ) public view returns (Lock[] memory) {
        if (end >= _tokenToLockIds[token].length()) {
            end = _tokenToLockIds[token].length() - 1;
        }
        uint256 length = end - start + 1;
        Lock[] memory locks = new Lock[](length);
        uint256 currentIndex = 0;
        for (uint256 i = start; i <= end; i++) {
            locks[currentIndex] = _locks[_tokenToLockIds[token].at(i)];
            currentIndex++;
        }
        return locks;
    }

    function _isValidLpToken(address token, address factory)
        private
        view
        returns (bool)
    {
        IUniswapV2Pair pair = IUniswapV2Pair(token);
        address factoryPair = IUniswapV2Factory(factory).getPair(
            pair.token0(),
            pair.token1()
        );
        return factoryPair == token;
    }

    function _safeTransfer(address token, address to, uint value) internal returns (bool){
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        if (token == usdtAddr) {
            return success;
        }
        return (success && (data.length == 0 || abi.decode(data, (bool))));
    }
}
