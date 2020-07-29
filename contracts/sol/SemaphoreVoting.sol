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
  * voteId to improve code clarity.
  *
  */

pragma solidity ^0.6.0;

import "./upgrades/Initializable.sol";
import "./gsn/BaseRelayRecipient.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@gnosis.pm/safe-contracts/contracts/base/Executor.sol";
import "@gnosis.pm/safe-contracts/contracts/common/SelfAuthorized.sol";
import "solidity-bytes-utils/contracts/AssertBytes.sol";
import { Semaphore } from './Semaphore.sol';

contract SemaphoreVoting is BaseRelayRecipient, Executor, Initializable, SelfAuthorized{
    using SafeMath for uint256;
    //Yes signal
    bytes public constant YEA = 'YEA';
    //No signal
    bytes public constant NAY = 'NAY';
    //New proposal signal
    bytes public constant NEW = 'NEW';

    Semaphore public semaphore;
    address public wallet;

    struct Vote {
      uint256 start;
      uint256 yes;
      uint256 no;
      bool executed;
      string metadata;
      address executionAddress;
      uint256 executionValue;
      bytes executionData;
    }

    // Array of members, identified only by their identity commitments
    uint256[] public identityCommitments;

    // The minimum amount of time between new proposals
    uint232 public epoch;

    // The total time each vote is open for
    uint256 public period;

    // The minimum percentage of members that must vote for the vote to pass
    uint256 public quorum;

    // The minimum percentage of total votes that must vote yes for the vote to pass
    uint256 public approval;

    // A mapping of an voteId (external nullifier) to Vote struct
    // The voteId is an external nullifier that members may signal their votes with
    mapping (uint232 => Vote) internal votes;

    mapping (uint232 => uint232) internal proposals;

    // The proposalId acts as an external nullifier so that only members may make proposals
    // Every new proposal deactivates the current proposalId and activates the next id
    uint232 public nextProposalId;

    event VoteInitiated(uint232 indexed voteId, string metadata, address executionAddress, uint256 executionValue, bytes executionData);
    event VoteBroadcast(uint232 indexed voteId, bytes signal);
    event ProposalBroadcast(uint232 indexed proposalId);

    function initialize(
      address _semaphore,
      address _wallet,
      uint232 _firstProposalId,
      uint232 _epoch,
      uint256 _period,
      uint256 _quorum,
      uint256 _approval,
      uint256[] calldata _identityCommitments
    ) external initializer{
        /*
        require(_epoch >= 1 hours);
        require(_period >= 1 days);
        require(_quorum < 1e18);
        require(_approval < 1e18);
        */
        semaphore = Semaphore(_semaphore);
        wallet = _wallet;
        nextProposalId = _firstProposalId;
        epoch = _epoch;
        period = _period;
        quorum = _quorum;
        approval = _approval;
        for(uint8 i = 0; i < _identityCommitments.length; i++) {
          _insertIdentity(_identityCommitments[i]);
        }
    }

    //Get members
    function getIdentityCommitments() public view returns (uint256 [] memory) {
        return identityCommitments;
    }
    //Get member
    function getIdentityCommitment(uint256 _index) public view returns (uint256) {
        return identityCommitments[_index];
    }
    //Add member
    function addMember(uint256 _leaf) external authorized {
      _insertIdentity(_leaf);
    }

    function _insertIdentity(uint256 _leaf) internal {
      semaphore.insertIdentity(_leaf);
      identityCommitments.push(_leaf);
    }

    //New proposal
    function newProposal(
      bytes calldata _data,
      uint256[8] calldata _proof,
      uint256 _root,
      uint256 _nullifiersHash,
      uint232 _proposalId,
      bytes calldata _executionData,
      address _executionAddress,
      uint256 _executionValue,
      string calldata _metadata
    ) external {
        require((_executionAddress == address(this)) || (_executionAddress == wallet), 'Only whitelisted addresses');
        require(AssertBytes._equal(_data, NEW), 'Must match signal');
        require(_proposalId == nextProposalId, 'Must match current proposal id');
        require(uint232(block.timestamp) > nextProposalId, 'Cannot make proposal before epoch over');

        //Broadcast signal to ensure only members may create proposals
        semaphore.broadcastSignal(_data, _proof, _root, _nullifiersHash, _proposalId);

        //Deactivate proposalId so that only one member may emit a signal on it
        semaphore.deactivateExternalNullifier(_proposalId);

        //Update proposalId and add new nullifier
        nextProposalId = uint232(block.timestamp) + epoch;
        semaphore.addExternalNullifier(nextProposalId);

        //Generate external nullifier for the new vote
        uint232 voteId = uint232(block.timestamp);
        semaphore.addExternalNullifier(voteId);

        Vote storage vote = votes[voteId];
        vote.start = block.timestamp;
        vote.metadata = _metadata;
        vote.executionData = _executionData;
        vote.executionAddress = _executionAddress;
        vote.executionValue = _executionValue;

        emit ProposalBroadcast(_proposalId);
        emit VoteInitiated(voteId, _metadata, _executionAddress, _executionValue, _executionData);
    }
    //End vote
    function finalizeProposal(uint232 _voteId) public {
        if (votePassedOutright(_voteId) || votePassedWithTimeout(_voteId)) {
          Vote storage vote = votes[_voteId];
          executeCall(
            vote.executionAddress,
            vote.executionValue,
            vote.executionData,
            gasleft()
          );
          semaphore.deactivateExternalNullifier(_voteId);
        }
    }

    //Vote
    function broadcastVote(
        bytes memory _vote,
        uint256[8] memory _proof,
        uint256 _root,
        uint256 _nullifiersHash,
        uint232 _voteId
    ) public {
        Vote storage vote = votes[_voteId];
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
        semaphore.broadcastSignal(_vote, _proof, _root, _nullifiersHash, _voteId);
        emit VoteBroadcast(_voteId, _vote);

        //Finalize proposal. If vote hasn't passed, nothing happens
        finalizeProposal(_voteId);
    }

    function setPermissioning(bool _newPermission) public authorized{
        semaphore.setPermissioning(_newPermission);
    }

    function votePassedOutright(uint232 _voteId) public view returns (bool){
        Vote storage vote = votes[_voteId];
        //Checks if the vote has reached necessary approval for all possible voters
        if (vote.yes.mul(1e18).div(identityCommitments.length) >= approval) {
          return true;
        }
        return false;
    }

    function votePassedWithTimeout(uint232 _voteId) public view returns (bool){
        Vote storage vote = votes[_voteId];
        uint256 total = vote.yes.add(vote.no);
        if (block.timestamp > vote.start.add(period)) {
          if (total >= identityCommitments.length.mul(quorum).div(1e18)) {
            if (vote.yes.mul(1e18).div(total) >= approval) {
              return true;
            }
          }
        }
        return false;
    }

    function recoverFunds(IERC20 _token) external {
      uint256 balance = _token.balanceOf(address(this));
      require(balance > 0);
      _token.transfer(wallet, balance);
    }

    function versionRecipient() external view override virtual returns (string memory){
        return "0.0.1+coeo.voting";
    }
}
