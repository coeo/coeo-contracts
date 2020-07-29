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

pragma solidity ^0.6.0;

import { IncrementalMerkleTree } from './IncrementalMerkleTree.sol';

contract IncrementalMerkleTreeClient is IncrementalMerkleTree{
    constructor(uint8 _treeLevels, uint256 _zeroValue)
        public {
          //Setup IncrementalMerkleTree
          // Limit the Merkle tree to MAX_DEPTH levels
          require(
              _treeLevels > 0 && _treeLevels <= MAX_DEPTH,
              "IncrementalMerkleTree: _treeLevels must be between 0 and 33"
          );

          /*
             To initialise the Merkle tree, we need to calculate the Merkle root
             assuming that each leaf is the zero value.

              H(H(a,b), H(c,d))
               /             \
              H(a,b)        H(c,d)
               /   \        /    \
              a     b      c      d

             `zeros` and `filledSubtrees` will come in handy later when we do
             inserts or updates. e.g when we insert a value in index 1, we will
             need to look up values from those arrays to recalculate the Merkle
             root.
           */
          treeLevels = _treeLevels;

          zeros[0] = _zeroValue;

          uint256 currentZero = _zeroValue;
          for (uint8 i = 1; i < _treeLevels; i++) {
              uint256 hashed = hashLeftRight(currentZero, currentZero);
              zeros[i] = hashed;
              filledSubtrees[i] = hashed;
              currentZero = hashed;
          }

          root = hashLeftRight(currentZero, currentZero);
    }

    function insertLeafAsClient(uint256 _leaf) public {
        insertLeaf(_leaf);
    }
}
