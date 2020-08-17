pragma solidity ^0.6.0;

import "./upgrades/UpgradeabilityProxy.sol";
import "./gsn/BaseRelayRecipient.sol";
import "./Ownable.sol";

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

contract CoeoProxyFactory is Ownable, BaseRelayRecipient{
  address semaphore;
  address semaphoreVoting;
  address wallet;

  event NewOrganization(address indexed creator, address indexed walletContract, address indexed votingContract, address semaphoreContract);
  event NewMember(address indexed member, address indexed walletContract);

  constructor(address _semaphore, address _semaphoreVoting, address _wallet) public {
    semaphore = _semaphore;
    semaphoreVoting = _semaphoreVoting;
    wallet = _wallet;
    _owner = msg.sender;
    emit OwnershipTransferred(address(0), _owner);
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
    emit NewOrganization(msgSender, address(walletProxy), address(semaphoreVotingProxy), address(semaphoreProxy));
    for (uint8 i = 0; i < _members.length; i++) {
      emit NewMember(_members[i], address(walletProxy));
    }
  }

  function updateVotingContract(address _newAddress) external onlyOwner {
    require(_newAddress != address(0));
    semaphoreVoting = _newAddress;
  }

  function updateWalletContract(address _newAddress) external onlyOwner {
    require(_newAddress != address(0));
    wallet = _newAddress;
  }

  function _msgSender() internal override(BaseRelayRecipient, Context) view returns (address payable) {
    return BaseRelayRecipient._msgSender();
  }

  function versionRecipient() external view override virtual returns (string memory){
      return "0.0.1+coeo.proxyfactory";
  }
}
