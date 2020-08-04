pragma solidity ^0.6.0;

import "./upgrades/UpgradeabilityProxy.sol";
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
    address[] calldata _members
  ) external;
}

contract CoeoProxyFactory is BaseRelayRecipient{
  address semaphore;
  address semaphoreVoting;
  address wallet;

  mapping(address => bool) public organisations;

  event NewOrganisation(address indexed creator, address indexed walletContract, address indexed votingContract, address semaphoreContract);
  event NewMember(address indexed member, address indexed votingContract);

  constructor(address _semaphore, address _semaphoreVoting, address _wallet) public {
    semaphore = _semaphore;
    semaphoreVoting = _semaphoreVoting;
    wallet = _wallet;
  }

  function create(uint232 _epoch, uint256 _period, uint256 _quorum, uint256 _approval, address[] calldata _members) external {
    uint232 firstNullifier = uint232(block.timestamp);
    address msgSender = _msgSender();
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
      msgSender
    ));
    ISemaphoreVoting(address(semaphoreVotingProxy)).initialize(
      address(semaphoreProxy),
      address(walletProxy),
      firstNullifier,
      _epoch,
      _period,
      _quorum,
      _approval,
      _members
    );
    // Register voting contract
    organisations[address(semaphoreVotingProxy)] = true;
    emit NewOrganisation(msgSender, address(walletProxy), address(semaphoreVotingProxy), address(semaphoreProxy));
    for (uint8 i = 0; i < _members.length; i++) {
      emit NewMember(_members[i], address(semaphoreVotingProxy));
    }

  }

  function registerMember(address _member) external {
    // Only semaphore voting contracts may call this
    require(organisations[msg.sender]);
    emit NewMember(_member, msg.sender);
  }

  function versionRecipient() external view override virtual returns (string memory){
      return "0.0.1+coeo.proxyfactory";
  }
}
