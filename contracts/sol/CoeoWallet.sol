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

  function isValidSignature(
    bytes memory _message,
    bytes memory _signature
  )
    public
    override
    view
    returns (bytes4 magicValue)
  {
    bytes32 messageHash = keccak256(abi.encodePacked(_message));
    address signer = messageHash.recover(_signature);
    if (approvedSigners[signer]) {
      return MAGICVALUE;
    } else {
      return INVALID_SIGNATURE;
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
