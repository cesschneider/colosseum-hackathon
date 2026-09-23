import { Connection, Keypair, SystemProgram, Transaction, LAMPORTS_PER_SOL } from '@solana/web3.js';
import { rentExemptMinimum, RentBenchmarkResult } from './rent-model';

/**
 * Mede o custo de alocar uma conta com `dataSize` bytes (rent deposit)
 * e o reembolso ao fechá-la. Retorna métricas por tamanho.
 */
export async function benchmarkRent(
  connection: Connection,
  payer: Keypair,
  dataSize: number,
  lamportsPerByte: number,
  solUsd: number
): Promise<RentBenchmarkResult> {
  const minBalance = rentExemptMinimum(dataSize, lamportsPerByte);
  const newAccount = Keypair.generate();
  const start = Date.now();

  const tx = new Transaction().add(
    SystemProgram.createAccount({
      fromPubkey: payer.publicKey,
      newAccountPubkey: newAccount.publicKey,
      lamports: minBalance,
      space: dataSize,
      programId: SystemProgram.programId
    })
  );
  const sig = await connection.sendTransaction(tx, [payer, newAccount], { skipPreflight: false });
  await connection.confirmTransaction(sig, 'confirmed');

  // Fechar a conta para reclamar o depósito.
  const closeTx = new Transaction().add(
    SystemProgram.transfer({
      fromPubkey: newAccount.publicKey,
      toPubkey: payer.publicKey,
      lamports: minBalance
    })
  );
  const closeSig = await connection.sendTransaction(closeTx, [newAccount], { skipPreflight: false });
  await connection.confirmTransaction(closeSig, 'confirmed');

  const latencyMs = Date.now() - start;
  const costSol = minBalance / LAMPORTS_PER_SOL;

  return {
    dataSize,
    minBalanceLamports: minBalance,
    costSol,
    costUsd: costSol * solUsd,
    refundedLamports: minBalance,
    netCostSol: 0,
    latencyMs
  };
}

export async function runRentBenchmark(
  connection: Connection,
  payer: Keypair,
  solUsd: number,
  lamportsPerByte: number
): Promise<RentBenchmarkResult[]> {
  const sizes = [128, 1024, 10 * 1024, 100 * 1024, 1024 * 1024];
  const results: RentBenchmarkResult[] = [];
  for (const size of sizes) {
    results.push(await benchmarkRent(connection, payer, size, lamportsPerByte, solUsd));
  }
  return results;
}
