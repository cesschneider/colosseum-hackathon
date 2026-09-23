/**
 * Operational benchmark runner (YOLO execution, not part of the 7 stories' tests).
 * Runs the REAL network benchmarks against a live RPC (localhost validator by default,
 * devnet if SOLANA_RPC_URL is set) and produces measured JSON + CSV artifacts.
 *
 * Usage:
 *   npx ts-node scripts/run-benchmarks.ts [rpc-url] [keypair-path]
 */
import { Connection, Keypair, PublicKey } from '@solana/web3.js';
import * as fs from 'fs';
import * as path from 'path';
import { runRentBenchmark } from '../src/bench/rent';
import { runCompressionBenchmark } from '../src/bench/compression';
import { benchmarkS3, S3_STORAGE_CLASSES } from '../src/bench/s3';
import { S3Client } from '@aws-sdk/client-s3';
import { fetchSolPrice } from '../src/harness/price';
import { toMetrics as rentToMetrics } from '../src/bench/rent-model';
import { toMetrics as compToMetrics } from '../src/bench/compression-model';
import { toMetrics as s3ToMetrics } from '../src/bench/s3';
import type { Metric } from '../src/harness/metrics';

const DEFAULT_LAMPORTS_PER_BYTE = 6960; // rent-exempt lamports/byte (mainnet devnet value)

async function main() {
  const rpc = process.env.SOLANA_RPC_URL ?? process.argv[2] ?? 'http://localhost:8899';
  const kpPath =
    process.env.SOLANA_KEYPAIR_PATH ?? process.argv[3] ?? path.resolve('.deploy/local-wallet.json');

  const connection = new Connection(rpc, 'confirmed');
  const payer = Keypair.fromSecretKey(
    Buffer.from(JSON.parse(fs.readFileSync(kpPath, 'utf8')))
  );

  // Sanity: network health + balance.
  const health = await connection
    .getBalance(payer.publicKey)
    .then(() => 'ok')
    .catch(() => 'unavailable');
  const balance = await connection.getBalance(payer.publicKey).catch(() => -1);
  console.log(`[runner] rpc=${rpc} health=${health}`);
  console.log(`[runner] payer=${payer.publicKey.toBase58()} balance=${balance / 1e9} SOL`);

  // SOL price (CoinGecko) — needed for USD conversion.
  let solUsd = 0;
  let priceSource = 'unavailable';
  try {
    const p = await fetchSolPrice(process.env.COINGECKO_API_URL);
    solUsd = p.solUsd;
    priceSource = p.source;
  } catch (e: any) {
    console.log(`[runner] SOL price unavailable: ${e.message}`);
  }
  console.log(`[runner] SOL/USD = ${solUsd} (${priceSource})`);

  const allMetrics: Metric[] = [];
  const rows: any[] = [];
  const timestamp = new Date().toISOString();

  // 1) Rent benchmark (write + close, real txs on-chain).
  console.log('\n[runner] === BENCH: solana-rent (create/close accounts) ===');
  try {
    const rentResults = await runRentBenchmark(
      connection,
      payer,
      solUsd,
      DEFAULT_LAMPORTS_PER_BYTE
    );
    const metrics = rentToMetrics(rentResults);
    for (const m of metrics) allMetrics.push(m);
    for (const r of rentResults) {
      rows.push({
        layer: 'solana-rent',
        operation: 'write',
        payload_bytes: r.dataSize,
        cost_sol: r.costSol,
        cost_usd: r.costUsd,
        latency_ms: r.latencyMs,
        refunded_lamports: r.refundedLamports,
        net_cost_sol: r.netCostSol,
        timestamp
      });
      console.log(
        `  dataSize=${r.dataSize}B minBalance=${r.minBalanceLamports} lamports ` +
        `cost=${r.costSol.toExponential(6)} SOL ($${r.costUsd.toExponential(4)}) latency=${r.latencyMs}ms`
      );
    }
  } catch (e: any) {
    console.log(`  RENT BENCHMARK FAILED: ${e.message}`);
    rows.push({ layer: 'solana-rent', operation: 'write', error: e.message, timestamp });
  }

  // 2) Compression benchmark (Merkle tree rent estimate via RPC).
  console.log('\n[runner] === BENCH: solana-compression (tree rent estimate) ===');
  try {
    const compResults = await runCompressionBenchmark(connection, solUsd);
    const metrics = compToMetrics(compResults);
    for (const m of metrics) allMetrics.push(m);
    for (const r of compResults) {
      rows.push({
        layer: 'solana-compression',
        operation: 'write',
        payload_bytes: r.leafCount * 32,
        leaf_count: r.leafCount,
        cost_sol: r.costSol,
        cost_usd: r.costUsd,
        cost_per_leaf_sol: r.costPerLeafSol,
        latency_ms: r.latencyMs,
        timestamp
      });
      console.log(
        `  leaves=${r.leafCount} cost=${r.costSol.toExponential(6)} SOL ` +
        `($${r.costUsd.toExponential(4)}) perLeaf=${r.costPerLeafSol.toExponential(6)} SOL latency=${r.latencyMs}ms`
      );
    }
  } catch (e: any) {
    console.log(`  COMPRESSION BENCHMARK FAILED: ${e.message}`);
    rows.push({ layer: 'solana-compression', operation: 'write', error: e.message, timestamp });
  }

  // 3) Program benchmark (store/verify) — REQUIRES deployed .so.
  console.log('\n[runner] === BENCH: solana-program (store/verify) ===');
  console.log('  SKIPPED: programa Anchor (.so) nao compilado/deployed (ver progress.json).');
  rows.push({
    layer: 'solana-program',
    operation: 'deploy',
    status: 'não executado (bloqueado)',
    detail: 'anchor build .so indisponivel; ver progress.json',
    timestamp
  });

  // 4) S3 baseline (real PUT to AWS, eworks-dev profile).
  console.log('\n[runner] === BENCH: aws-s3 (PUT 1MB per storage class) ===');
  const bucket = process.env.S3_BUCKET || 'colosseum-poc-benchmark';
  const region = process.env.AWS_REGION || 'us-east-1';
  const client = new S3Client({ region });
  const payload = Buffer.alloc(1024 * 1024, 0xab);
  for (const cls of S3_STORAGE_CLASSES) {
    const key = `bench/${cls.name}/${Date.now()}.bin`;
    try {
      const r = await benchmarkS3(client, bucket, key, payload, cls.name);
      rows.push({
        layer: 'aws-s3',
        operation: 'write',
        storage_class: cls.name,
        payload_bytes: r.payloadBytes,
        cost_per_month_usd: r.costPerMonthUsd,
        cost_per_year_usd: r.costPerYearUsd,
        latency_ms: r.latencyMs,
        timestamp
      });
      console.log(
        `  [${cls.name}] latency=${r.latencyMs}ms cost/mo=$${r.costPerMonthUsd.toExponential(4)}`
      );
    } catch (e: any) {
      console.log(`  [${cls.name}] FAILED: ${e.message}`);
      rows.push({ layer: 'aws-s3', operation: 'write', storage_class: cls.name, error: e.message, timestamp });
    }
  }

  // Write artifacts.
  const outDir = path.resolve('docs/research');
  fs.mkdirSync(outDir, { recursive: true });

  const csvHeader = Object.keys(rows[0] ?? {}).join(',');
  const csvLines = rows.map((r) =>
    Object.values(r)
      .map((v) => {
        if (typeof v === 'number') return String(v);
        if (typeof v === 'string') return `"${v.replace(/"/g, '""')}"`;
        return String(v);
      })
      .join(',')
  );
  const csv = [csvHeader, ...csvLines].join('\n');
  fs.writeFileSync(path.resolve('bench-results.csv'), csv);
  fs.writeFileSync(
    path.resolve('docs/research/bench-results.raw.json'),
    JSON.stringify(
      {
        generated_at: timestamp,
        rpc,
        payer: payer.publicKey.toBase58(),
        sol_usd: solUsd,
        price_source: priceSource,
        lamports_per_byte: DEFAULT_LAMPORTS_PER_BYTE,
        rows,
        metrics: allMetrics
      },
      null,
      2
    )
  );

  console.log('\n[runner] DONE.');
  console.log(`  bench-results.csv -> ${path.resolve('bench-results.csv')}`);
  console.log(`  raw JSON          -> ${path.resolve('docs/research/bench-results.raw.json')}`);
}

main().catch((e) => {
  console.error('[runner] FATAL', e);
  process.exit(1);
});
