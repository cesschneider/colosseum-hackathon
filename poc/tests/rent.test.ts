import { rentExemptMinimum, toMetrics } from '../src/bench/rent-model';

describe('rentExemptMinimum', () => {
  it('aplica a fórmula (128 + data_size) * lamports_per_byte', () => {
    expect(rentExemptMinimum(0, 6960)).toBe(128 * 6960);
    expect(rentExemptMinimum(100, 6960)).toBe(228 * 6960);
  });

  it('rejeita valores negativos', () => {
    expect(() => rentExemptMinimum(-1, 100)).toThrow();
    expect(() => rentExemptMinimum(100, -1)).toThrow();
  });
});

describe('toMetrics (rent)', () => {
  it('converte resultados em métricas', () => {
    const metrics = toMetrics([
      {
        dataSize: 1024,
        minBalanceLamports: 1_000_000_000,
        costSol: 1,
        costUsd: 150,
        refundedLamports: 1_000_000_000,
        netCostSol: 0,
        latencyMs: 500
      }
    ]);
    expect(metrics).toHaveLength(1);
    expect(metrics[0].layer).toBe('solana-rent');
    expect(metrics[0].operation).toBe('write');
    expect(metrics[0].payload_bytes).toBe(1024);
  });
});
