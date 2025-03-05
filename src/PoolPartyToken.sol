// SPDX-License-Identifier: MIT
pragma solidity >=0.6.2 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title PoolPartyToken
 * @dev ERC20 token with minting capabilities controlled by hookers
 */
contract PoolPartyToken is ERC20, ERC20Burnable {
    // Mapping to track addresses with hooker privileges
    mapping(address => bool) public hookers;
    
    /**
     * @dev Modifier to restrict function access to hookers only
     */
    modifier onlyHookers() {
        require(hookers[msg.sender], "PoolPartyToken: caller is not a hooker");
        _;
    }
    
    /**
     * @dev Initializes the PoolPartyToken with a name and symbol
     * @param initialHooker The address that will have initial hooker privileges
     */
    constructor(address initialHooker) 
        ERC20("PoolParty Token", "PP")
    {
        // Set the initial hooker
        hookers[initialHooker] = true;
    }

    function addHooker(address newHooker) public onlyHookers {
        hookers[newHooker] = true;
    }

    function removeHooker(address oldHooker) public onlyHookers {
        hookers[oldHooker] = false;
    }

    /**
     * @dev Mints new tokens
     * @param to The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) public onlyHookers {
        _mint(to, amount);
    }
    
    /**
     * @dev Burns tokens from a specified account
     * @param from The address to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burn(address from, uint256 amount) public onlyHookers {
        _burn(from, amount);
    }
}
