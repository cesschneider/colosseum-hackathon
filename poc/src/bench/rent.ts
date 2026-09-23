import { Connection, Keypair, SystemProgram, Transaction, LAMPORTS_PER_SOL } from '@solana/web3.js';
import { rentExemptMinimum, RentBenchmarkResult } from './rent-model';

/**
 * Mede o custo de alocar uma conta com `dataSize` bytes (rent deposit).
 *
 * NOTA (correção operacional): uma conta System com dados NÃO pode ser fechada
 * por transfer direta — o fechamento exige o `close` do programa dono. Como aqui
 * criamos contas de propriedade do System Program (para isolar o custo de rent
 * puro), não há fechamento programático; registramos o depósito medido e
 * `refundedLamports: 0` (sem reembolso aplicável neste caminho).
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

  const latencyMs = Date.now() - start;
  const costSol = minBalance / LAMPORTS_PER_SOL;

  return {
    dataSize,
    minBalanceLamports: minBalance,
    costSol,
    costUsd: costSol * solUsd,
    refundedLamports: 0,
    netCostSol: costSol,
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
