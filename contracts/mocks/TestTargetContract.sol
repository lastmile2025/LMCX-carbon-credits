// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title TestTargetContract
 * @dev Simple contract used as a target for governance proposal testing
 */
contract TestTargetContract {
    uint256 public value;
    address public lastCaller;
    bool public flag;

    event ValueSet(uint256 newValue, address caller);
    event FlagSet(bool newFlag);

    function setValue(uint256 _value) external {
        value = _value;
        lastCaller = msg.sender;
        emit ValueSet(_value, msg.sender);
    }

    function setFlag(bool _flag) external {
        flag = _flag;
        emit FlagSet(_flag);
    }

    function incrementValue() external {
        value += 1;
        emit ValueSet(value, msg.sender);
    }

    function reset() external {
        value = 0;
        flag = false;
    }

    // Function that reverts for testing failure cases
    function willRevert() external pure {
        revert("Intentional revert");
    }

    // Function with payable for testing ETH transfers
    function receiveEth() external payable {
        // Just accept ETH
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
