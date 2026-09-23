import { S3Client, PutObjectCommand } from '@aws-sdk/client-s3';

/**
 * Script de baseline S3: mede latência de escrita de payloads em 3 classes.
 * Uso: npx ts-node scripts/run-s3-baseline.ts
 */
const S3_STORAGE_CLASSES = [
  { name: 'STANDARD', costPerGbMonth: 0.023 },
  { name: 'STANDARD_IA', costPerGbMonth: 0.0125 },
  { name: 'DEEP_ARCHIVE', costPerGbMonth: 0.00099 }
];

async function main() {
  const bucket = process.env.S3_BUCKET || 'colosseum-poc-benchmark';
  const client = new S3Client({ region: process.env.AWS_REGION || 'us-east-1' });

  // Payload de 1 MB determinístico
  const payload = Buffer.alloc(1024 * 1024, 0xAB);

  const results: any[] = [];
  for (const cls of S3_STORAGE_CLASSES) {
    const key = `bench/${cls.name}/${Date.now()}.bin`;
    const start = Date.now();
    try {
      await client.send(
        new PutObjectCommand({
          Bucket: bucket,
          Key: key,
          Body: payload,
          StorageClass: cls.name as never
        })
      );
      const latencyMs = Date.now() - start;
      const gb = payload.length / (1024 * 1024 * 1024);
      const costPerMonthUsd = cls.costPerGbMonth * gb;
      results.push({
        layer: 'aws-s3',
        storageClass: cls.name,
        payload_bytes: payload.length,
        latency_ms: latencyMs,
        cost_per_month_usd: costPerMonthUsd,
        cost_per_year_usd: costPerMonthUsd * 12
      });
      console.log(`[${cls.name}] OK latency=${latencyMs}ms cost/mo=$${costPerMonthUsd.toFixed(6)}`);
    } catch (e: any) {
      console.log(`[${cls.name}] ERROR: ${e.message}`);
    }
  }

  console.log('\n=== RESULTADOS (JSON) ===');
  console.log(JSON.stringify(results, null, 2));
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
