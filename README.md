# Evry Loans
Smart contract to manage EVRY Loans

### List of smart contract
- EvryLoans - A main Lending & Borrowing protocol.
- EvToken - The synthetic protocol token (evUSD).
- EvryMix - The primary pegging mechanism for the EvryLoans synthetic tokens.
- YearnControllerMock - The mock up of vault contract.
- VaultAdapter - The vault adapter contract uses to connect with the vault.
- Else - mocks, utils and interface to outsider smart contract.

### Folders & Files structure
- **contracts** - contain all `solidity` files, included mock, interfaces to outside contract and core of lending & borrowing logic
- **deploy** - all the deployment scripts, the script is maintain in single file, but separate environment by folder `config/${env}` (`alpha`, `beta`, `gamma`, `staging` and `prod`)
- **package.json** - contain script for deployment (please check under `scripts` section)
- **hardhat.config.ts** - contain configuration for solidity development,deployment framework. Especially for **private_key**, **api_key** and **networks target**
- **.openzeppelin** - folder that generated after deployment or run unit test - please commit and store it if deploy on staging or production


## How to set up project
- Make sure **node** is installed (preferred v16)
- Preferred IDE is VSCode with extension **solidity (Juan Blanco)**
- Configure solidity workspace version to `0.8.9`
- Install dependency `npm install`
- Update **hardhat.config.js** for
    - private_key - account that have gas fee to deploy
    - verify_api_key - the one get from bsc-scan or eth-scan
- Compile code to byte `npm run compile`
- Then you are ready to develop new feature or deploy

### How to develop
- Run unit test `npm run test`
- Everytime write or update **Sol** file, need to recompile again since unittest script and deploy ignore the change

### How to deploy (after setup)
- Check the script in **package.json** and append with target network from **hardhat.config.js** 
- Example: `npm run deploy:001 alpha` (last parameter will read configuration from `deploy/config/${env}/..` and also link to `hardhat.config.js`)
- Add/Update the resulting contract address into the config file (address.json)
- Check in bscscan.com whether success or fail, and if it is **Upgradeable smart contract**, please verify again for **Proxy Address**

#### Scripts
- deploy:001 - deploy EvToken contract
- deploy:002 - deploy EvryLoans contract
- deploy:003 - deploy EvryMix contract
- deploy:004 - deploy YearnControllerMock contract
- deploy:005 - deploy VaultAdapter contract
- deploy:006 - deploy EvryHyperMock contract (for dev testing)
- deploy:007 - AttackerMock contract (for dev testion)
- deploy:008 - deploy the upgradable of EvryLoans and then call upgradeTo() with new EnvyLoans implementation address
- init:101 - Initialize EvryLoans contract
- init:102 - Initialize EvToken contract
- init:103 - Initialize EvryMix contract
- set:201 - TurnSelfRepayModeOn
- set:202 - ApproveTokenForEvryLoans
- upgrade:301 - deploy new EvryLoans implementation contract (only for owner of proxy admin contract to call)

### How to turn on the selfRepay mode
- Option#1 : run the script `npm run set:201 alpha` (last parameter will read configuration from `deploy/config/${env}/..` and also link to `hardhat.config.js`)
- Option#2 : 
On BSC scan: In `EvryLoans` contract -> call `turnSelfRepayModeOn` function with the parameters of transmuter, reward(treasury), harvestFee, and vaultAdapter.

### How to turn off the selfRepay mode
On BSC scan: In `EvryLoans` contract -> call `turnSelfRepayModeOff` function

## FAQ
### How to solve verify smart contract fail
- Option#1 : Go to bscscan.com and verify that smart contract manually by upload `deployments/*/solcInputs/*.json`
- Option#2 : run verify command line e.g. `npx hardhat verify --network testnet 0xBe940B7bEf0AD71D1BFF57C738C820A90a431709`
