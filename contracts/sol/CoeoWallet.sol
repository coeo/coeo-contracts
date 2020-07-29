pragma solidity ^0.6.0;

import "./erc725/ERC725X.sol";
import "./erc725/ERC725Y.sol";
import "./erc1271/IERC1271.sol";
import "./upgrades/Initializable.sol";
import "./gsn/BaseRelayRecipient.sol";
import "@openzeppelin/contracts/cryptography/ECDSA.sol";

contract CoeoWallet is BaseRelayRecipient, ERC725X, ERC725Y, IERC1271, Initializable {
  // bytes4(keccak256("isValidSignature(bytes32,bytes)")
  bytes4 constant internal MAGICVALUE = 0x1626ba7e;

  mapping(address => bool) public approvedSigners;

  event NewSigner(address signer);
  event ReceivedPayment(address sender, uint256 value);

  function initialize(address _newOwner, address _signer) public initializer {
    require(_signer != address(0));
    approvedSigners[_signer] = true;
    _owner = _newOwner;
    NewSigner(_signer);
    OwnershipTransferred(address(0), _owner);
  }

  function addSigner(address _signer)
    external
    onlyOwner
  {
    require(_signer != address(0));
    require(!approvedSigners[_signer]);
    approvedSigners[_signer] = true;
  }

  function removeSigner(address _signer)
    external
    onlyOwner
  {
    require(_signer != address(0));
    require(approvedSigners[_signer]);
    approvedSigners[_signer] = false;
  }

  /**
   * @dev Should return whether the signature provided is valid for the provided data
   * @param _data Arbitrary length data signed on the behalf of address(this)
   * @param _signature Signature byte array associated with _data
   *
   * MUST return the bytes4 magic value 0x20c13b0b when function passes.
   * MUST NOT modify state (using STATICCALL for solc < 0.5, view modifier for solc > 0.5)
   * MUST allow external calls
   */
  function isValidSignature(
   bytes32 _data,
   bytes memory _signature)
   public
   override
   view
   returns (bytes4 magicValue)
  {
    bytes32 signedData = ECDSA.toEthSignedMessageHash(_data);
    address recovered = ECDSA.recover(signedData, _signature);
    if (approvedSigners[recovered]) {
     return MAGICVALUE;
    }
  }

  function _msgSender() internal override(BaseRelayRecipient, Context) view returns (address payable) {
    return BaseRelayRecipient._msgSender();
  }

  function versionRecipient() external view override virtual returns (string memory){
      return "0.0.1+coeo.wallet";
  }

  receive () external payable {
    emit ReceivedPayment(_msgSender(), msg.value);
  }
}
