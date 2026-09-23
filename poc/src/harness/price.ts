import { PriceResult } from './metrics';

/**
 * Busca o preço atual de SOL em USD via CoinGecko.
 * Retorna um PriceResult com timestamp da consulta.
 */
export async function fetchSolPrice(
  url: string = 'https://api.coingecko.com/api/v3/simple/price'
): Promise<PriceResult> {
  const timestamp = new Date().toISOString();
  const params = new URLSearchParams({ ids: 'solana', vs_currencies: 'usd' });
  const res = await fetch(`${url}?${params.toString()}`);
  if (!res.ok) {
    throw new Error(`CoinGecko request failed: ${res.status}`);
  }
  const data = (await res.json()) as { solana?: { usd?: number } };
  const usd = data.solana?.usd;
  if (typeof usd !== 'number' || usd <= 0) {
    throw new Error('Invalid SOL price in CoinGecko response');
  }
  return { solUsd: usd, timestamp, source: 'coingecko' };
}
