// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

// e this is probably interface to work with TSwap 
// qanswered why are we using TSwap]
// use to calculate fees
interface IPoolFactory {
    function getPool(address tokenAddress) external view returns (address);
}
