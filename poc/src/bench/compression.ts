import { Connection } from '@solana/web3.js';
import { CompressionBenchmarkResult, treeBytes } from './compression-model';

/**
 * Estima o custo de uma Merkle tree de `leafCount` leaves via rent da conta da árvore.
 */
export async function benchmarkCompression(
  connection: Connection,
  leafCount: number,
  solUsd: number
): Promise<CompressionBenchmarkResult> {
  const start = Date.now();
  const rentLamports = await connection.getMinimumBalanceForRentExemption(treeBytes(leafCount));
  const costSol = rentLamports / 1_000_000_000;
  const latencyMs = Date.now() - start;

  return {
    leafCount,
    costSol,
    costUsd: costSol * solUsd,
    costPerLeafSol: leafCount > 0 ? costSol / leafCount : 0,
    latencyMs
  };
}

export async function runCompressionBenchmark(
  connection: Connection,
  solUsd: number
): Promise<CompressionBenchmarkResult[]> {
  const leafCounts = [1_000, 10_000, 100_000];
  const results: CompressionBenchmarkResult[] = [];
  for (const n of leafCounts) {
    results.push(await benchmarkCompression(connection, n, solUsd));
  }
  return results;
}
