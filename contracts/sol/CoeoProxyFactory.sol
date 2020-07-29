pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./upgrades/UpgradeabilityProxy.sol";
import "./CoeoPaymaster.sol";
import "./gsn/BaseRelayRecipient.sol";

interface ISemaphoreVoting {
  function initialize(
    address _semaphore,
    address _wallet,
    uint232 _firstProposalId,
    uint232 _epoch,
    uint256 _period,
    uint256 _quorum,
    uint256 _approval,
    uint256[] calldata _identityCommitments
  ) external;
}

contract CoeoProxyFactory is BaseRelayRecipient, CoeoPaymaster{
  address semaphore;
  address semaphoreVoting;
  address wallet;

  event NewOrganisation(address indexed creator, address indexed walletContract, address indexed votingContract, address semaphoreContract);

  constructor(address _semaphore, address _semaphoreVoting, address _wallet) public {
    semaphore = _semaphore;
    semaphoreVoting = _semaphoreVoting;
    wallet = _wallet;
    _addGSNRecipient(address(this));
  }

  function create(uint232 _epoch, uint256 _period, uint256 _quorum, uint256 _approval, uint256[] calldata _identityCommitments) external {
    uint232 firstNullifier = uint232(block.timestamp);
    UpgradeabilityProxy semaphoreVotingProxy = new UpgradeabilityProxy(semaphoreVoting, '');
    UpgradeabilityProxy semaphoreProxy = new UpgradeabilityProxy(semaphore, abi.encodeWithSelector(
      bytes4(keccak256('initialize(uint8,uint232,address)')),
      uint8(20),
      firstNullifier,
      address(semaphoreVotingProxy)
    ));
    UpgradeabilityProxy walletProxy = new UpgradeabilityProxy(wallet, abi.encodeWithSelector(
      bytes4(keccak256('initialize(address,address)')),
      address(semaphoreVotingProxy),
      _msgSender()
    ));
    ISemaphoreVoting(address(semaphoreVotingProxy)).initialize(
      address(semaphoreProxy),
      address(walletProxy),
      firstNullifier,
      _epoch,
      _period,
      _quorum,
      _approval,
      _identityCommitments
    );
    _addGSNRecipient(address(semaphoreVotingProxy));
    _addGSNRecipient(address(walletProxy));
    emit NewOrganisation(_msgSender(), address(walletProxy), address(semaphoreVotingProxy), address(semaphoreProxy));
  }

  function _msgSender() internal override(BaseRelayRecipient, Context) view returns (address payable) {
    return BaseRelayRecipient._msgSender();
  }

  function versionRecipient() external view override virtual returns (string memory){
      return "0.0.1+coeo.proxyfactory";
  }
}
