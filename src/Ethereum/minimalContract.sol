// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IAccount} from "lib/account-abstraction/contracts/interfaces/IAccount.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {SIG_VALIDATION_FAILED, SIG_VALIDATION_SUCCESS} from "lib/account-abstraction/contracts/core/Helpers.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract MinimalAccount is IAccount, Ownable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error MinimalAccount__NotFromEntryPoint();
    error MinimalAccount__NotFromEntryPointOrOwner();
    error MiniamlAccount__CallFailed(bytes);
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IEntryPoint private immutable i_entryPoint;
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier requireFromEntryPoint() {
        if (msg.sender != address(i_entryPoint)) {
            revert MinimalAccount__NotFromEntryPoint();
        }
        _;
    }

    modifier requireFromEntryPointOrOwner() {
        if (msg.sender != address(i_entryPoint) && msg.sender != owner()) {
            revert MinimalAccount__NotFromEntryPointOrOwner();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address entryPoint) Ownable(msg.sender) {
        i_entryPoint = IEntryPoint(entryPoint);
    }

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function execute(address dest, uint256 value, bytes calldata functionData) external requireFromEntryPointOrOwner {
        (bool success, bytes memory result) = payable(dest).call{value: value}(functionData);
        if (!success) {
            revert MiniamlAccount__CallFailed(result);
        }
    }

    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external
        requireFromEntryPoint
        returns (uint256 validationData)
    {
        validationData = _validateSignature(userOp, userOpHash);
        _payPreFund(missingAccountFunds);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _validateSignature(PackedUserOperation calldata userOp, bytes32 userOpHash)
        internal
        view
        returns (uint256 validationData)
    {
        bytes32 ethSignedMessgeHash = MessageHashUtils.toEthSignedMessageHash(userOpHash);
        (address signer,,) = ECDSA.tryRecover(ethSignedMessgeHash, userOp.signature);
        if (signer == owner()) {
            return SIG_VALIDATION_SUCCESS;
        }
        return SIG_VALIDATION_FAILED;
    }

    function _payPreFund(uint256 missingAccountFunds) private {
        (bool success,) = payable(msg.sender).call{value: missingAccountFunds, gas: type(uint256).max}("");
        (success);
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/
    function getEntryPoint() external view returns (address) {
        return address(i_entryPoint);
    }
}
