export type Layer =
  | 'solana-rent'
  | 'solana-compression'
  | 'solana-program'
  | 'aws-s3';

export type Operation =
  | 'write'
  | 'read'
  | 'deploy'
  | 'verify'
  | 'close';

export interface Metric {
  layer: Layer;
  operation: Operation;
  payload_bytes: number;
  cost_sol: number;
  cost_usd: number;
  latency_ms: number;
  throughput_mbps: number;
  timestamp: string;
}

export interface PriceResult {
  solUsd: number;
  timestamp: string;
  source: string;
}

/**
 * Converte lamports para SOL.
 * 1 SOL = 1_000_000_000 lamports.
 */
export function lamportsToSol(lamports: number): number {
  if (lamports < 0) {
    throw new Error('lamports must be non-negative');
  }
  return lamports / 1_000_000_000;
}

/**
 * Converte SOL para USD dado um preço.
 */
export function solToUsd(sol: number, solUsd: number): number {
  if (sol < 0) {
    throw new Error('sol must be non-negative');
  }
  return sol * solUsd;
}

/**
 * Calcula throughput em MB/s a partir de bytes e latência em ms.
 */
export function computeThroughputMbps(payloadBytes: number, latencyMs: number): number {
  if (payloadBytes < 0 || latencyMs <= 0) {
    return 0;
  }
  const megabytes = payloadBytes / (1024 * 1024);
  const seconds = latencyMs / 1000;
  return seconds > 0 ? megabytes / seconds : 0;
}

export interface MetricInput {
  layer: Layer;
  operation: Operation;
  payloadBytes: number;
  costLamports?: number;
  costSol?: number;
  solUsd?: number;
  latencyMs: number;
  timestamp?: string;
}

/**
 * Constrói uma métrica normalizada com custo em SOL e USD.
 * Preferência: usa costSol direto se fornecido; senão converte de lamports via solUsd.
 */
export function buildMetric(input: MetricInput): Metric {
  const costSol = input.costSol ?? lamportsToSol(input.costLamports ?? 0);
  const costUsd = solToUsd(costSol, input.solUsd ?? 0);
  return {
    layer: input.layer,
    operation: input.operation,
    payload_bytes: input.payloadBytes,
    cost_sol: costSol,
    cost_usd: costUsd,
    latency_ms: input.latencyMs,
    throughput_mbps: computeThroughputMbps(input.payloadBytes, input.latencyMs),
    timestamp: input.timestamp ?? new Date().toISOString()
  };
}
