/*
 * Semaphore - Zero-knowledge signaling on Ethereum
 * Copyright (C) 2020 Barry WhiteHat <barrywhitehat@protonmail.com>, Kobi
 * Gurkan <kobigurk@gmail.com> and Koh Wei Jie (contact@kohweijie.com)
 *
 * This file is part of Semaphore.
 *
 * Semaphore is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Semaphore is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with Semaphore.  If not, see <http://www.gnu.org/licenses/>.
 */

 /*
  * This contract modifies SemaphoreClient to support a voting interface
  * With that in mind, the externalNullifier variable has been renamed to
  * proposalId to improve code clarity.
  *
  */

pragma solidity ^0.6.0;

import "./upgrades/Initializable.sol";
import "./gsn/BaseRelayRecipient.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "solidity-bytes-utils/contracts/AssertBytes.sol";

interface ISemaphore {
  function addExternalNullifier(uint232 _externalNullifier) external;
  function deactivateExternalNullifier(uint232 _externalNullifier) external;
  function broadcastSignal(
      bytes calldata _signal,
      uint256[8] calldata _proof,
      uint256 _root,
      uint256 _nullifiersHash,
      uint232 _externalNullifier
  ) external;
  function insertIdentity(uint256 _identityCommitment) external;
  function setPermissioning(bool _newPermission) external;
}
interface ICoeoProxyFactory {
  function registerMember(address _member) external;
}

contract SemaphoreVoting is BaseRelayRecipient, Initializable {
    using SafeMath for uint256;
    //Yes signal
    bytes public constant YEA = 'YEA';
    //No signal
    bytes public constant NAY = 'NAY';

    ISemaphore public semaphore;
    ICoeoProxyFactory public proxyFactory;
    address public wallet;

    struct Vote {
      bool executed;
      uint256 start;
      uint256 yes;
      uint256 no;
      bytes metadata;
      address executionAddress;
      uint256 executionValue;
      bytes executionData;
    }

    // Array of members, identified only by their identity commitments
    uint256[] internal identityCommitments;

    // The minimum amount of time between new proposals
    uint232 public epoch;

    // The total time each vote is open for
    uint256 public period;

    // The minimum percentage of members that must vote for the vote to pass
    uint256 public quorum;

    // The minimum percentage of total votes that must vote yes for the vote to pass
    uint256 public approval;

    mapping (address => bool) private members;

    mapping (address => bool) private identities;

    // A mapping of an proposalId (external nullifier) to Vote struct
    // The proposalId is an external nullifier that members may signal their votes with
    mapping (uint232 => Vote) public votes;

    // A mapping of proposalIndexes with proposalIds
    mapping (uint256 => uint232) public proposals;

    // The proposalId acts as an external nullifier so that only members may make proposals
    uint232 public nextProposalId;

    // The proposalIndex increases by one every time a proposal is created
    uint256 public nextProposalIndex;

    event VoteInitiated(uint232 indexed proposalId, bytes metadata, address executionAddress, uint256 executionValue, bytes executionData);
    event VoteBroadcast(uint232 indexed proposalId, bytes signal);
    event VoteExecuted(uint232 indexed proposalId);
    event VoteNotExecuted(uint232 indexed proposalId);
    event IdentityAdded(uint256 indexed identityCommitment);
    event MemberAdded(address indexed member);



    function initialize(
      address _semaphore,
      address _wallet,
      uint232 _firstProposalId,
      uint232 _epoch,
      uint256 _period,
      uint256 _quorum,
      uint256 _approval,
      address[] calldata _members
    ) external initializer{
        require(_epoch >= 1 hours);
        require(_period >= 1 days);
        require(_quorum < 1e18);
        require(_approval < 1e18);
        proxyFactory = ICoeoProxyFactory(msg.sender); //This contract assume it is being intialize by a factory
        semaphore = ISemaphore(_semaphore);
        wallet = _wallet;
        nextProposalId = _firstProposalId;
        epoch = _epoch;
        period = _period;
        quorum = _quorum;
        approval = _approval;
        for (uint8 i = 0; i < _members.length; i++) {
          members[_members[i]] = true;
          emit MemberAdded(_members[i]);
        }
    }

    //Get identity commitments
    function getIdentityCommitments() public view returns (uint256 [] memory) {
        return identityCommitments;
    }
    //Get identity commitment
    function getIdentityCommitment(uint256 _index) public view returns (uint256) {
        return identityCommitments[_index];
    }
    //Add member
    function addMember(address _member) external authorized {
      require(!members[_member]);
      members[_member] = true;
      emit MemberAdded(_member);
      proxyFactory.registerMember(_member);
    }

    function addIdentity(uint256 _leaf) external {
      address msgSender = _msgSender();
      require(members[msgSender]);
      require(!identities[msgSender]);
      _insertIdentity(_leaf, msgSender);
    }

    function _insertIdentity(uint256 _leaf, address _member) internal {
      semaphore.insertIdentity(_leaf);
      identityCommitments.push(_leaf);
      identities[_member] = true;
      emit IdentityAdded(_leaf);
    }

    //New proposal
    function broadcastProposal(
      bytes calldata _metadata,
      bytes calldata _executionData,
      address _executionAddress,
      uint256 _executionValue,
      uint256[8] calldata _proof,
      uint256 _root,
      uint256 _nullifiersHash,
      uint232 _proposalId
    ) external {
        require((_executionAddress == address(this)) || (_executionAddress == wallet), 'Only whitelisted addresses');
        require(_proposalId == nextProposalId, 'Must match current proposal id');
        require(uint232(block.timestamp) > nextProposalId, 'Cannot make proposal before epoch over');

        // Broadcast signal to ensure only members may create proposals
        semaphore.broadcastSignal(_metadata, _proof, _root, _nullifiersHash, _proposalId);

        // Update proposalId, proposalIndex, and add new nullifier
        {
          proposals[nextProposalIndex] = _proposalId;
          nextProposalIndex += 1;
          nextProposalId = uint232(block.timestamp) + epoch;
          semaphore.addExternalNullifier(nextProposalId);
        }

        // Setup vote data
        {
          votes[_proposalId] = Vote(
            false,
            block.timestamp,
            1,
            0,
            _metadata,
            _executionAddress,
            _executionValue,
            _executionData
          );

          emit VoteInitiated(_proposalId, _metadata, _executionAddress, _executionValue, _executionData);
        }

        // If there is only one member, we can finalize the vote
        if (identityCommitments.length == 1) {
          finalizeVote(_proposalId);
        }
    }

    // Vote
    function broadcastVote(
        bytes memory _vote,
        uint256[8] memory _proof,
        uint256 _root,
        uint256 _nullifiersHash,
        uint232 _proposalId
    ) public {
        Vote storage vote = votes[_proposalId];
        //Overflow shouldn't be a problem here...
        require((vote.start + period) > block.timestamp);
        require(AssertBytes._equal(_vote, YEA) || AssertBytes._equal(_vote, NAY));
        //Given that total membership is much less than 2^256-1, this also should never overflow
        if(AssertBytes._equal(_vote, YEA)){
          vote.yes += 1;
        } else {
          vote.no += 1;
        }

        // broadcast the signal
        semaphore.broadcastSignal(_vote, _proof, _root, _nullifiersHash, _proposalId);
        emit VoteBroadcast(_proposalId, _vote);

        //Finalize vote. If vote hasn't passed, nothing happens
        finalizeVote(_proposalId);
    }

    // End vote
    function finalizeVote(uint232 _proposalId) public {
      Vote storage vote = votes[_proposalId];
      require(!vote.executed, 'Action already axecuted');
      // If majority has voted yes, deactivate nullifier, and move to execute
      if (vote.yes.mul(1e18).div(identityCommitments.length) >= approval) {
        // Vote passed, deactivate nullifier
        semaphore.deactivateExternalNullifier(_proposalId);
      } else {
        if (vote.start.add(period) < block.timestamp) {
            // Time passed, deactivate nullifier
            semaphore.deactivateExternalNullifier(_proposalId);
            uint256 total = vote.yes.add(vote.no);
            // If total is less that quorum, return
            if (total < identityCommitments.length.mul(quorum).div(1e18)) return;
            // If yes votes are less than required, return
            if (vote.yes.mul(1e18).div(total) < approval) return;
        } else {
          return;
        }
      }
      bool success = executeCall(
        vote.executionAddress,
        vote.executionValue,
        vote.executionData,
        gasleft()
      );
      if (success) {
        vote.executed = true;
        emit VoteExecuted(_proposalId);
      } else {
        emit VoteNotExecuted(_proposalId);
      }
    }

    function executeCall(address to, uint256 value, bytes memory data, uint256 txGas)
        internal
        returns (bool success)
    {
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := call(txGas, to, value, add(data, 0x20), mload(data), 0, 0)
        }
    }

    function setPermissioning(bool _newPermission) public authorized{
        semaphore.setPermissioning(_newPermission);
    }

    function recoverFunds(IERC20 _token) external {
      uint256 balance = _token.balanceOf(address(this));
      require(balance > 0);
      _token.transfer(wallet, balance);
    }

    function versionRecipient() external view override virtual returns (string memory){
        return "0.0.1+coeo.voting";
    }

    modifier authorized() {
        require(msg.sender == address(this), "Method can only be called from this contract");
        _;
    }
}
