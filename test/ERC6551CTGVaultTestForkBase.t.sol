// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC6551CTGVault} from "../src/ERC6551CTGVault.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import "erc6551/src/interfaces/IERC6551Registry.sol";

contract ERC6551CTGVaultTestForkBase is Test {
    ERC6551CTGVault public erc6551CTGVault;

    ERC721 public ctgTokenContract;

    // Thank you Solady: https://github.com/Vectorized/solady/blob/9ea8a82b4485478b2ef5efdcc8012b10c2b7d865/src/accounts/LibERC6551.sol#L26
    /// @dev The canonical ERC6551 registry address for EVM chains.
    address internal constant REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    /// @dev The canonical ERC6551 registry bytecode for EVM chains.
    /// Useful for forge tests:
    bytes internal constant REGISTRY_BYTECODE =
        hex"608060405234801561001057600080fd5b50600436106100365760003560e01c8063246a00211461003b5780638a54c52f1461006a575b600080fd5b61004e6100493660046101b7565b61007d565b6040516001600160a01b03909116815260200160405180910390f35b61004e6100783660046101b7565b6100e1565b600060806024608c376e5af43d82803e903d91602b57fd5bf3606c5285605d52733d60ad80600a3d3981f3363d3d373d3d3d363d7360495260ff60005360b76055206035523060601b60015284601552605560002060601b60601c60005260206000f35b600060806024608c376e5af43d82803e903d91602b57fd5bf3606c5285605d52733d60ad80600a3d3981f3363d3d373d3d3d363d7360495260ff60005360b76055206035523060601b600152846015526055600020803b61018b578560b760556000f580610157576320188a596000526004601cfd5b80606c52508284887f79f19b3655ee38b1ce526556b7731a20c8f218fbda4a3990b6cc4172fdf887226060606ca46020606cf35b8060601b60601c60005260206000f35b80356001600160a01b03811681146101b257600080fd5b919050565b600080600080600060a086880312156101cf57600080fd5b6101d88661019b565b945060208601359350604086013592506101f46060870161019b565b94979396509194608001359291505056fea2646970667358221220ea2fe53af507453c64dd7c1db05549fa47a298dfb825d6d11e1689856135f16764736f6c63430008110033";

    uint256 baseFork;
    uint256 WILL_TOKEN_ID = 65;

    uint256 JURY_OWNER_1_TOKEN_ID = 2;
    uint256 JURY_OWNER_2_TOKEN_ID_1 = 123;
    uint256 JURY_OWNER_2_TOKEN_ID_2 = 198;
    uint256 JURY_OWNER_2_TOKEN_ID_3 = 741;

    function setUp() public {
        baseFork = vm.createFork("https://mainnet.base.org");
        vm.selectFork(baseFork);
        vm.rollFork(13268448);

        vm.etch(REGISTRY, REGISTRY_BYTECODE);

        ctgTokenContract = ERC721(0x4DfC7EA5aC59B63223930C134796fecC4258d093);
        erc6551CTGVault = new ERC6551CTGVault();
    }

    address will;
    address juryOwner1;
    address juryOwner2;
    address willTba;

    function prepareWithdrawal() public {
        will = 0x69EC014c15baF1C96620B6BA02A391aBaBB9C96b;
        juryOwner1 = 0x5008b5DD4bdbD96eD8897e56EBC8e84D2A824687;
        juryOwner2 = 0xE22276077f9DB31B0be7E78aD91aCD60bC8Eb6b2;

        willTba = IERC6551Registry(REGISTRY).createAccount(
            address(erc6551CTGVault), 0, block.chainid, address(ctgTokenContract), WILL_TOKEN_ID
        );

        // move will's token to it's own account
        vm.prank(will);
        ctgTokenContract.safeTransferFrom(will, willTba, WILL_TOKEN_ID);

        assertEq(ctgTokenContract.ownerOf(WILL_TOKEN_ID), willTba);

        // Move jury tokens to will's vault account
        vm.prank(juryOwner1);
        ctgTokenContract.safeTransferFrom(juryOwner1, willTba, JURY_OWNER_1_TOKEN_ID);

        vm.startPrank(juryOwner2);
        ctgTokenContract.safeTransferFrom(juryOwner2, willTba, JURY_OWNER_2_TOKEN_ID_1);
        ctgTokenContract.safeTransferFrom(juryOwner2, willTba, JURY_OWNER_2_TOKEN_ID_2);
        ctgTokenContract.safeTransferFrom(juryOwner2, willTba, JURY_OWNER_2_TOKEN_ID_3);
        vm.stopPrank();
    }

    // HAPPY PATH WITHDRAWAL TESTS
    function test_BatchWithdraw() public {
        prepareWithdrawal();

        vm.deal(willTba, 80 ether);

        vm.warp(erc6551CTGVault.CTG_VOTING_START_TIMESTAMP());
        vm.prank(will);

        uint256 prevWillBalance = will.balance;
        uint256 prevJuryOwner1Balance = juryOwner1.balance;
        uint256 prevJuryOwner2Balance = juryOwner2.balance;

        ERC6551CTGVault(payable(willTba)).enableEarlyWithdrawals();

        vm.assertEq(will.balance, prevWillBalance + 40 ether);

        ERC6551CTGVault(payable(willTba)).batchWithdraw();

        vm.assertEq(juryOwner1.balance, prevJuryOwner1Balance + 10 ether);
        vm.assertEq(juryOwner2.balance, prevJuryOwner2Balance + 30 ether);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_1_TOKEN_ID), juryOwner1);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_1), juryOwner2);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_2), juryOwner2);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_3), juryOwner2);
    }

    function test_IndividualWithdraw() public {
        prepareWithdrawal();

        vm.deal(willTba, 80 ether);

        uint256 prevWillBalance = will.balance;
        uint256 prevJuryOwner1Balance = juryOwner1.balance;
        uint256 prevJuryOwner2Balance = juryOwner2.balance;

        vm.warp(erc6551CTGVault.CTG_VOTING_START_TIMESTAMP());
        vm.prank(will);
        ERC6551CTGVault(payable(willTba)).enableEarlyWithdrawals();

        vm.assertEq(will.balance, prevWillBalance + 40 ether);

        ERC6551CTGVault(payable(willTba)).withdraw(JURY_OWNER_1_TOKEN_ID);
        ERC6551CTGVault(payable(willTba)).withdraw(JURY_OWNER_2_TOKEN_ID_1);
        ERC6551CTGVault(payable(willTba)).withdraw(JURY_OWNER_2_TOKEN_ID_2);
        ERC6551CTGVault(payable(willTba)).withdraw(JURY_OWNER_2_TOKEN_ID_3);

        vm.assertEq(juryOwner1.balance, prevJuryOwner1Balance + 10 ether);
        vm.assertEq(juryOwner2.balance, prevJuryOwner2Balance + 30 ether);

        vm.assertEq(ctgTokenContract.ownerOf(WILL_TOKEN_ID), will);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_1_TOKEN_ID), juryOwner1);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_1), juryOwner2);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_2), juryOwner2);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_3), juryOwner2);
    }

    function test_NoBalanceBatchWithdraw() public {
        prepareWithdrawal();

        uint256 prevWillBalance = will.balance;
        uint256 prevJuryOwner1Balance = juryOwner1.balance;
        uint256 prevJuryOwner2Balance = juryOwner2.balance;

        vm.warp(erc6551CTGVault.CTG_VOTING_START_TIMESTAMP());
        vm.prank(will);
        ERC6551CTGVault(payable(willTba)).enableEarlyWithdrawals();

        vm.assertEq(will.balance, prevWillBalance);

        ERC6551CTGVault(payable(willTba)).batchWithdraw();

        vm.assertEq(juryOwner1.balance, prevJuryOwner1Balance);
        vm.assertEq(juryOwner2.balance, prevJuryOwner2Balance);
        vm.assertEq(ctgTokenContract.ownerOf(WILL_TOKEN_ID), will);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_1_TOKEN_ID), juryOwner1);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_1), juryOwner2);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_2), juryOwner2);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_3), juryOwner2);
    }

    // TESTS TO VERIFY WILL CANT STEAL ASSETS
    function testFail_TransferEther() public {
        prepareWithdrawal();

        vm.deal(willTba, 80 ether);

        vm.warp(erc6551CTGVault.CTG_VOTING_START_TIMESTAMP());
        vm.prank(will);
        ERC6551CTGVault(payable(willTba)).execute(will, 1 ether, "", 0);
    }

    function testFail_TransferCTGTokens() public {
        prepareWithdrawal();

        vm.warp(erc6551CTGVault.CTG_VOTING_START_TIMESTAMP());
        vm.prank(will);
        ERC6551CTGVault(payable(willTba)).enableEarlyWithdrawals();

        vm.assertEq(will.balance, 40 ether);

        vm.prank(will);
        ERC6551CTGVault(payable(willTba)).execute(
            address(ctgTokenContract),
            0,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256)", juryOwner1, willTba, JURY_OWNER_1_TOKEN_ID
            ),
            0
        );
    }

    // TESTS TO MAKE SURE ONLY WILL CAN TOGGLE WITHDRAWALS
    function testFail_NonWillEnableEarlyWithdrawals() public {
        prepareWithdrawal();

        vm.warp(erc6551CTGVault.CTG_VOTING_START_TIMESTAMP());
        vm.prank(juryOwner1);
        ERC6551CTGVault(payable(willTba)).enableEarlyWithdrawals();
    }

    // TESTS TO MAKE SURE NO ONE CAN WITHDRAW BEFORE WITHDRAWALS ARE ENABLED
    function testFail_BatchWithdrawBeforeEnabled() public {
        prepareWithdrawal();

        vm.warp(erc6551CTGVault.CTG_VOTING_START_TIMESTAMP());
        ERC6551CTGVault(payable(willTba)).batchWithdraw();
    }

    // MAKE SURE NO ONE CAN DEPOSIT AFTER CTG VOTING STARTS
    function testFail_DepositAfterVotingStarts() public {
        vm.warp(erc6551CTGVault.CTG_VOTING_START_TIMESTAMP());
        prepareWithdrawal();
    }

    // MAKE SURE PEOPLE CAN WITHDRAW AFTER THE WITHDRAWAL ENABLE TIMESTAMP
    function test_BatchWithdrawAfterEnabled() public {
        prepareWithdrawal();

        vm.warp(erc6551CTGVault.WITHDRAWAL_ENABLED_TIMESTAMP() + WILL_TOKEN_ID);

        ERC6551CTGVault(payable(willTba)).batchWithdraw();

        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_1_TOKEN_ID), juryOwner1);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_1), juryOwner2);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_2), juryOwner2);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_3), juryOwner2);
    }

    function test_IndividualWithdrawAfterEnabled() public {
        prepareWithdrawal();

        vm.warp(erc6551CTGVault.WITHDRAWAL_ENABLED_TIMESTAMP() + WILL_TOKEN_ID);

        ERC6551CTGVault(payable(willTba)).withdraw(JURY_OWNER_1_TOKEN_ID);
        ERC6551CTGVault(payable(willTba)).withdraw(JURY_OWNER_2_TOKEN_ID_1);
        ERC6551CTGVault(payable(willTba)).withdraw(JURY_OWNER_2_TOKEN_ID_2);
        ERC6551CTGVault(payable(willTba)).withdraw(JURY_OWNER_2_TOKEN_ID_3);

        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_1_TOKEN_ID), juryOwner1);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_1), juryOwner2);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_2), juryOwner2);
        vm.assertEq(ctgTokenContract.ownerOf(JURY_OWNER_2_TOKEN_ID_3), juryOwner2);

        vm.prank(will);
        ERC6551CTGVault(payable(willTba)).enableEarlyWithdrawals();

        vm.assertEq(ctgTokenContract.ownerOf(WILL_TOKEN_ID), will);
    }
}
