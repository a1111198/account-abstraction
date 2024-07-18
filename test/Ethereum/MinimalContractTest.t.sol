// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MinimalAccount} from "../../src/Ethereum/minimalContract.sol";
import {DeployMinimalAccount} from "../../script/DeployMinimalContract.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {SendPackedUserOp, PackedUserOperation} from "script/SendPackedUserOp.s.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";

contract MinimalContractTest is Test {
    using MessageHashUtils for bytes32;

    HelperConfig helperConfig;
    MinimalAccount minimalAccount;
    uint256 AMOUNT = 1e18;
    ERC20Mock usdc;
    address randomuser = makeAddr("randomUser");
    SendPackedUserOp sendPackedUserOp;

    function setUp() public {
        DeployMinimalAccount deployMinimal = new DeployMinimalAccount();
        (helperConfig, minimalAccount) = deployMinimal.deployMinimalAccount();
        usdc = new ERC20Mock();
        sendPackedUserOp = new SendPackedUserOp();
    }

    function testOwnerCanExecuteCommands() public {
        //Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);

        address ownerOfMinimalAccount = minimalAccount.owner();
        vm.startPrank(ownerOfMinimalAccount);
        minimalAccount.execute(dest, value, functionData);
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
        vm.stopPrank();
    }

    function testNonOwnerCanNotExecuteCommands() public {
        //Arrange

        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);

        vm.startPrank(randomuser);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointOrOwner.selector);
        minimalAccount.execute(dest, value, functionData);
        vm.stopPrank();
    }

    function testValidationOfUserOps() public {
        //Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(minimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory packedUserOperation = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        bytes32 userOpHashsigned = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOperation);
        vm.prank(helperConfig.getConfig().entryPoint);
        uint256 missingAccountFunds = 1e18;
        uint256 validationData =
            minimalAccount.validateUserOp(packedUserOperation, userOpHashsigned, missingAccountFunds);
        assertEq(validationData, 0);
    }

    function testRecoverSignedOp() public {
        //Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(minimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory packedUserOperation = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        bytes32 userOpHashsigned = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOperation);
        //Act
        address signer = ECDSA.recover(userOpHashsigned.toEthSignedMessageHash(), packedUserOperation.signature);
        assertEq(signer, minimalAccount.owner());
    }

    function testExecuteUsingEntryPoint() public {
        assertEq(usdc.balanceOf(randomuser), 0);
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, randomuser, AMOUNT);
        bytes memory executeCallData =
            abi.encodeWithSelector(minimalAccount.execute.selector, dest, value, functionData);
        PackedUserOperation memory packedUserOperation = sendPackedUserOp.generateSignedUserOperation(
            executeCallData, helperConfig.getConfig(), address(minimalAccount)
        );

        vm.deal(address(minimalAccount), AMOUNT);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOperation;

        //Act
        vm.prank(randomuser);
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(randomuser));
        assertEq(usdc.balanceOf(randomuser), AMOUNT);
    }
}
