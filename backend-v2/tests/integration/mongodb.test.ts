import { describe, expect, it } from 'vitest';
import mongoose from 'mongoose';
import { getDatabaseHealth, pingDatabase, withTransaction } from '../../src/database/connection';
import { SocietyModel } from '../../src/modules/society/models/society.model';

describe('MongoDB connection', () => {
  it('reports healthy connection', async () => {
    const health = getDatabaseHealth();
    expect(health.status).toBe('up');
    expect(health.readyState).toBe(1);
    await expect(pingDatabase()).resolves.toBe(true);
  });

  it('supports replica-set transactions', async () => {
    const result = await withTransaction(async (session) => {
      const [society] = await SocietyModel.create(
        [{ name: 'Txn Society', code: 'TXN1', isActive: true }],
        { session },
      );
      return society;
    });
    expect(result.code).toBe('TXN1');
    const found = await SocietyModel.findById(result._id);
    expect(found).not.toBeNull();
    expect(mongoose.connection.readyState).toBe(1);
  });
});
