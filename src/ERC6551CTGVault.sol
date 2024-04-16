// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

import "erc6551/src/interfaces/IERC6551Registry.sol";
import "erc6551/src/examples/simple/ERC6551Account.sol";
import "erc6551/src/lib/ERC6551AccountLib.sol";

contract ERC6551CTGVault is ERC721Holder, ERC6551Account {
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    error EnableWithdrawalsFailed();
    error WithdrawalFailed();

    // ERC6551 constants
    address public constant registry = 0x000000006551c19487814612e58FE06813775758;
    address public constant proxy = 0x55266d75D1a14E4572138116aF39863Ed6596E7F;

    // V3 account implementation
    address public constant implementation = 0x41C8f39463A868d3A88af00cd0fe7102F30E44eC;

    address public constant CTG_TOKEN_CONTRACT = 0x87f7266fA4e9da89E3710882bD0E10954fa1D48D;
    uint256 public constant CTG_VOTING_START_TIMESTAMP = 1713398400;
    uint8 public constant STAKERS_SHARE_PERCENTAGE = 50;

    EnumerableMap.UintToAddressMap private tokenIdToOriginalOwnerMap;

    address public selfOwnershipAccount;
    uint256 public amountPerStaker;
    bool public isWithdrawalEnabled;

    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        payable
        virtual
        override
        returns (bytes memory result)
    {
        require(_isValidSigner(msg.sender), "Invalid signer");
        require(operation == 0, "Only call operations are supported");

        // Prevent Will from transferring CTG tokens out of the account
        require(to != CTG_TOKEN_CONTRACT, "Cannot call CTG token contract");

        // Prevent Will from transferring his participant token out of the account
        (, address accountTokenContract,) = token();
        require(to != accountTokenContract, "Cannot call account token contract");

        // Prevent transfers of ETH out of the account
        require(value == 0, "Invalid value");

        ++state;

        bool success;
        (success, result) = to.call{value: value}(data);

        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    function onERC721Received(address, address from, uint256 tokenId, bytes memory)
        public
        virtual
        override
        returns (bytes4)
    {
        require(IERC721(msg.sender).ownerOf(tokenId) == address(this), "Invalid token owner");

        (uint256 chainId, address tokenContract, uint256 accountTokenId) = ERC6551AccountLib.token();

        // Record original owner of token sent in if CTG contract
        if (msg.sender == CTG_TOKEN_CONTRACT && accountTokenId != tokenId) {
            require(block.timestamp < CTG_VOTING_START_TIMESTAMP, "Deposits have been closed since voting started");
            tokenIdToOriginalOwnerMap.set(tokenId, from);
        }

        // Record sender of participant token (will's address)
        if (chainId == block.chainid && msg.sender == tokenContract && tokenId == accountTokenId) {
            selfOwnershipAccount = from;
        }

        return this.onERC721Received.selector;
    }

    function owner() public view override returns (address) {
        (uint256 chainId, address tokenContract, uint256 tokenId) = token();
        if (chainId != block.chainid) return address(0);

        if (selfOwnershipAccount != address(0)) return selfOwnershipAccount;

        return IERC721(tokenContract).ownerOf(tokenId);
    }

    function enableWithdrawals() public {
        // onlyOwner
        require(_isValidSigner(msg.sender), "Invalid signer");

        // enable Withdrawals
        isWithdrawalEnabled = true;

        // calculate amountPerStaker
        amountPerStaker =
            ((address(this).balance * STAKERS_SHARE_PERCENTAGE) / 100) / tokenIdToOriginalOwnerMap.length();

        uint256 amountOfOwner = ((address(this).balance * (100 - STAKERS_SHARE_PERCENTAGE)) / 100);

        // return participant token
        if (selfOwnershipAccount != address(0)) {
            address recipient = selfOwnershipAccount;
            (, address accountTokenContract, uint256 tokenId) = token();
            selfOwnershipAccount = address(0);
            IERC721(accountTokenContract).safeTransferFrom(address(this), recipient, tokenId);
        }

        // payout winner
        (bool success,) = owner().call{value: amountOfOwner}("");
        if (!success) revert EnableWithdrawalsFailed();
    }

    function batchWithdraw() public {
        // Check if withdrawals are enabled
        require(isWithdrawalEnabled, "Withdrawals are not enabled");

        uint256[] memory tokenIds = tokenIdToOriginalOwnerMap.keys();
        uint256 stakedTokenCount = tokenIds.length;

        // Transfer all CTG tokens out of the account
        for (uint256 i = 0; i < stakedTokenCount; i++) {
            uint256 tokenId = tokenIds[i];

            _withdraw(tokenId);
        }
    }

    function withdraw(uint256 tokenId) public {
        // Check if withdrawals are enabled
        require(isWithdrawalEnabled, "Withdrawals are not enabled");

        _withdraw(tokenId);
    }

    function _withdraw(uint256 tokenId) private {
        address originalOwner = tokenIdToOriginalOwnerMap.get(tokenId);

        EnumerableMap.remove(tokenIdToOriginalOwnerMap, tokenId);

        IERC721(CTG_TOKEN_CONTRACT).transferFrom(address(this), originalOwner, tokenId);

        // Transfer a portion of the balance to the original owner
        (bool success,) = originalOwner.call{value: amountPerStaker}("");
        if (!success) revert WithdrawalFailed();
    }

    function getStakedTokenIds(address staker) public view returns (uint256[] memory) {
        uint256 totalStakedTokens = tokenIdToOriginalOwnerMap.length();
        uint256[] memory stakedTokenIds = new uint256[](totalStakedTokens);

        uint256 count = 0;
        for (uint256 i = 0; i < totalStakedTokens; i++) {
            (uint256 tokenId, address owner) = tokenIdToOriginalOwnerMap.at(i);
            if (owner == staker) {
                stakedTokenIds[count] = tokenId;
                count++;
            }
        }

        // Resize the array to fit only the staked tokens
        uint256[] memory fittedStakedTokenIds = new uint256[](count);
        for (uint256 j = 0; j < count; j++) {
            fittedStakedTokenIds[j] = stakedTokenIds[j];
        }

        return fittedStakedTokenIds;
    }
}
