import mongoose from 'mongoose';
import { getEnv } from '../config/env';
import { getLogger } from '../utils/logger';

let isConnecting = false;

export async function connectDatabase(uri?: string): Promise<typeof mongoose> {
  const env = getEnv();
  const mongoUri = uri ?? env.MONGODB_URI;
  const logger = getLogger();

  if (mongoose.connection.readyState === 1) {
    return mongoose;
  }

  if (isConnecting) {
    await new Promise<void>((resolve, reject) => {
      mongoose.connection.once('connected', () => resolve());
      mongoose.connection.once('error', reject);
    });
    return mongoose;
  }

  isConnecting = true;
  try {
    mongoose.set('strictQuery', true);
    await mongoose.connect(mongoUri, {
      serverSelectionTimeoutMS: 10_000,
      connectTimeoutMS: 10_000,
      socketTimeoutMS: 45_000,
      maxPoolSize: 20,
      minPoolSize: 1,
    });
    logger.info({ readyState: mongoose.connection.readyState }, 'MongoDB connected');
    return mongoose;
  } finally {
    isConnecting = false;
  }
}

export async function disconnectDatabase(): Promise<void> {
  if (mongoose.connection.readyState !== 0) {
    await mongoose.disconnect();
    getLogger().info('MongoDB disconnected');
  }
}

export function getDatabaseHealth(): {
  status: 'up' | 'down';
  readyState: number;
  name?: string;
} {
  const { readyState, name } = mongoose.connection;
  return {
    status: readyState === 1 ? 'up' : 'down',
    readyState,
    name: name || undefined,
  };
}

export async function pingDatabase(): Promise<boolean> {
  if (mongoose.connection.readyState !== 1 || !mongoose.connection.db) {
    return false;
  }
  const result = await mongoose.connection.db.admin().ping();
  return Boolean(result?.ok);
}

export function supportsTransactions(): boolean {
  // Transactions require a replica set (or mongos). Detection is best-effort.
  const topology = (mongoose.connection as unknown as { client?: { options?: { replicaSet?: string } } })
    .client?.options?.replicaSet;
  return Boolean(topology) || getEnv().MONGODB_URI.includes('replicaSet=');
}

export async function withTransaction<T>(
  fn: (session: mongoose.ClientSession) => Promise<T>,
): Promise<T> {
  const session = await mongoose.startSession();
  try {
    let result!: T;
    await session.withTransaction(async () => {
      result = await fn(session);
    });
    return result;
  } finally {
    await session.endSession();
  }
}
