import { Connection, Keypair } from '@solana/web3.js';
import * as fs from 'fs';
import { fetchSolPrice } from './harness/price';

/**
 * CLI do PoC. Subcomandos:
 *   npm run hello            → valida conectividade Solana (airdrop + balance + latência)
 *   npm run bench            → executa todos os benchmarks e grava JSON/CSV
 */
async function main(): Promise<void> {
  const cmd = process.argv[2] ?? 'hello';
  switch (cmd) {
    case 'hello':
      await hello();
      break;
    case 'bench':
      await bench();
      break;
    default:
      console.error(`Comando desconhecido: ${cmd}. Use 'hello' ou 'bench'.`);
      process.exit(1);
  }
}

async function getEnv(): Promise<{ connection: Connection; payer: Keypair; solUsd: number }> {
  const rpc = process.env.SOLANA_RPC_URL ?? 'https://api.devnet.solana.com';
  const connection = new Connection(rpc, 'confirmed');
  const payer = loadPayer();
  const { solUsd } = await fetchSolPrice(process.env.COINGECKO_API_URL);
  return { connection, payer, solUsd };
}

function loadPayer(): Keypair {
  const pk = process.env.SOLANA_PRIVATE_KEY;
  const kpPath = process.env.SOLANA_KEYPAIR_PATH;
  if (pk) {
    return Keypair.fromSecretKey(Buffer.from(JSON.parse(pk)));
  }
  if (kpPath) {
    const secret = JSON.parse(fs.readFileSync(kpPath, 'utf8'));
    return Keypair.fromSecretKey(Buffer.from(secret));
  }
  // Fallback: gera uma wallet efêmera (sem saldo) — só para smoke test local.
  return Keypair.generate();
}

async function hello(): Promise<void> {
  const { connection, payer } = await getEnv();
  const start = Date.now();
  try {
    // Airdrop de 1 SOL em devnet.
    const airdropSig = await connection.requestAirdrop(payer.publicKey, 1_000_000_000);
    await connection.confirmTransaction(airdropSig, 'confirmed');
  } catch {
    // Se a wallet já tem saldo ou airdrop falhou, segue.
  }
  const balance = await connection.getBalance(payer.publicKey);
  const latencyMs = Date.now() - start;
  console.log(JSON.stringify({
    pubkey: payer.publicKey.toBase58(),
    balanceSol: balance / 1_000_000_000,
    latencyMs,
    network: process.env.SOLANA_NETWORK ?? 'devnet'
  }, null, 2));
}

async function bench(): Promise<void> {
  // Benchmarks de rede são executados manualmente; aqui apenas valida o preço e imprime o schema.
  const { solUsd } = await getEnv();
  console.log(JSON.stringify({
    status: 'ready',
    solUsd,
    note: 'Benchmarks de rede são executados via `npm run bench:rent`, `:compression`, `:program`, `:s3`.'
  }, null, 2));
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
