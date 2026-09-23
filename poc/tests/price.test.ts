import { fetchSolPrice } from '../src/harness/price';

describe('fetchSolPrice', () => {
  it('extrai o preço de SOL da resposta do CoinGecko', async () => {
    const mockFetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ solana: { usd: 150.5 } })
    });
    global.fetch = mockFetch as unknown as typeof fetch;

    const result = await fetchSolPrice('https://example.com/price');
    expect(result.solUsd).toBe(150.5);
    expect(result.source).toBe('coingecko');
    expect(result.timestamp).toBeTruthy();
  });

  it('lança erro em resposta não-ok', async () => {
    const mockFetch = jest.fn().mockResolvedValue({ ok: false, status: 500 });
    global.fetch = mockFetch as unknown as typeof fetch;

    await expect(fetchSolPrice('https://example.com/price')).rejects.toThrow();
  });

  it('lança erro quando o preço é inválido', async () => {
    const mockFetch = jest.fn().mockResolvedValue({
      ok: true,
      json: async () => ({ solana: {} })
    });
    global.fetch = mockFetch as unknown as typeof fetch;

    await expect(fetchSolPrice('https://example.com/price')).rejects.toThrow();
  });
});
