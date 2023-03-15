pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestErc20 is ERC20 {
    constructor(string memory _name) ERC20(_name, _name) {}

    function mint(address account, uint256 amount) public {
        super._mint(account, amount);
    }

    function decimals() public view override returns (uint8) {
        return 8;
    }
}
