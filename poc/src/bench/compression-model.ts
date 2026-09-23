import { buildMetric, Metric } from '../harness/metrics';

export interface CompressionBenchmarkResult {
  leafCount: number;
  costSol: number;
  costUsd: number;
  costPerLeafSol: number;
  latencyMs: number;
}

/**
 * Estima o tamanho (bytes) de uma Merkle tree com `leafCount` leaves.
 * Fórmula: (2 * leafCount - 1) * 32 bytes por nó.
 */
export function treeBytes(leafCount: number): number {
  if (leafCount < 0) {
    throw new Error('leafCount must be non-negative');
  }
  return (2 * leafCount - 1) * 32;
}

export function toMetrics(results: CompressionBenchmarkResult[]): Metric[] {
  return results.map((r) =>
    buildMetric({
      layer: 'solana-compression',
      operation: 'write',
      payloadBytes: r.leafCount * 32,
      costSol: r.costSol,
      solUsd: r.costSol > 0 ? r.costUsd / r.costSol : 0,
      latencyMs: r.latencyMs
    })
  );
}
