require('module-alias/register')
const MiMC = require('@semaphore-contracts/compiled/MiMC.json')
const Semaphore = require('@semaphore-contracts/compiled/Semaphore.json')
const SemaphoreVoting = require('@semaphore-contracts/compiled/SemaphoreVoting.json')
const CoeoProxyFactory = require('@semaphore-contracts/compiled/CoeoProxyFactory.json')
const CoeoWallet = require('@semaphore-contracts/compiled/CoeoWallet.json')

const etherlime = require('etherlime-lib')

const deploy = async () => {
  const deployer = new etherlime.JSONRPCPrivateKeyDeployer('privatekey', 'url');

  console.log('Deploying MiMC')
  const mimcContract = await deployer.deploy(MiMC, {})

  const libraries = {
      MiMC: mimcContract.contractAddress,
  }

  console.log('Deploying Semaphore Voting Base')
  const semaphoreVotingBaseContract = await deployer.deploy(
      SemaphoreVoting
  )

  console.log('Semaphore Voting Base: ', semaphoreVotingBaseContract.contractAddress)

  console.log('Deploying Wallet Base')
  const walletBaseContract = await deployer.deploy(
      CoeoWallet
  )

  console.log('Wallet Base: ', walletBaseContract.contractAddress)

  console.log('Deploying Coeo Proxy Factory')
  const factoryContract = await deployer.deploy(
      CoeoProxyFactory,
      libraries,
      semaphoreVotingBaseContract.contractAddress,
      walletBaseContract.contractAddress
  )

  console.log('Proxy Factory: ', factoryContract.contractAddress)
}

deploy()
