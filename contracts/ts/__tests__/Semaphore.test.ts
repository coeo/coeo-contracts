require('module-alias/register')
jest.setTimeout(90000)

const MiMC = require('@semaphore-contracts/compiled/MiMC.json')
const Semaphore = require('@semaphore-contracts/compiled/Semaphore.json')
const SemaphoreVoting = require('@semaphore-contracts/compiled/SemaphoreVoting.json')
const CoeoProxyFactory = require('@semaphore-contracts/compiled/CoeoProxyFactory.json')
const CoeoWallet = require('@semaphore-contracts/compiled/CoeoWallet.json')
const hasEvent = require('etherlime/cli-commands/etherlime-test/events.js').hasEvent

import {
    SnarkBigInt,
    genIdentity,
    genIdentityCommitment,
    genExternalNullifier,
    genWitness,
    genCircuit,
    genProof,
    genPublicSignals,
    verifyProof,
    SnarkProvingKey,
    SnarkVerifyingKey,
    parseVerifyingKeyJson,
    genBroadcastSignalParams,
    genSignalHash,
} from 'libsemaphore'
import * as etherlime from 'etherlime-lib'
import * as etherlimeConfig from 'etherlime-config'
import { config } from 'semaphore-config'
import * as path from 'path'
import * as fs from 'fs'
import * as ethers from 'ethers'

const NUM_LEVELS = 20
const YES = 'YEA'
const NO = 'NAY'
const EPOCH = '3600' //1 hour
const PERIOD = '86500' //1 day
const QUORUM = ethers.utils.parseEther('0.25') // 25%
const APPROVAL = ethers.utils.parseEther('0.5').add('1') // 50% + 1

const votingInterface = new ethers.utils.Interface(SemaphoreVoting.abi)
const walletInterface = new ethers.utils.Interface(CoeoWallet.abi)

const provider = new ethers.providers.JsonRpcProvider('http://localhost:8545')
const genTestAccounts = (num: number) => {
  let accounts: ethers.Wallet[] = []
  for (let i=0; i<num; i++) {
    const wallet = new ethers.Wallet(etherlimeConfig.ganacheSetupConfig.accounts[i].secretKey)
    accounts.push(wallet)
  }
  return accounts
}
const accounts = genTestAccounts(10)

let userWallet
let semaphoreContract
let semaphoreVotingContract
let walletContract
let factoryContract
let mimcContract

let originalIdentity
let originalIdentityCommitment

// hex representations of all inserted identity commitments
let insertedIdentityCommitments: string[] = []
const activeEn = genExternalNullifier('1111')
const inactiveEn = genExternalNullifier('2222')

let deployer

describe('Semaphore', () => {
    beforeAll(async () => {
        deployer = new etherlime.EtherlimeGanacheDeployer()

        console.log('Deploying MiMC')
        mimcContract = await deployer.deploy(MiMC, {})

        const libraries = {
            MiMC: mimcContract.contractAddress,
        }

        console.log('Deploying Semaphore Base')
        const semaphoreBaseContract = await deployer.deploy(
            Semaphore,
            libraries
        )

        console.log('Deploying Semaphore Voting Base')
        const semaphoreVotingBaseContract = await deployer.deploy(
            SemaphoreVoting
        )

        console.log('Deploying Wallet Base')
        const walletBaseContract = await deployer.deploy(
            CoeoWallet
        )

        console.log('Semaphore Base: ', semaphoreBaseContract.contractAddress)
        console.log('Semaphore Voting Base: ', semaphoreVotingBaseContract.contractAddress)
        console.log('Wallet Base: ', walletBaseContract.contractAddress)
        console.log('Deploying Coeo Proxy Factory')
        factoryContract = await deployer.deploy(
            CoeoProxyFactory,
            {},
            semaphoreBaseContract.contractAddress,
            semaphoreVotingBaseContract.contractAddress,
            walletBaseContract.contractAddress
        )

        console.log('Proxy Factory: ', factoryContract.contractAddress)

        const members = [accounts[0].address]

        console.log('Create new organization')
        let tx = await factoryContract.create(
            EPOCH,
            PERIOD,
            QUORUM,
            APPROVAL,
            members
        )
        let receipt = await tx.wait()
        console.log('Gas used by create():', receipt.gasUsed.toString())
        const newOrganizationEvent = receipt.events.find(event => event.event === 'NewOrganization')
        const semaphoreAddress = newOrganizationEvent.args.semaphoreContract
        const votingAddress = newOrganizationEvent.args.votingContract
        const walletAddress = newOrganizationEvent.args.walletContract

        console.log('Semaphore address: ', semaphoreAddress)
        console.log('Voting address: ', votingAddress)
        console.log('Wallet address: ', walletAddress)

        semaphoreContract = await etherlime.ContractAt(Semaphore, semaphoreAddress)
        semaphoreVotingContract = await etherlime.ContractAt(SemaphoreVoting, votingAddress)
        walletContract = await etherlime.ContractAt(CoeoWallet, walletAddress)

        console.log('Get identity')
        originalIdentity = genIdentity()
        originalIdentityCommitment = genIdentityCommitment(originalIdentity)
        insertedIdentityCommitments.push('0x' + originalIdentityCommitment.toString(16))

        tx = await semaphoreVotingContract
          .from(accounts[0].address)
          .addIdentity(originalIdentityCommitment.toString())
        receipt = await tx.wait()
        console.log('Gas used by addIdentity():', receipt.gasUsed.toString())

        const walletOwner = await walletContract.owner()
        console.log('Wallet owner: ', walletOwner)

        const signer = provider.getSigner()
        await signer.sendTransaction({
            to: walletContract.contractAddress,
            value: ethers.utils.parseEther('5.0')
        });
        await signer.sendTransaction({
            to: '0xeAe275bE0783173Ee2962080b3745F9b8769B1Ee',
            value: ethers.utils.parseEther('5.0')
        });

        const balance = await provider.getBalance(walletContract.contractAddress)
        console.log('Wallet contract balance: ', balance.toString())
        expect(balance).toEqual(ethers.utils.parseEther('5.0'))
    })

    test('Semaphore belongs to the correct owner', async () => {
        const owner = await semaphoreContract.owner()
        expect(owner).toEqual(semaphoreVotingContract.contractAddress)
    })

    test('check current identity commitments', async () => {
        const numInserted = await semaphoreContract.getNumIdentityCommitments()
        expect(numInserted.toString()).toEqual('1')

        const firstIdentityCommitment = await semaphoreVotingContract.getIdentityCommitment(0)
        expect(firstIdentityCommitment.toHexString()).toEqual(insertedIdentityCommitments[0])
    })

    test('when there is only 1 external nullifier, the first and last external nullifier variables should be the same', async () => {
        expect((await semaphoreContract.numExternalNullifiers()).toNumber()).toEqual(1)
        const firstEn = await semaphoreContract.firstExternalNullifier()
        const lastEn = await semaphoreContract.lastExternalNullifier()
        expect(firstEn.toString()).toEqual(lastEn.toString())
    })

    describe('test voting', () => {
      // Load circuit, proving key, and verifying key
      const circuitPath = path.join(__dirname, '../../../circuits/build/circuit.json')
      const provingKeyPath = path.join(__dirname, '../../../circuits/build/proving_key.bin')
      const verifyingKeyPath = path.join(__dirname, '../../../circuits/build/verification_key.json')

      const cirDef = JSON.parse(fs.readFileSync(circuitPath).toString())
      const provingKey: SnarkProvingKey = fs.readFileSync(provingKeyPath)
      const verifyingKey: SnarkVerifyingKey = parseVerifyingKeyJson(fs.readFileSync(verifyingKeyPath).toString())
      const circuit = genCircuit(cirDef)
      let identity
      let identityCommitment
      let proof
      let publicSignals
      let params
      let currentProposalId
      let leaves

      test('create a proposal for new member', async () => {
        currentProposalId = await semaphoreVotingContract.nextProposalId()
        leaves = await semaphoreVotingContract.getIdentityCommitments()

        const metadata = `Add new member: ${accounts[1].address}`
        const executionData = votingInterface.functions.addMember.encode([accounts[1].address])

        const result = await genWitness(
            metadata,
            circuit,
            originalIdentity,
            leaves,
            NUM_LEVELS,
            currentProposalId,
        )
        proof = await genProof(result.witness, provingKey)
        publicSignals = genPublicSignals(result.witness, circuit)
        params = genBroadcastSignalParams(result, proof, publicSignals)

        const tx = await semaphoreVotingContract.broadcastProposal(
            ethers.utils.toUtf8Bytes(metadata),
            executionData,
            semaphoreVotingContract.contractAddress,
            0,
            params.proof,
            params.root,
            params.nullifiersHash,
            currentProposalId,
            { gasLimit: 1000000 },
        )

        const receipt = await tx.wait()
        expect(receipt.status).toEqual(1)
        console.log('Gas used by broadcastProposal():', receipt.gasUsed.toString())

        expect(hasEvent(receipt, semaphoreVotingContract, 'VoteInitiated')).toBeTruthy()
        expect(hasEvent(receipt, semaphoreVotingContract, 'VoteExecuted')).toBeTruthy()
        expect(hasEvent(receipt, semaphoreVotingContract, 'MemberAdded')).toBeTruthy()
      })

      test('add identity', async () => {
        identity = genIdentity()
        identityCommitment = genIdentityCommitment(identity)
        insertedIdentityCommitments.push('0x' + identityCommitment.toString(16))

        const tx = await semaphoreVotingContract
          .from(accounts[1].address)
          .addIdentity(identityCommitment.toString())
        const receipt = await tx.wait()
        expect(receipt.status).toEqual(1)
        console.log('Gas used by addIdentity():', receipt.gasUsed.toString())

        expect(hasEvent(receipt, semaphoreVotingContract, 'IdentityAdded')).toBeTruthy()

        const numInserted = await semaphoreContract.getNumIdentityCommitments()
        expect(numInserted.toString()).toEqual('2')
      })

      test('attempt to vote on deactivated nullifier', async () => {
        try {
          leaves = await semaphoreVotingContract.getIdentityCommitments()

          const result = await genWitness(
              YES,
              circuit,
              identity,
              leaves,
              NUM_LEVELS,
              currentProposalId,
          )

          proof = await genProof(result.witness, provingKey)
          publicSignals = genPublicSignals(result.witness, circuit)
          params = genBroadcastSignalParams(result, proof, publicSignals)

          const tx = await semaphoreVotingContract.broadcastVote(
              ethers.utils.toUtf8Bytes(YES),
              params.proof,
              params.root,
              params.nullifiersHash,
              params.externalNullifier,
              { gasLimit: 1000000 },
          )
        } catch (e) {
            expect(e.message.endsWith('Semaphore: external nullifier not found')).toBeTruthy()
        }
      })

      test('propose to send funds from wallet', async () => {
        await provider.send('evm_increaseTime', [3601]) //Progress beyond epoch
        currentProposalId = await semaphoreVotingContract.nextProposalId()
        leaves = await semaphoreVotingContract.getIdentityCommitments()

        const metadata = `Send ${1} ETH to ${accounts[9].address}`
        const executionData = walletInterface.functions.execute.encode([0, accounts[9].address, ethers.utils.parseEther('1.0'), '0x0'])

        const result = await genWitness(
            metadata,
            circuit,
            identity,
            leaves,
            NUM_LEVELS,
            currentProposalId,
        )
        proof = await genProof(result.witness, provingKey)
        publicSignals = genPublicSignals(result.witness, circuit)
        params = genBroadcastSignalParams(result, proof, publicSignals)

        const tx = await semaphoreVotingContract.broadcastProposal(
            ethers.utils.toUtf8Bytes(metadata),
            executionData,
            walletContract.contractAddress,
            0,
            params.proof,
            params.root,
            params.nullifiersHash,
            params.externalNullifier,
            { gasLimit: 1000000 },
        )

        const receipt = await tx.wait()
        expect(receipt.status).toEqual(1)
        console.log('Gas used by broadcastProposal():', receipt.gasUsed.toString())

        expect(hasEvent(receipt, semaphoreVotingContract, 'VoteInitiated')).toBeTruthy()
      })

      test('attempt to double vote and fail', async () => {
        try {
          const result = await genWitness(
              YES,
              circuit,
              identity,
              leaves,
              NUM_LEVELS,
              currentProposalId,
          )

          proof = await genProof(result.witness, provingKey)
          publicSignals = genPublicSignals(result.witness, circuit)
          params = genBroadcastSignalParams(result, proof, publicSignals)

          const tx = await semaphoreVotingContract.broadcastVote(
              ethers.utils.toUtf8Bytes(YES),
              params.proof,
              params.root,
              params.nullifiersHash,
              params.externalNullifier,
              { gasLimit: 1000000 },
          )
        } catch (e) {
            expect(e.message.endsWith('Semaphore: nullifier already seen')).toBeTruthy()
        }
      })

      test('vote for and finalize proposal', async () => {
        const userBalanceBefore = await provider.getBalance(accounts[9].address)
        const contractBalanceBefore = await provider.getBalance(walletContract.contractAddress)
        const result = await genWitness(
            YES,
            circuit,
            originalIdentity,
            leaves,
            NUM_LEVELS,
            currentProposalId,
        )

        proof = await genProof(result.witness, provingKey)
        publicSignals = genPublicSignals(result.witness, circuit)
        params = genBroadcastSignalParams(result, proof, publicSignals)

        const tx = await semaphoreVotingContract.broadcastVote(
            ethers.utils.toUtf8Bytes(YES),
            params.proof,
            params.root,
            params.nullifiersHash,
            params.externalNullifier,
            { gasLimit: 1000000 },
        )

        const receipt = await tx.wait()
        expect(receipt.status).toEqual(1)
        console.log('Gas used by broadcastVote():', receipt.gasUsed.toString())

        expect(hasEvent(receipt, semaphoreVotingContract, 'VoteBroadcast')).toBeTruthy()
        expect(hasEvent(receipt, semaphoreVotingContract, 'VoteExecuted')).toBeTruthy()

        const userBalanceAfter = await provider.getBalance(accounts[9].address)
        const contractBalanceAfter = await provider.getBalance(walletContract.contractAddress)
        expect(userBalanceAfter.sub(userBalanceBefore)).toEqual(ethers.utils.parseEther('1.0'))
        expect(contractBalanceBefore.sub(contractBalanceAfter)).toEqual(ethers.utils.parseEther('1.0'))
      })
    })

    /*
    test('insert an identity commitment', async () => {
        const identity = genIdentity()
        const identityCommitment: SnarkBigInt = genIdentityCommitment(identity)

        const tx = await semaphoreVotingContract.insertIdentityAsClient(
            identityCommitment.toString()
        )
        const receipt = await tx.wait()
        expect(receipt.status).toEqual(1)

        const numInserted = await semaphoreContract.getNumIdentityCommitments()
        expect(numInserted.toString()).toEqual('1')

        console.log('Gas used by insertIdentityAsClient():', receipt.gasUsed.toString())

        insertedIdentityCommitments.push('0x' + identityCommitment.toString(16))
        expect(hasEvent(receipt, semaphoreContract, 'LeafInsertion')).toBeTruthy()
    })

    describe('identity insertions', () => {
        test('should be stored in the contract and retrievable via leaves()', async () => {
            expect.assertions(insertedIdentityCommitments.length + 1)

            const leaves = await semaphoreVotingContract.getIdentityCommitments()
            expect(leaves.length).toEqual(insertedIdentityCommitments.length)

            const leavesHex = leaves.map(BigInt)

            for (let i = 0; i < insertedIdentityCommitments.length; i++) {
                const containsLeaf = leavesHex.indexOf(BigInt(insertedIdentityCommitments[i])) > -1
                expect(containsLeaf).toBeTruthy()
            }
        })

        test('should be stored in the contract and retrievable by enumerating leaf()', async () => {
            expect.assertions(insertedIdentityCommitments.length)

            // Assumes that insertedIdentityCommitments has the same number of
            // elements as the number of leaves
            const idCommsBigint = insertedIdentityCommitments.map(BigInt)
            for (let i = 0; i < insertedIdentityCommitments.length; i++) {
                const leaf = await semaphoreVotingContract.getIdentityCommitment(i)
                const leafHex = BigInt(leaf.toHexString())
                expect(idCommsBigint.indexOf(leafHex) > -1).toBeTruthy()
            }
        })

        test('inserting an identity commitment of the nothing-up-my-sleeve value should fail', async () => {
            expect.assertions(1)
            const nothingUpMySleeve =
                BigInt(ethers.utils.solidityKeccak256(['bytes'], [ethers.utils.toUtf8Bytes('Semaphore')]))
                %
                BigInt('21888242871839275222246405745257275088548364400416034343698204186575808495617')

            try {
                await semaphoreVotingContract.insertIdentityAsClient(nothingUpMySleeve.toString())
            } catch (e) {
                expect(e.message.endsWith('Semaphore: identity commitment cannot be the nothing-up-my-sleeve-value')).toBeTruthy()
            }
        })

    })

    describe('external nullifiers', () => {

        test('when there is only 1 external nullifier, the first and last external nullifier variables should be the same', async () => {
            expect((await semaphoreContract.numExternalNullifiers()).toNumber()).toEqual(1)
            const firstEn = await semaphoreContract.firstExternalNullifier()
            const lastEn = await semaphoreContract.lastExternalNullifier()
            expect(firstEn.toString()).toEqual(lastEn.toString())
        })

        test('getNextExternalNullifier should throw if there is only 1 external nullifier', async () => {
            expect((await semaphoreContract.numExternalNullifiers()).toNumber()).toEqual(1)
            const firstEn = await semaphoreContract.firstExternalNullifier()
            try {
                await semaphoreContract.getNextExternalNullifier(firstEn)
            } catch (e) {
                expect(e.message.endsWith('Semaphore: no external nullifier exists after the specified one')).toBeTruthy()
            }
        })

        test('should be able to add an external nullifier', async () => {
            expect.assertions(4)
            const tx = await semaphoreVotingContract.addExternalNullifier(
                activeEn,
                { gasLimit: 200000 },
            )
            const receipt = await tx.wait()

            expect(receipt.status).toEqual(1)
            expect(hasEvent(receipt, semaphoreContract, 'ExternalNullifierAdd')).toBeTruthy()

            // Check if isExternalNullifierActive works
            const isActive = await semaphoreContract.isExternalNullifierActive(activeEn)
            expect(isActive).toBeTruthy()

            // Check if numExternalNullifiers() returns the correct value
            expect((await semaphoreContract.numExternalNullifiers()).toNumber()).toEqual(2)
        })

        test('getNextExternalNullifier should throw if there is no such external nullifier', async () => {
            try {
                await semaphoreContract.getNextExternalNullifier('876876876876')
            } catch (e) {
                expect(e.message.endsWith('Semaphore: no such external nullifier')).toBeTruthy()
            }
        })

        test('should be able to deactivate an external nullifier', async () => {
            await (await semaphoreVotingContract.addExternalNullifier(
                inactiveEn,
                { gasLimit: 200000 },
            )).wait()
            const tx = await semaphoreVotingContract.deactivateExternalNullifier(
                inactiveEn,
                { gasLimit: 100000 },
            )
            const receipt = await tx.wait()
            expect(receipt.status).toEqual(1)

            expect(await semaphoreContract.isExternalNullifierActive(inactiveEn)).toBeFalsy()
        })

        test('reactivating a deactivated external nullifier and then deactivating it should work', async () => {
            expect.assertions(3)

            // inactiveEn should be inactive
            expect(await semaphoreContract.isExternalNullifierActive(inactiveEn)).toBeFalsy()

            // reactivate inactiveEn
            let tx = await semaphoreVotingContract.reactivateExternalNullifier(
                inactiveEn,
                { gasLimit: 100000 },
            )
            await tx.wait()

            expect(await semaphoreContract.isExternalNullifierActive(inactiveEn)).toBeTruthy()

            tx = await semaphoreVotingContract.deactivateExternalNullifier(
                inactiveEn,
                { gasLimit: 100000 },
            )
            await tx.wait()

            expect(await semaphoreContract.isExternalNullifierActive(inactiveEn)).toBeFalsy()
        })

        test('enumerating external nullifiers should work', async () => {
            const firstEn = await semaphoreContract.firstExternalNullifier()
            const lastEn = await semaphoreContract.lastExternalNullifier()

            const externalNullifiers: BigInt[] = [ firstEn ]
            let currentEn = firstEn

            while (currentEn.toString() !== lastEn.toString()) {
                currentEn = await semaphoreContract.getNextExternalNullifier(currentEn)
                externalNullifiers.push(currentEn)
            }

            expect(externalNullifiers).toHaveLength(3)
            expect(BigInt(externalNullifiers[0].toString())).toEqual(BigInt(firstEn.toString()))
            expect(BigInt(externalNullifiers[1].toString())).toEqual(BigInt(activeEn.toString()))
            expect(BigInt(externalNullifiers[2].toString())).toEqual(BigInt(inactiveEn.toString()))
        })
    })

    describe('signal broadcasts', () => {
        // Load circuit, proving key, and verifying key
        const circuitPath = path.join(__dirname, '../../../circuits/build/circuit.json')
        const provingKeyPath = path.join(__dirname, '../../../circuits/build/proving_key.bin')
        const verifyingKeyPath = path.join(__dirname, '../../../circuits/build/verification_key.json')

        const cirDef = JSON.parse(fs.readFileSync(circuitPath).toString())
        const provingKey: SnarkProvingKey = fs.readFileSync(provingKeyPath)
        const verifyingKey: SnarkVerifyingKey = parseVerifyingKeyJson(fs.readFileSync(verifyingKeyPath).toString())
        const circuit = genCircuit(cirDef)
        let identity
        let identityCommitment
        let proof
        let publicSignals
        let params

        beforeAll(async () => {
            identity = genIdentity()
            identityCommitment = genIdentityCommitment(identity)

            await (await semaphoreVotingContract.insertIdentityAsClient(identityCommitment.toString())).wait()

            const leaves = await semaphoreVotingContract.getIdentityCommitments()

            const result = await genWitness(
                SIGNAL,
                circuit,
                identity,
                leaves,
                NUM_LEVELS,
                FIRST_EXTERNAL_NULLIFIER,
            )

            proof = await genProof(result.witness, provingKey)
            publicSignals = genPublicSignals(result.witness, circuit)
            params = genBroadcastSignalParams(result, proof, publicSignals)
        })

        test('the proof should be valid', async () => {
            expect.assertions(1)
            const isValid = verifyProof(verifyingKey, proof, publicSignals)
            expect(isValid).toBeTruthy()
        })

        test('the pre-broadcast check should pass', async () => {
            expect.assertions(1)

            const signal = ethers.utils.toUtf8Bytes(SIGNAL)
            const check = await semaphoreContract.preBroadcastCheck(
                signal,
                params.proof,
                params.root,
                params.nullifiersHash,
                genSignalHash(signal).toString(),
                FIRST_EXTERNAL_NULLIFIER,
            )
            expect(check).toBeTruthy()
        })

        test('the pre-broadcast check with an invalid signal should fail', async () => {
            expect.assertions(1)

            const signal = ethers.utils.toUtf8Bytes(SIGNAL)
            const check = await semaphoreContract.preBroadcastCheck(
                '0x0',
                params.proof,
                params.root,
                params.nullifiersHash,
                genSignalHash(signal).toString(),
                FIRST_EXTERNAL_NULLIFIER,
            )
            expect(check).toBeFalsy()
        })

        test('broadcastSignal with an input element above the scalar field should fail', async () => {
            expect.assertions(1)
            const size = BigInt('21888242871839275222246405745257275088548364400416034343698204186575808495617')
            const oversizedInput = (BigInt(params.nullifiersHash) + size).toString()
            try {
                await semaphoreVotingContract.broadcastSignal(
                    ethers.utils.toUtf8Bytes(SIGNAL),
                    params.proof,
                    params.root,
                    oversizedInput,
                    FIRST_EXTERNAL_NULLIFIER,
                )
            } catch (e) {
                expect(e.message.endsWith('Semaphore: the nullifiers hash must be lt the snark scalar field')).toBeTruthy()
            }
        })

        test('broadcastSignal with an invalid proof_data should fail', async () => {
            expect.assertions(1)
            try {
                await semaphoreVotingContract.broadcastSignal(
                    ethers.utils.toUtf8Bytes(SIGNAL),
                    [
                        "21888242871839275222246405745257275088548364400416034343698204186575808495617",
                        "7",
                        "7",
                        "7",
                        "7",
                        "7",
                        "7",
                        "7",
                    ],
                    params.root,
                    params.nullifiersHash,
                    FIRST_EXTERNAL_NULLIFIER,
                )
            } catch (e) {
                expect(e.message.endsWith('Semaphore: invalid field element(s) in proof')).toBeTruthy()
            }
        })

        test('broadcastSignal with an unseen root should fail', async () => {
            expect.assertions(1)
            try {
                await semaphoreVotingContract.broadcastSignal(
                    ethers.utils.toUtf8Bytes(SIGNAL),
                    params.proof,
                    params.nullifiersHash, // note that this is delibrately swapped
                    params.root,
                    FIRST_EXTERNAL_NULLIFIER,
                )
            } catch (e) {
                expect(e.message.endsWith('Semaphore: root not seen')).toBeTruthy()
            }
        })

        test('broadcastSignal by an unpermissioned user should fail', async () => {
            expect.assertions(1)
            try {
                await semaphoreContract.broadcastSignal(
                    ethers.utils.toUtf8Bytes(SIGNAL),
                    params.proof,
                    params.root,
                    params.nullifiersHash,
                    FIRST_EXTERNAL_NULLIFIER,
                )
            } catch (e) {
                expect(e.message.endsWith('Semaphore: broadcast permission denied')).toBeTruthy()
            }
        })

        test('broadcastSignal to active external nullifier with an account with the right permissions should work', async () => {
            expect.assertions(3)
            const tx = await semaphoreVotingContract.broadcastSignal(
                ethers.utils.toUtf8Bytes(SIGNAL),
                params.proof,
                params.root,
                params.nullifiersHash,
                FIRST_EXTERNAL_NULLIFIER,
                //params.externalNullifier,
                { gasLimit: 1000000 },
            )
            const receipt = await tx.wait()
            expect(receipt.status).toEqual(1)
            console.log('Gas used by broadcastSignal():', receipt.gasUsed.toString())

            const index = (await semaphoreVotingContract.nextSignalIndex()) - 1
            const signal = await semaphoreVotingContract.signalIndexToSignal(index.toString())

            expect(ethers.utils.toUtf8String(signal)).toEqual(SIGNAL)

            expect(hasEvent(receipt, semaphoreVotingContract, 'SignalBroadcastByClient')).toBeTruthy()
        })

        test('double-signalling to the same external nullifier should fail', async () => {
            expect.assertions(1)
            const leaves = await semaphoreVotingContract.getIdentityCommitments()
            const newSignal = 'newSignal0'

            const result = await genWitness(
                newSignal,
                circuit,
                identity,
                leaves,
                NUM_LEVELS,
                FIRST_EXTERNAL_NULLIFIER,
            )

            proof = await genProof(result.witness, provingKey)
            publicSignals = genPublicSignals(result.witness, circuit)
            params = genBroadcastSignalParams(result, proof, publicSignals)
            try {
                const tx = await semaphoreVotingContract.broadcastSignal(
                    ethers.utils.toUtf8Bytes(newSignal),
                    params.proof,
                    params.root,
                    params.nullifiersHash,
                    FIRST_EXTERNAL_NULLIFIER,
                )
            } catch (e) {
                expect(e.message.endsWith('Semaphore: nullifier already seen')).toBeTruthy()
            }
        })

        test('signalling to a different external nullifier should work', async () => {
            expect.assertions(1)
            const leaves = await semaphoreVotingContract.getIdentityCommitments()
            const newSignal = 'newSignal1'

            const result = await genWitness(
                newSignal,
                circuit,
                identity,
                leaves,
                NUM_LEVELS,
                activeEn,
            )

            proof = await genProof(result.witness, provingKey)
            publicSignals = genPublicSignals(result.witness, circuit)
            params = genBroadcastSignalParams(result, proof, publicSignals)
            const tx = await semaphoreVotingContract.broadcastSignal(
                ethers.utils.toUtf8Bytes(newSignal),
                params.proof,
                params.root,
                params.nullifiersHash,
                activeEn,
                { gasLimit: 1000000 },
            )
            const receipt = await tx.wait()
            expect(receipt.status).toEqual(1)
        })

        test('broadcastSignal to a deactivated external nullifier should fail', async () => {
            expect.assertions(2)
            expect(await semaphoreContract.isExternalNullifierActive(inactiveEn)).toBeFalsy()

            identity = genIdentity()
            identityCommitment = genIdentityCommitment(identity)

            await (await semaphoreVotingContract.insertIdentityAsClient(identityCommitment.toString())).wait()

            const leaves = await semaphoreVotingContract.getIdentityCommitments()

            const result = await genWitness(
                SIGNAL,
                circuit,
                identity,
                leaves,
                NUM_LEVELS,
                inactiveEn,
            )

            proof = await genProof(result.witness, provingKey)
            publicSignals = genPublicSignals(result.witness, circuit)
            params = genBroadcastSignalParams(result, proof, publicSignals)

            try {
                const tx = await semaphoreVotingContract.broadcastSignal(
                    ethers.utils.toUtf8Bytes(SIGNAL),
                    params.proof,
                    params.root,
                    params.nullifiersHash,
                    inactiveEn,
                )
            } catch (e) {
                expect(e.message.endsWith('Semaphore: external nullifier not found')).toBeTruthy()
            }
        })

        test('setPermissioning(false) should allow anyone to broadcast a signal', async () => {
            expect.assertions(2)
            const leaves = await semaphoreVotingContract.getIdentityCommitments()
            const newSignal = 'newSignal2'

            const result = await genWitness(
                newSignal,
                circuit,
                identity,
                leaves,
                NUM_LEVELS,
                activeEn,
            )

            proof = await genProof(result.witness, provingKey)
            publicSignals = genPublicSignals(result.witness, circuit)
            params = genBroadcastSignalParams(result, proof, publicSignals)
            try {
                await semaphoreContract.broadcastSignal(
                    ethers.utils.toUtf8Bytes(newSignal),
                    params.proof,
                    params.root,
                    params.nullifiersHash,
                    activeEn,
                    { gasLimit: 1000000 },
                )
            } catch (e) {
                expect(e.message.endsWith('Semaphore: broadcast permission denied')).toBeTruthy()
            }

            await (await semaphoreVotingContract.setPermissioning(false, { gasLimit: 100000 })).wait()

            const tx = await semaphoreVotingContract.broadcastSignal(
                ethers.utils.toUtf8Bytes(newSignal),
                params.proof,
                params.root,
                params.nullifiersHash,
                activeEn,
                { gasLimit: 1000000 },
            )
            const receipt = await tx.wait()
            expect(receipt.status).toEqual(1)
        })

    })
    */
})
