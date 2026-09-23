import { buildMetric, Metric } from '../harness/metrics';

export const ACCOUNT_OVERHEAD_BYTES = 128;

/**
 * Calcula o min_balance (rent-exempt) para um tamanho de conta.
 * Fórmula Solana: min_balance = (128 + data_size) * lamports_per_byte.
 */
export function rentExemptMinimum(dataSize: number, lamportsPerByte: number): number {
  if (dataSize < 0 || lamportsPerByte < 0) {
    throw new Error('dataSize and lamportsPerByte must be non-negative');
  }
  return (ACCOUNT_OVERHEAD_BYTES + dataSize) * lamportsPerByte;
}

export interface RentBenchmarkResult {
  dataSize: number;
  minBalanceLamports: number;
  costSol: number;
  costUsd: number;
  refundedLamports: number;
  netCostSol: number;
  latencyMs: number;
}

export function toMetrics(results: RentBenchmarkResult[]): Metric[] {
  return results.map((r) =>
    buildMetric({
      layer: 'solana-rent',
      operation: 'write',
      payloadBytes: r.dataSize,
      costSol: r.costSol,
      solUsd: r.costSol > 0 ? r.costUsd / r.costSol : 0,
      latencyMs: r.latencyMs
    })
  );
}
