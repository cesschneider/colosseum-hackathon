import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';
import { buildMetric, Metric } from '../harness/metrics';

export interface S3StorageClass {
  name: string;
  costPerGbMonth: number; // USD
}

export const S3_STORAGE_CLASSES: S3StorageClass[] = [
  { name: 'STANDARD', costPerGbMonth: 0.023 },
  { name: 'STANDARD_IA', costPerGbMonth: 0.0125 },
  { name: 'DEEP_ARCHIVE', costPerGbMonth: 0.00099 }
];

export interface S3BenchmarkResult {
  storageClass: string;
  payloadBytes: number;
  costPerMonthUsd: number;
  costPerYearUsd: number;
  latencyMs: number;
}

/**
 * Mede latência de escrita (PUT) no S3 para uma classe de storage.
 * Deep Archive tem min 180 dias + retrieval lento, então não fazemos GET real.
 */
export async function benchmarkS3(
  client: S3Client,
  bucket: string,
  key: string,
  payload: Buffer,
  storageClass: string
): Promise<S3BenchmarkResult> {
  const start = Date.now();
  await client.send(
    new PutObjectCommand({
      Bucket: bucket,
      Key: key,
      Body: payload,
      StorageClass: storageClass as never
    })
  );
  const latencyMs = Date.now() - start;

  const gb = payload.length / (1024 * 1024 * 1024);
  const cls = S3_STORAGE_CLASSES.find((c) => c.name === storageClass);
  const costPerMonthUsd = (cls?.costPerGbMonth ?? 0) * gb;

  return {
    storageClass,
    payloadBytes: payload.length,
    costPerMonthUsd,
    costPerYearUsd: costPerMonthUsd * 12,
    latencyMs
  };
}

export function toMetrics(results: S3BenchmarkResult[]): Metric[] {
  return results.map((r) =>
    buildMetric({
      layer: 'aws-s3',
      operation: 'write',
      payloadBytes: r.payloadBytes,
      costSol: 0,
      solUsd: 0,
      latencyMs: r.latencyMs
    })
  );
}
