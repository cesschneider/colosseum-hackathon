import { S3_STORAGE_CLASSES, toMetrics } from '../src/bench/s3';

describe('S3_STORAGE_CLASSES', () => {
  it('define 3 classes com custo esperado', () => {
    expect(S3_STORAGE_CLASSES).toHaveLength(3);
    const std = S3_STORAGE_CLASSES.find((c) => c.name === 'STANDARD');
    expect(std?.costPerGbMonth).toBe(0.023);
    const deep = S3_STORAGE_CLASSES.find((c) => c.name === 'DEEP_ARCHIVE');
    expect(deep?.costPerGbMonth).toBe(0.00099);
  });
});

describe('toMetrics (s3)', () => {
  it('converte resultados em métricas', () => {
    const metrics = toMetrics([
      {
        storageClass: 'STANDARD',
        payloadBytes: 1024,
        costPerMonthUsd: 0.000023,
        costPerYearUsd: 0.000276,
        latencyMs: 200
      }
    ]);
    expect(metrics).toHaveLength(1);
    expect(metrics[0].layer).toBe('aws-s3');
    expect(metrics[0].cost_sol).toBe(0);
  });
});
