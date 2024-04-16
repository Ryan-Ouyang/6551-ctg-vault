// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";

interface IERC6551Account {
    receive() external payable;

    function token()
        external
        view
        returns (uint256 chainId, address tokenContract, uint256 tokenId);

    function state() external view returns (uint256);

    function isValidSigner(
        address signer,
        bytes calldata context
    ) external view returns (bytes4 magicValue);
}

interface IERC6551Executable {
    function execute(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation
    ) external payable returns (bytes memory);
}

contract ERC6551Account is
    IERC165,
    IERC1271,
    IERC6551Account,
    IERC6551Executable,
    ERC721Holder
{
    using EnumerableMap for EnumerableMap.UintToAddressMap;

    uint256 public state;

    address public constant CTG_TOKEN_CONTRACT =
        0x87f7266fA4e9da89E3710882bD0E10954fa1D48D;
    uint8 public constant STAKERS_SHARE_PERCENTAGE = 50;

    EnumerableMap.UintToAddressMap private tokenIdToOriginalOwnerMap;

    uint256 public amountPerStaker;
    bool public isWithdrawalEnabled;

    receive() external payable {}

    function execute(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation
    ) external payable virtual returns (bytes memory result) {
        require(_isValidSigner(msg.sender), "Invalid signer");
        require(operation == 0, "Only call operations are supported");

        // Prevent Will from transferring CTG tokens out of the account
        require(to != CTG_TOKEN_CONTRACT, "Invalid target contract");

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

    function isValidSigner(
        address signer,
        bytes calldata
    ) external view virtual returns (bytes4) {
        if (_isValidSigner(signer)) {
            return IERC6551Account.isValidSigner.selector;
        }

        return bytes4(0);
    }

    function isValidSignature(
        bytes32 hash,
        bytes memory signature
    ) external view virtual returns (bytes4 magicValue) {
        bool isValid = SignatureChecker.isValidSignatureNow(
            owner(),
            hash,
            signature
        );

        if (isValid) {
            return IERC1271.isValidSignature.selector;
        }

        return bytes4(0);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual returns (bool) {
        return
            interfaceId == type(IERC165).interfaceId ||
            interfaceId == type(IERC6551Account).interfaceId ||
            interfaceId == type(IERC6551Executable).interfaceId;
    }

    function token() public view virtual returns (uint256, address, uint256) {
        bytes memory footer = new bytes(0x60);

        assembly {
            extcodecopy(address(), add(footer, 0x20), 0x4d, 0x60)
        }

        return abi.decode(footer, (uint256, address, uint256));
    }

    function owner() public view virtual returns (address) {
        (uint256 chainId, address tokenContract, uint256 tokenId) = token();
        if (chainId != block.chainid) return address(0);

        return IERC721(tokenContract).ownerOf(tokenId);
    }

    function _isValidSigner(
        address signer
    ) internal view virtual returns (bool) {
        return signer == owner();
    }

    function onERC721Received(
        address,
        address from,
        uint256 tokenId,
        bytes memory
    ) public virtual override returns (bytes4) {
        require(msg.sender == CTG_TOKEN_CONTRACT, "Invalid token contract");
        require(
            IERC721(msg.sender).ownerOf(tokenId) == address(this),
            "Invalid token owner"
        );

        // Record original owner of token sent in
        tokenIdToOriginalOwnerMap.set(tokenId, from);

        return this.onERC721Received.selector;
    }

    function enableWithdrawals() public {
        // onlyOwner
        require(_isValidSigner(msg.sender), "Invalid signer");

        // enable Withdrawals
        isWithdrawalEnabled = true;

        // calculate amountPerStaker
        amountPerStaker =
            ((address(this).balance * STAKERS_SHARE_PERCENTAGE) / 100) /
            tokenIdToOriginalOwnerMap.length();

        uint256 amountOfOwner = ((address(this).balance *
            (100 - STAKERS_SHARE_PERCENTAGE)) / 100);

        // payout winner
        address(owner()).call{value: amountOfOwner}("");
    }

    function batchWithdraw() public {
        // Check if withdrawals are enabled
        require(isWithdrawalEnabled, "Withdrawals are not enabled");

        // Transfer all CTG tokens out of the account
        for (uint256 i = 0; i < tokenIdToOriginalOwnerMap.length(); i++) {
            (uint256 tokenId, address originalOwner) = tokenIdToOriginalOwnerMap
                .at(i);

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

        IERC721(CTG_TOKEN_CONTRACT).transferFrom(
            address(this),
            originalOwner,
            tokenId
        );

        // Transfer a portion of the balance to the original owner
        address(originalOwner).call{value: amountPerStaker}("");
    }
}

// you lost the game btw. ~ luc
