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
    error AlreadyWithdrawn();

    // CTG contracts
    address public constant CTG_TOKEN_CONTRACT = 0x4DfC7EA5aC59B63223930C134796fecC4258d093;
    uint256 public constant CTG_VOTING_START_TIMESTAMP = 1713398400;
    uint256 public constant WITHDRAWAL_ENABLED_TIMESTAMP = 1715918400; // 1 month after voting
    uint256 public constant ACCOUNT_UNLOCK_TIMESTAMP = 1718596800; // 1 month after withdrawal opens

    uint8 public constant STAKERS_SHARE_PERCENTAGE = 50;

    EnumerableMap.UintToAddressMap private tokenIdToOriginalOwnerMap;

    address public selfOwnershipAccount;
    uint256 public amountPerStaker;
    bool public isEarlyWithdrawalEnabled;

    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        payable
        virtual
        override
        returns (bytes memory result)
    {
        require(_isValidSigner(msg.sender), "Invalid signer");
        require(operation == 0, "Only call operations are supported");

        // Impose restrictions on the account until after withdrawal period has expired
        if (block.timestamp < ACCOUNT_UNLOCK_TIMESTAMP) {
            // Prevent Will from transferring CTG tokens out of the account
            require(to != CTG_TOKEN_CONTRACT, "Cannot call CTG token contract");

            // Prevent transfers of ETH out of the account
            require(value == 0, "Invalid value");
        }

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

    function isWithdrawalEnabled() public view returns (bool) {
        return isEarlyWithdrawalEnabled || block.timestamp >= WITHDRAWAL_ENABLED_TIMESTAMP;
    }

    function enableEarlyWithdrawals() external {
        // onlyOwner
        require(_isValidSigner(msg.sender), "Invalid signer");
        require(!isEarlyWithdrawalEnabled, "Early withdrawals already enabled");
        // enable Withdrawals
        isEarlyWithdrawalEnabled = true;

        // calculate amountPerStaker
        uint256 numRemainingStakers = tokenIdToOriginalOwnerMap.length();

        // Avoid division by zero if Will calls this function after all stakers have unstaked
        if (numRemainingStakers == 0) {
            amountPerStaker = 0;
        } else {
            amountPerStaker =
                ((address(this).balance * STAKERS_SHARE_PERCENTAGE) / 100) / tokenIdToOriginalOwnerMap.length();
        }

        uint256 amountOfOwner = ((address(this).balance * (100 - STAKERS_SHARE_PERCENTAGE)) / 100);

        // return participant token
        if (selfOwnershipAccount != address(0)) {
            (,, uint256 accountTokenId) = token();
            address recipient = selfOwnershipAccount;

            selfOwnershipAccount = address(0);
            IERC721(CTG_TOKEN_CONTRACT).transferFrom(address(this), recipient, accountTokenId);
        }

        // payout winner
        (bool success,) = owner().call{value: amountOfOwner}("");
        if (!success) revert EnableWithdrawalsFailed();
    }

    function batchWithdraw() external {
        // Check if withdrawals are enabled
        require(isWithdrawalEnabled(), "Withdrawals are not enabled");

        uint256[] memory tokenIds = tokenIdToOriginalOwnerMap.keys();
        uint256 stakedTokenCount = tokenIds.length;

        // Transfer all CTG tokens out of the account
        for (uint256 i = 0; i < stakedTokenCount; i++) {
            uint256 tokenId = tokenIds[i];

            _withdraw(tokenId);
        }
    }

    function withdraw(uint256 tokenId) external {
        // Check if withdrawals are enabled
        require(isWithdrawalEnabled(), "Withdrawals are not enabled");

        _withdraw(tokenId);
    }

    function _withdraw(uint256 tokenId) private {
        address originalOwner = tokenIdToOriginalOwnerMap.get(tokenId);

        bool removed = EnumerableMap.remove(tokenIdToOriginalOwnerMap, tokenId);
        if (!removed) revert AlreadyWithdrawn();

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
            (uint256 tokenId, address originalOwner) = tokenIdToOriginalOwnerMap.at(i);
            if (originalOwner == staker) {
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
