import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract DummyToken is ERC721 {
    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function mint(address to, uint256 tokenId) public {
        _mint(to, tokenId);
    }
}
