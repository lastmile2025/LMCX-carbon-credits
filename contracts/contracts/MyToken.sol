// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MyToken is ERC1155, Ownable {
    constructor(address initialOwner) ERC1155("") Ownable() {
        _transferOwnership(initialOwner);
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }
}
