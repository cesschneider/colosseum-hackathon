/**
 * Operational program benchmark (YOLO execution).
 * Drives the deployed `dataset-provenance` program directly (store_dataset +
 * verify_dataset) via raw web3.js + manual Anchor discriminator/borsh encoding.
 * Measures: store latency, verify latency, record account rent (provenance cost).
 *
 * Usage:
 *   SOLANA_RPC_URL=http://localhost:8899 SOLANA_KEYPAIR_PATH=.deploy/local-wallet.json \
 *     npx ts-node scripts/run-program-benchmark.ts
 */
import { Connection, Keypair, PublicKey, Transaction, TransactionInstruction, SystemProgram, LAMPORTS_PER_SOL } from '@solana/web3.js';
import { createHash } from 'crypto';
import * as fs from 'fs';
import * as path from 'path';

const PROGRAM_ID = new PublicKey('6nevEtv1X6KV8BprxJdD5qJSAPkdi2tym2zZPrvxeqF7');

function discriminator(name: string): Buffer {
  return createHash('sha256').update(`global:${name}`).digest().subarray(0, 8);
}

function borshString(s: string): Buffer {
  const b = Buffer.from(s, 'utf8');
  const len = Buffer.alloc(4);
  len.writeUInt32LE(b.length, 0);
  return Buffer.concat([len, b]);
}

function borshU32(n: number): Buffer {
  const b = Buffer.alloc(4);
  b.writeUInt32LE(n, 0);
  return b;
}

async function findRecordPda(datasetId: string): Promise<[PublicKey, number]> {
  return PublicKey.findProgramAddress(
    [Buffer.from('dataset'), Buffer.from(datasetId, 'utf8')],
    PROGRAM_ID
  );
}

async function main() {
  const rpc = process.env.SOLANA_RPC_URL ?? 'http://localhost:8899';
  const kpPath = process.env.SOLANA_KEYPAIR_PATH ?? '.deploy/local-wallet.json';
  const connection = new Connection(rpc, 'confirmed');
  const payer = Keypair.fromSecretKey(
    Buffer.from(JSON.parse(fs.readFileSync(path.resolve(kpPath), 'utf8')))
  );

  const datasetId = `bench-${Date.now()}`;
  const contentHash = createHash('sha256').update('colosseum-micr-br-dataset').digest();
  const source = 'IBGE microdados (PoC)';
  const license = 'CC-BY-4.0';
  const schemaVersion = 1;

  const [recordPda] = await findRecordPda(datasetId);
  console.log(`[program] rpc=${rpc}`);
  console.log(`[program] payer=${payer.publicKey.toBase58()} balance=${(await connection.getBalance(payer.publicKey)) / 1e9} SOL`);
  console.log(`[program] dataset_id=${datasetId}`);
  console.log(`[program] record_pda=${recordPda.toBase58()}`);

  // ---- STORE ----
  const storeIx = new TransactionInstruction({
    keys: [
      { pubkey: recordPda, isSigner: false, isWritable: true },
      { pubkey: payer.publicKey, isSigner: true, isWritable: true },
      { pubkey: SystemProgram.programId, isSigner: false, isWritable: false },
    ],
    programId: PROGRAM_ID,
    data: Buffer.concat([
      discriminator('store_dataset'),
      borshString(datasetId),
      Buffer.from(contentHash),
      borshString(source),
      borshString(license),
      borshU32(schemaVersion),
    ]),
  });

  const storeStart = Date.now();
  const storeTx = new Transaction().add(storeIx);
  storeTx.feePayer = payer.publicKey;
  storeTx.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;
  storeTx.sign(payer);
  const storeSig = await connection.sendRawTransaction(storeTx.serialize(), { skipPreflight: false });
  await connection.confirmTransaction(storeSig, 'confirmed');
  const storeLatency = Date.now() - storeStart;

  const storeMeta = await connection.getTransaction(storeSig, { commitment: 'confirmed' });
  const storeFee = storeMeta?.meta?.fee ?? 0;

  // Record account rent (the provenance storage cost).
  const recordInfo = await connection.getAccountInfo(recordPda);
  const recordLamports = recordInfo?.lamports ?? 0;
  const recordBytes = recordInfo?.data.length ?? 0;

  console.log(`[program] STORE  sig=${storeSig}`);
  console.log(`[program] STORE  latency=${storeLatency}ms fee=${storeFee} lamports`);
  console.log(`[program] RECORD rent=${recordLamports} lamports (${recordLamports / 1e9} SOL) size=${recordBytes} bytes`);

  // ---- VERIFY (read-only, true + false) ----
  async function verify(hash: Buffer, label: string) {
    const ix = new TransactionInstruction({
      keys: [{ pubkey: recordPda, isSigner: false, isWritable: false }],
      programId: PROGRAM_ID,
      data: Buffer.concat([discriminator('verify_dataset'), borshString(datasetId), Buffer.from(hash)]),
    });
    const start = Date.now();
    const tx = new Transaction().add(ix);
    tx.feePayer = payer.publicKey;
    tx.recentBlockhash = (await connection.getLatestBlockhash()).blockhash;
    tx.sign(payer);
    const sig = await connection.sendRawTransaction(tx.serialize(), { skipPreflight: false });
    await connection.confirmTransaction(sig, 'confirmed');
    const latency = Date.now() - start;
    const meta = await connection.getTransaction(sig, { commitment: 'confirmed' });
    const fee = meta?.meta?.fee ?? 0;
    console.log(`[program] VERIFY ${label} latency=${latency}ms fee=${fee} lamports sig=${sig}`);
    return { latency, fee };
  }

  const vTrue = await verify(contentHash, '(match)');
  const wrongHash = Buffer.from(contentHash);
  wrongHash[0] ^= 0xff;
  const vFalse = await verify(wrongHash, '(mismatch)');

  // ---- EMIT RESULTS ----
  const solUsd = parseFloat(process.env.SOL_USD ?? '0');
  const row = {
    layer: 'solana-program',
    operation: 'store/verify',
    dataset_id: datasetId,
    record_pda: recordPda.toBase58(),
    record_rent_lamports: recordLamports,
    record_rent_sol: recordLamports / 1e9,
    record_size_bytes: recordBytes,
    store_fee_lamports: storeFee,
    store_latency_ms: storeLatency,
    verify_match_latency_ms: vTrue.latency,
    verify_mismatch_latency_ms: vFalse.latency,
    verify_fee_lamports: vTrue.fee,
    sol_usd: solUsd,
    network: 'local-validator',
    program_id: PROGRAM_ID.toBase58(),
    timestamp: new Date().toISOString(),
  };

  const outPath = path.resolve('docs/research/program-benchmark.json');
  fs.writeFileSync(outPath, JSON.stringify(row, null, 2));
  console.log(`\n[program] RESULT -> ${outPath}`);
  console.log(JSON.stringify(row, null, 2));
}

main().catch((e) => {
  console.error('[program] FATAL', e);
  process.exit(1);
});

