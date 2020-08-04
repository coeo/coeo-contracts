pragma solidity ^0.6.0;

import "./upgrades/UpgradeabilityProxy.sol";
import "./gsn/BaseRelayRecipient.sol";
import "./Semaphore.sol";

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

contract CoeoProxyFactory is BaseRelayRecipient{
  address semaphoreVoting;
  address wallet;

  event NewOrganisation(address indexed creator, address indexed walletContract, address indexed votingContract, address semaphoreContract);
  event NewMember(address indexed member, address indexed votingContract);

  constructor(address _semaphoreVoting, address _wallet) public {
    semaphoreVoting = _semaphoreVoting;
    wallet = _wallet;
  }

  function create(uint232 _epoch, uint256 _period, uint256 _quorum, uint256 _approval, address[] calldata _members) external {
    uint232 firstNullifier = uint232(block.timestamp);
    address msgSender = _msgSender();
    UpgradeabilityProxy semaphoreVotingProxy = new UpgradeabilityProxy(semaphoreVoting, '');
    UpgradeabilityProxy walletProxy = new UpgradeabilityProxy(wallet, abi.encodeWithSelector(
      bytes4(keccak256('initialize(address,address)')),
      address(semaphoreVotingProxy),
      msgSender
    ));
    Semaphore semaphore = new Semaphore(20, firstNullifier, address(semaphoreVotingProxy));
    ISemaphoreVoting(address(semaphoreVotingProxy)).initialize(
      address(semaphore),
      address(walletProxy),
      firstNullifier,
      _epoch,
      _period,
      _quorum,
      _approval,
      _members
    );
    emit NewOrganisation(msgSender, address(walletProxy), address(semaphoreVotingProxy), address(semaphore));
    for (uint8 i = 0; i < _members.length; i++) {
      emit NewMember(_members[i], address(semaphoreVoting));
    }
  }

  function versionRecipient() external view override virtual returns (string memory){
      return "0.0.1+coeo.proxyfactory";
  }
}
