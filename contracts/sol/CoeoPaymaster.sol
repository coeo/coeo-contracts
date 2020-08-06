pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./gsn/BasePaymaster.sol";
import "./gsn/utils/GSNTypes.sol";

contract CoeoPaymaster is BasePaymaster{
  mapping(address => bool) public recipients;

  event RelayFinished(bool success, bytes context);

  constructor() public {
    _owner = msg.sender;
  }

  function acceptRelayedCall(
      GSNTypes.RelayRequest calldata relayRequest,
      bytes calldata signature,
      bytes calldata approvalData,
      uint256 maxPossibleCharge
  ) external override view
  returns (bytes memory) {
      (relayRequest, approvalData, maxPossibleCharge, signature);
      // **TESTING PURPOSES** ACCEPT ALL RELAYS!!
      //require( recipients[relayRequest.target], "contract not in recipient list");
      return "";
  }

  function preRelayedCall(bytes calldata context) external override
  returns (bytes32) {
      (context);
      return 0;
  }

  function postRelayedCall(
      bytes calldata context,
      bool success,
      bytes32 preRetVal,
      uint256 gasUseWithoutPost,
      GSNTypes.GasData calldata gasData
  ) external override {
    (preRetVal, gasUseWithoutPost, gasData);
    emit RelayFinished(success, context);
  }

  function addGSNRecipient(address _recipient) external onlyOwner {
    _addGSNRecipient(_recipient);
  }

  function _addGSNRecipient(address _recipient) internal {
    recipients[_recipient] = true;
  }

  function versionPaymaster() external view override virtual returns (string memory){
      return "0.0.1+coeo.paymaster";
  }
}
