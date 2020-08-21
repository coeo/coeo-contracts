pragma solidity ^0.6.0;

import "./erc725/ERC725X.sol";
import "./erc725/ERC725Y.sol";
import "./erc1271/IERC1271.sol";
import "./upgrades/Initializable.sol";
import "./gsn/BaseRelayRecipient.sol";
import "@openzeppelin/contracts/cryptography/ECDSA.sol";

contract CoeoWallet is BaseRelayRecipient, ERC725X, ERC725Y, IERC1271, Initializable {
  using ECDSA for bytes32;

  bytes4 constant internal MAGICVALUE = 0x20c13b0b;
  bytes4 constant internal INVALID_SIGNATURE = 0xffffffff;

  mapping(address => bool) public approvedSigners;

  event NewSigner(address signer);
  event RemovedSigner(address signer);
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
    NewSigner(_signer);
  }

  function removeSigner(address _signer)
    external
    onlyOwner
  {
    require(_signer != address(0));
    require(approvedSigners[_signer]);
    approvedSigners[_signer] = false;
    RemovedSigner(_signer);
  }

  function isValidSignature(
    bytes memory _message,
    bytes memory _signature
  )
    public
    override
    view
    returns (bytes4 magicValue)
  {
    address signer = _getEthSignedMessageHash(_message).recover(_signature);
    magicValue = approvedSigners[signer] ? MAGICVALUE : INVALID_SIGNATURE;
  }

  // @dev Adds ETH signed message prefix to bytes message and hashes it
  // @param _data Bytes data before adding the prefix
  // @return Prefixed and hashed message
  function _getEthSignedMessageHash(bytes memory _data) internal pure returns (bytes32) {
      return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n", _uint2str(_data.length), _data));
  }

  // @dev Convert uint to string
  // @param _num Uint to be converted
  // @return String equivalent of the uint
  function _uint2str(uint _num) private pure returns (string memory _uintAsString) {
      if (_num == 0) {
          return "0";
      }
      uint i = _num;
      uint j = _num;
      uint len;
      while (j != 0) {
          len++;
          j /= 10;
      }
      bytes memory bstr = new bytes(len);
      uint k = len - 1;
      while (i != 0) {
          bstr[k--] = byte(uint8(48 + i % 10));
          i /= 10;
      }
      return string(bstr);
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
