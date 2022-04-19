// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

interface ILock {
    function lockTransfer(
        address token,
        address to,
        uint256 amount,
        uint256 releaseStartTime,
        uint256 releaseCycle,
        uint256 releaseTimes
    ) external returns (bool);

    function getLockAmount(address token, address account) external view returns (uint256);

    // event LockTransfer(
    //     address token,
    //     address to,
    //     uint256 amount,
    //     uint256 transferAmount,
    //     uint256 releaseStartTime,
    //     uint256 releaseCycle,
    //     uint256 releaseTimes
    // );
}