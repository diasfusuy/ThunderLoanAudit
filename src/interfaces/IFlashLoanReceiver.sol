// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

//@audit info : unused import, should be removed
// its bad engineering practice to use live code for mock/tests, must remove from mock 
import { IThunderLoan } from "./IThunderLoan.sol";

/**
 * @dev Inspired by Aave:
 * https://github.com/aave/aave-v3-core/blob/master/contracts/flashloan/interfaces/IFlashLoanReceiver.sol
 */
interface IFlashLoanReceiver {
    // q is the token, token being borrowed? 
    // q amaount is the amount of tokens?
    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    )
        external
        returns (bool);
}
