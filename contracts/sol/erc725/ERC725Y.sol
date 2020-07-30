// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.6.0;

// interfaces
import "./IERC725Y.sol";

// modules
import "../Ownable.sol";
import "@openzeppelin/contracts/introspection/ERC165.sol";

/**
 * @title ERC725 Y data store
 * @dev Contract module which provides the ability to set arbitrary key value sets that can be changed over time.
 * It is intended to standardise certain keys value pairs to allow automated retrievals and interactions
 * from interfaces and other smart contracts.
 *
 * `setData` should only be callable by the owner of the contract set via ERC173.
 *
 *  @author Fabian Vogelsteller <fabian@lukso.network>
 */
contract ERC725Y is ERC165, Ownable, IERC725Y {

    bytes4 internal constant _INTERFACE_ID_ERC725Y = 0x2bd57b73;

    mapping(bytes32 => bytes) internal store;

    /* Public functions */
    constructor() public {
      _registerInterface(_INTERFACE_ID_ERC725Y);
    }

    /**
     * @notice Gets data at a given `key`
     * @param _key the key which value to retrieve
     * @return _value The date stored at the key
     */
    function getData(bytes32 _key)
    public
    view
    override
    virtual
    returns (bytes memory _value)
    {
        return store[_key];
    }

    /**
     * @notice Sets data at a given `key`
     * @param _key the key which value to retrieve
     * @param _value the bytes to set.
     */
    function setData(bytes32 _key, bytes calldata _value)
    external
    override
    virtual
    onlyOwner
    {
        store[_key] = _value;
        emit DataChanged(_key, _value);
    }


    /* Modifiers */

}
