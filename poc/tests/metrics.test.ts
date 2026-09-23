import {
  lamportsToSol,
  solToUsd,
  computeThroughputMbps,
  buildMetric
} from '../src/harness/metrics';

describe('lamportsToSol', () => {
  it('converte 1 SOL corretamente', () => {
    expect(lamportsToSol(1_000_000_000)).toBe(1);
  });

  it('converte frações', () => {
    expect(lamportsToSol(500_000_000)).toBe(0.5);
  });

  it('rejeita valor negativo', () => {
    expect(() => lamportsToSol(-1)).toThrow();
  });
});

describe('solToUsd', () => {
  it('converte SOL para USD', () => {
    expect(solToUsd(2, 150)).toBe(300);
  });

  it('rejeita SOL negativo', () => {
    expect(() => solToUsd(-1, 100)).toThrow();
  });
});

describe('computeThroughputMbps', () => {
  it('calcula throughput', () => {
    // 1 MB em 1000ms = 1 MB/s
    const bytes = 1024 * 1024;
    expect(computeThroughputMbps(bytes, 1000)).toBeCloseTo(1, 5);
  });

  it('retorna 0 para latência <= 0', () => {
    expect(computeThroughputMbps(1024, 0)).toBe(0);
  });
});

describe('buildMetric', () => {
  it('constrói métrica de lamports', () => {
    const m = buildMetric({
      layer: 'solana-rent',
      operation: 'write',
      payloadBytes: 1024,
      costLamports: 1_000_000_000,
      solUsd: 150,
      latencyMs: 500,
      timestamp: '2026-09-23T00:00:00.000Z'
    });
    expect(m.cost_sol).toBe(1);
    expect(m.cost_usd).toBe(150);
    expect(m.layer).toBe('solana-rent');
    expect(m.timestamp).toBe('2026-09-23T00:00:00.000Z');
  });

  it('usa costSol direto quando fornecido', () => {
    const m = buildMetric({
      layer: 'solana-program',
      operation: 'verify',
      payloadBytes: 32,
      costSol: 0.000005,
      solUsd: 150,
      latencyMs: 400
    });
    expect(m.cost_sol).toBe(0.000005);
    expect(m.cost_usd).toBeCloseTo(0.00075, 6);
  });
});
