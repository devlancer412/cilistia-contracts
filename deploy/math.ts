import axios from "axios";
import { encodeSqrtRatioX96 } from "v3-sdk";

export const getSqrtPriceX96 = async (price: number, isFirst: boolean) => {
  const response = await axios.get(
    "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd",
  );
  const ethPrice = response.data?.ethereum?.usd * 100;

  return encodeSqrtRatioX96(isFirst ? price * 100 : ethPrice, isFirst ? ethPrice : price * 100).toString();
};
