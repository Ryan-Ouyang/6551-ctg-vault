// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {ERC6551CTGVault} from "../src/ERC6551CTGVault.sol";
import {DummyToken} from "./DummyToken.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

import "erc6551/src/interfaces/IERC6551Registry.sol";

contract ERC6551CTGVaultTest is Test {
    ERC6551CTGVault public erc6551CTGVault;

    DummyToken public ctgTokenContract;

    /// @dev The canonical ERC6551 registry address for EVM chains.
    address internal constant REGISTRY =
        0x000000006551c19487814612e58FE06813775758;

    /// @dev The canonical ERC6551 registry bytecode for EVM chains.
    /// Useful for forge tests:
    bytes internal constant REGISTRY_BYTECODE =
        hex"608060405234801561001057600080fd5b50600436106100365760003560e01c8063246a00211461003b5780638a54c52f1461006a575b600080fd5b61004e6100493660046101b7565b61007d565b6040516001600160a01b03909116815260200160405180910390f35b61004e6100783660046101b7565b6100e1565b600060806024608c376e5af43d82803e903d91602b57fd5bf3606c5285605d52733d60ad80600a3d3981f3363d3d373d3d3d363d7360495260ff60005360b76055206035523060601b60015284601552605560002060601b60601c60005260206000f35b600060806024608c376e5af43d82803e903d91602b57fd5bf3606c5285605d52733d60ad80600a3d3981f3363d3d373d3d3d363d7360495260ff60005360b76055206035523060601b600152846015526055600020803b61018b578560b760556000f580610157576320188a596000526004601cfd5b80606c52508284887f79f19b3655ee38b1ce526556b7731a20c8f218fbda4a3990b6cc4172fdf887226060606ca46020606cf35b8060601b60601c60005260206000f35b80356001600160a01b03811681146101b257600080fd5b919050565b600080600080600060a086880312156101cf57600080fd5b6101d88661019b565b945060208601359350604086013592506101f46060870161019b565b94979396509194608001359291505056fea2646970667358221220ea2fe53af507453c64dd7c1db05549fa47a298dfb825d6d11e1689856135f16764736f6c63430008110033";

    function setUp() public {
        vm.etch(REGISTRY, REGISTRY_BYTECODE);

        ctgTokenContract = new DummyToken("CTG Token", "CTG");
        erc6551CTGVault = new ERC6551CTGVault();

        vm.etch(
            erc6551CTGVault.CTG_TOKEN_CONTRACT(),
            address(ctgTokenContract).code
        );
    }

    function test_BatchWithdraw() public {
        address will = makeAddr("will");
        address juryOwner1 = makeAddr("juryOwner1");
        address juryOwner2 = makeAddr("juryOwner2");

        DummyToken tokenContract = DummyToken(
            erc6551CTGVault.CTG_TOKEN_CONTRACT()
        );

        tokenContract.mint(will, 1); // Will's token
        tokenContract.mint(juryOwner1, 2); // Jury token #1
        tokenContract.mint(juryOwner2, 3); // Jury token #2
        tokenContract.mint(juryOwner2, 4); // Jury token #3
        tokenContract.mint(juryOwner2, 5); // Jury token #4

        address willTba = IERC6551Registry(REGISTRY).createAccount(
            address(erc6551CTGVault),
            0,
            block.chainid,
            address(tokenContract),
            1
        );

        // Move jury tokens to will's vault account
        vm.prank(juryOwner1);
        tokenContract.safeTransferFrom(juryOwner1, willTba, 2);

        vm.prank(juryOwner2);
        tokenContract.safeTransferFrom(juryOwner2, willTba, 3);
        vm.prank(juryOwner2);
        tokenContract.safeTransferFrom(juryOwner2, willTba, 4);
        vm.prank(juryOwner2);
        tokenContract.safeTransferFrom(juryOwner2, willTba, 5);

        vm.deal(willTba, 80 ether);

        vm.prank(will);
        ERC6551CTGVault(payable(willTba)).enableWithdrawals();

        vm.assertEq(will.balance, 40 ether);

        ERC6551CTGVault(payable(willTba)).batchWithdraw();

        vm.assertEq(juryOwner1.balance, 10 ether);
        vm.assertEq(juryOwner2.balance, 30 ether);
    }

    function test_IndividualWithdraw() public {
        address will = makeAddr("will");
        address juryOwner1 = makeAddr("juryOwner1");
        address juryOwner2 = makeAddr("juryOwner2");

        DummyToken tokenContract = DummyToken(
            erc6551CTGVault.CTG_TOKEN_CONTRACT()
        );

        tokenContract.mint(will, 1); // Will's token
        tokenContract.mint(juryOwner1, 2); // Jury token #1
        tokenContract.mint(juryOwner2, 3); // Jury token #2
        tokenContract.mint(juryOwner2, 4); // Jury token #3
        tokenContract.mint(juryOwner2, 5); // Jury token #4

        address willTba = IERC6551Registry(REGISTRY).createAccount(
            address(erc6551CTGVault),
            0,
            block.chainid,
            address(tokenContract),
            1
        );

        // Move jury tokens to will's vault account
        vm.prank(juryOwner1);
        tokenContract.safeTransferFrom(juryOwner1, willTba, 2);

        vm.prank(juryOwner2);
        tokenContract.safeTransferFrom(juryOwner2, willTba, 3);
        vm.prank(juryOwner2);
        tokenContract.safeTransferFrom(juryOwner2, willTba, 4);
        vm.prank(juryOwner2);
        tokenContract.safeTransferFrom(juryOwner2, willTba, 5);

        vm.deal(willTba, 80 ether);

        vm.prank(will);
        ERC6551CTGVault(payable(willTba)).enableWithdrawals();

        vm.assertEq(will.balance, 40 ether);

        for (uint256 i = 2; i <= 5; i++) {
            ERC6551CTGVault(payable(willTba)).withdraw(i);
        }

        vm.assertEq(juryOwner1.balance, 10 ether);
        vm.assertEq(juryOwner2.balance, 30 ether);
    }

    function testFail_TransferEther() public {
        address will = makeAddr("will");
        address juryOwner1 = makeAddr("juryOwner1");
        address juryOwner2 = makeAddr("juryOwner2");

        DummyToken tokenContract = DummyToken(
            erc6551CTGVault.CTG_TOKEN_CONTRACT()
        );

        tokenContract.mint(will, 1); // Will's token
        tokenContract.mint(juryOwner1, 2); // Jury token #1
        tokenContract.mint(juryOwner2, 3); // Jury token #2
        tokenContract.mint(juryOwner2, 4); // Jury token #3
        tokenContract.mint(juryOwner2, 5); // Jury token #4

        address willTba = IERC6551Registry(REGISTRY).createAccount(
            address(erc6551CTGVault),
            0,
            block.chainid,
            address(tokenContract),
            1
        );

        // Move jury tokens to will's vault account
        vm.prank(juryOwner1);
        tokenContract.safeTransferFrom(juryOwner1, willTba, 2);

        vm.prank(juryOwner2);
        tokenContract.safeTransferFrom(juryOwner2, willTba, 3);
        vm.prank(juryOwner2);
        tokenContract.safeTransferFrom(juryOwner2, willTba, 4);
        vm.prank(juryOwner2);
        tokenContract.safeTransferFrom(juryOwner2, willTba, 5);

        vm.deal(willTba, 80 ether);

        vm.prank(will);
        ERC6551CTGVault(payable(willTba)).execute(will, 1 ether, "", 0);
    }

    function testFail_TransferCTGTokens() public {
        address will = makeAddr("will");
        address juryOwner1 = makeAddr("juryOwner1");
        address juryOwner2 = makeAddr("juryOwner2");

        DummyToken tokenContract = DummyToken(
            erc6551CTGVault.CTG_TOKEN_CONTRACT()
        );

        tokenContract.mint(will, 1); // Will's token
        tokenContract.mint(juryOwner1, 2); // Jury token #1
        tokenContract.mint(juryOwner2, 3); // Jury token #2
        tokenContract.mint(juryOwner2, 4); // Jury token #3
        tokenContract.mint(juryOwner2, 5); // Jury token #4

        address willTba = IERC6551Registry(REGISTRY).createAccount(
            address(erc6551CTGVault),
            0,
            block.chainid,
            address(tokenContract),
            1
        );

        // Move jury tokens to will's vault account
        vm.prank(juryOwner1);
        tokenContract.safeTransferFrom(juryOwner1, willTba, 2);

        vm.prank(juryOwner2);
        tokenContract.safeTransferFrom(juryOwner2, willTba, 3);
        vm.prank(juryOwner2);
        tokenContract.safeTransferFrom(juryOwner2, willTba, 4);
        vm.prank(juryOwner2);
        tokenContract.safeTransferFrom(juryOwner2, willTba, 5);

        vm.deal(willTba, 80 ether);

        vm.prank(will);
        ERC6551CTGVault(payable(willTba)).enableWithdrawals();

        vm.assertEq(will.balance, 40 ether);

        vm.prank(will);
        ERC6551CTGVault(payable(willTba)).execute(
            address(tokenContract),
            0,
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256)",
                juryOwner1,
                willTba,
                2
            ),
            0
        );
    }
}
