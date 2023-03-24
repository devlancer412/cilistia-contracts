export interface ContractsConfigType {
  uniswapRouter: string;
  nonfungiblePositionManager: string;
  USDT?: string;
  USDC?: string;
  priceFeeds: {
    nativeToken: string;
    [name: string]: string;
  };
}

const arbitrumContracts: ContractsConfigType = {
  uniswapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
  nonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
  USDT: "0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9",
  USDC: "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8",
  priceFeeds: {
    nativeToken: "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",
  },
};
const goerliContracts: ContractsConfigType = {
  uniswapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
  nonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
  priceFeeds: {
    nativeToken: "0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e",
  },
};

const hardhatContracts: ContractsConfigType = {
  uniswapRouter: "0xE592427A0AEce92De3Edee1F18E0157C05861564",
  nonfungiblePositionManager: "0xC36442b4a4522E871399CD717aBDD847Ab11FE88",
  priceFeeds: {
    nativeToken: "0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612",
  },
};

export const contracts = {
  arbitrum: arbitrumContracts,
  goerli: goerliContracts,
  hardhat: hardhatContracts,
};

export const tokenPrice = 6;
