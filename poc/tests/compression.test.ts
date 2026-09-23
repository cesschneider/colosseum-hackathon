import { toMetrics, treeBytes } from '../src/bench/compression-model';

describe('treeBytes', () => {
  it('calcula tamanho da árvore (2n-1)*32', () => {
    expect(treeBytes(3)).toBe((2 * 3 - 1) * 32);
    expect(treeBytes(1)).toBe(32);
  });

  it('rejeita negativo', () => {
    expect(() => treeBytes(-1)).toThrow();
  });
});

describe('toMetrics (compression)', () => {
  it('converte resultados em métricas', () => {
    const metrics = toMetrics([
      {
        leafCount: 1000,
        costSol: 0.001,
        costUsd: 0.15,
        costPerLeafSol: 0.000001,
        latencyMs: 300
      }
    ]);
    expect(metrics).toHaveLength(1);
    expect(metrics[0].layer).toBe('solana-compression');
    expect(metrics[0].payload_bytes).toBe(1000 * 32);
  });
});
