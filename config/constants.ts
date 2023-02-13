export interface ContractsConfigType {
  uniswapRouter: string;
  USDT?: string;
  USDC?: string;
  priceFeeds: {
    nativeToken: string;
    [name: string]: string;
  };
}

const mainnetContracts: ContractsConfigType = {
  uniswapRouter: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
  USDT: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  USDC: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
  priceFeeds: {
    nativeToken: "0xaEA2808407B7319A31A383B6F8B60f04BCa23cE2",
  },
};
const goerliContracts: ContractsConfigType = {
  uniswapRouter: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
  priceFeeds: {
    nativeToken: "0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e",
  },
};
const hardhatContracts: ContractsConfigType = {
  uniswapRouter: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
  priceFeeds: {
    nativeToken: "0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e",
  },
};
const avaxContracts: ContractsConfigType = {
  uniswapRouter: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
  USDT: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
  USDC: "0xdAC17F958D2ee523a2206206994597C13D831ec7",
  priceFeeds: {
    nativeToken: "0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e",
  },
};

export const contracts = {
  mainnet: mainnetContracts,
  goerli: goerliContracts,
  hardhat: hardhatContracts,
  avax: avaxContracts,
};

export const tokenPrice = 6;
