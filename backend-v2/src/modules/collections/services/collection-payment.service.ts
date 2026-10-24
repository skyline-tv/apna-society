import type { ClientSession } from 'mongoose';
import { isDemoPaymentsEnabled, isOnlineCheckoutEnabled } from '../../../config/env';
import { withTransaction } from '../../../database/connection';
import {
  AppError,
  badRequest,
  conflict,
  forbidden,
  notFound,
} from '../../../shared/errors/app-error';
import { isDuplicateKeyError, mapMongoWriteError } from '../../../utils/mongo-errors';
import { formatFlatLabel } from '../../../utils/flat-label';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { nextSequence } from '../../billing/models/sequence.model';
import { getPaymentProvider } from '../../billing/providers/payment-provider.factory';
import { buildReceiptPdf } from '../../billing/services/pdf.service';
import { SocietyModel } from '../../society/models/society.model';
import { assertFinancialAccess } from '../../users/services/access-control.service';
import { CollectionChargeModel } from '../models/collection-charge.model';
import { CollectionPaymentModel } from '../models/collection-payment.model';
import { CollectionReceiptModel } from '../models/collection-receipt.model';
import { CollectionModel } from '../models/collection.model';
import { deriveChargeStatus, requireActiveCollection } from './collection.service';
import type { WebhookEvent } from '../../billing/providers/payment-provider';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

function rethrowPaymentError(error: unknown): never {
  if (error instanceof AppError) throw error;
  if (isDuplicateKeyError(error)) {
    throw conflict('Duplicate collection payment settlement', 'DUPLICATE_PAYMENT');
  }
  mapMongoWriteError(error, 'Duplicate collection payment settlement');
}

async function nextCollectionPaymentNumber(societyId: string, session: ClientSession) {
  const year = new Date().getUTCFullYear();
  const seq = await nextSequence(societyId, `colpay-${year}`, session);
  return `COLPAY-${year}-${seq.toString().padStart(6, '0')}`;
}

async function nextCollectionReceiptNumber(societyId: string, session: ClientSession) {
  const year = new Date().getUTCFullYear();
  const seq = await nextSequence(societyId, `colrcpt-${year}`, session);
  return `COLRCPT-${year}-${seq.toString().padStart(6, '0')}`;
}

function serializePayment(
  row: {
    _id: { toString(): string };
    paymentNumber: string;
    collectionId: { toString(): string };
    chargeId: { toString(): string };
    flatId: { toString(): string };
    ownerUserId?: { toString(): string } | null;
    amountPaise: number;
    paymentMethod: string;
    status: string;
    paidAt?: Date;
    referenceNumber?: string;
    gatewayOrderId?: string;
    gatewayPaymentId?: string;
    receiptId?: string;
  },
  extras?: { wingCodeSnapshot?: string; flatNumberSnapshot?: string },
) {
  const wingCodeSnapshot = extras?.wingCodeSnapshot;
  const flatNumberSnapshot = extras?.flatNumberSnapshot;
  const flatLabel = formatFlatLabel(wingCodeSnapshot, flatNumberSnapshot);
  return {
    id: String(row._id),
    paymentNumber: row.paymentNumber,
    collectionId: String(row.collectionId),
    chargeId: String(row.chargeId),
    flatId: String(row.flatId),
    ownerUserId: row.ownerUserId ? String(row.ownerUserId) : undefined,
    amountPaise: row.amountPaise,
    paymentMethod: row.paymentMethod,
    status: row.status,
    paidAt: row.paidAt?.toISOString(),
    referenceNumber: row.referenceNumber,
    gatewayOrderId: row.gatewayOrderId,
    gatewayPaymentId: row.gatewayPaymentId,
    receiptId: row.receiptId,
    wingCodeSnapshot,
    flatNumberSnapshot,
    flatLabel: flatLabel || undefined,
  };
}

export async function createCollectionPaymentOrder(
  societyId: string,
  chargeId: string,
  ownerUserId: string,
  amountPaiseInput: number | undefined,
  actor: Actor,
) {
  const charge = await CollectionChargeModel.findOne({
    _id: parseObjectId(chargeId, 'chargeId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!charge) throw notFound('Collection charge not found');
  const collection = await requireActiveCollection(societyId, String(charge.collectionId));
  if (charge.status === 'CANCELLED' || charge.status === 'PAID') {
    throw badRequest('This collection charge is already settled', 'CHARGE_ALREADY_PAID');
  }
  if (charge.outstandingPaise <= 0) {
    throw badRequest('This collection charge is already settled', 'CHARGE_ALREADY_PAID');
  }
  if (!charge.ownerUserId || String(charge.ownerUserId) !== ownerUserId) {
    throw forbidden('Only the flat owner may pay this collection', 'NOT_CHARGE_OWNER');
  }
  await assertFinancialAccess({
    userId: ownerUserId,
    societyId,
    flatId: String(charge.flatId),
  });

  const requested = amountPaiseInput ?? charge.outstandingPaise;
  if (requested <= 0 || requested > charge.outstandingPaise) {
    throw badRequest('Payment amount is invalid', 'INVALID_AMOUNT');
  }
  if (!collection.allowPartialPayment && requested !== charge.outstandingPaise) {
    throw badRequest('Partial payment is not enabled for this collection', 'PARTIAL_PAYMENT_DISABLED');
  }
  if (!isOnlineCheckoutEnabled()) {
    throw forbidden(
      'Online payment is not available. Please pay cash or cheque at the society office.',
      'ONLINE_PAYMENTS_DISABLED',
    );
  }

  const provider = getPaymentProvider();
  const order = await provider.createOrder({
    amountPaise: requested,
    receipt: `${collection.collectionNumber}-${charge.flatNumberSnapshot}`,
    notes: {
      collectionId: String(collection._id),
      chargeId: String(charge._id),
      societyId,
    },
  });

  const payment = await withTransaction(async (session) => {
    const paymentNumber = await nextCollectionPaymentNumber(societyId, session);
    const [doc] = await CollectionPaymentModel.create(
      [
        {
          societyId,
          collectionId: collection._id,
          chargeId: charge._id,
          flatId: charge.flatId,
          ownerUserId: charge.ownerUserId,
          paymentNumber,
          amountPaise: requested,
          paymentMethod: 'UPI',
          status: 'PENDING',
          gateway: provider.name,
          gatewayOrderId: order.orderId,
          createdBy: actor.userId,
        },
      ],
      { session },
    );
    await writeAuditLog(
      {
        action: 'COLLECTION_PAYMENT_INITIATED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'SpecialCollectionPayment',
        targetId: String(doc._id),
        metadata: { chargeId: String(charge._id), amountPaise: requested },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );
    return doc;
  });

  return {
    paymentId: String(payment._id),
    paymentNumber: payment.paymentNumber,
    chargeId: String(charge._id),
    collectionId: String(collection._id),
    amountPaise: requested,
    order,
  };
}

async function settleCollectionPayment(input: {
  societyId: string;
  payment: InstanceType<typeof CollectionPaymentModel>;
  gatewayPaymentId: string;
  signatureVerified: boolean;
  paidAt: Date;
  actor?: Actor;
  source: 'verify' | 'webhook' | 'offline';
}) {
  if (input.payment.status === 'SUCCESS') {
    const existingReceipt = await CollectionReceiptModel.findOne({
      paymentId: input.payment._id,
    }).lean();
    return {
      paymentId: String(input.payment._id),
      alreadySettled: true,
      receiptId: existingReceipt ? String(existingReceipt._id) : undefined,
    };
  }

  const society = await SocietyModel.findById(input.societyId).lean();
  if (!society) throw notFound('Society not found');

  try {
    return await withTransaction(async (session) => {
      const claimed = await CollectionPaymentModel.findOneAndUpdate(
        { _id: input.payment._id, status: { $in: ['PENDING', 'FAILED'] } },
        {
          $set: {
            status: 'SUCCESS',
            gatewayPaymentId: input.gatewayPaymentId,
            gatewaySignatureVerified: input.signatureVerified,
            paidAt: input.paidAt,
            receivedAt: input.paidAt,
          },
        },
        { session, new: true },
      );
      if (!claimed) {
        const existing = await CollectionPaymentModel.findById(input.payment._id).session(session);
        if (existing?.status === 'SUCCESS') {
          const existingReceipt = await CollectionReceiptModel.findOne({
            paymentId: existing._id,
          }).session(session);
          return {
            paymentId: String(existing._id),
            alreadySettled: true,
            receiptId: existingReceipt ? String(existingReceipt._id) : undefined,
          };
        }
        throw conflict('Payment cannot be settled', 'PAYMENT_NOT_SETTLEABLE');
      }

      const charge = await CollectionChargeModel.findById(claimed.chargeId).session(session);
      if (!charge) throw notFound('Collection charge not found');
      const collection = await CollectionModel.findById(charge.collectionId).session(session);
      if (!collection) throw notFound('Collection not found');
      if (collection.status === 'CANCELLED') {
        throw badRequest('Collection is cancelled', 'COLLECTION_CANCELLED');
      }
      if (claimed.amountPaise > charge.outstandingPaise) {
        throw conflict('Payment exceeds outstanding collection amount', 'PAYMENT_EXCEEDS_OUTSTANDING');
      }

      charge.amountPaidPaise += claimed.amountPaise;
      charge.outstandingPaise = Math.max(
        0,
        charge.amountPaise + charge.adjustmentsPaise - charge.amountPaidPaise,
      );
      charge.status = deriveChargeStatus(charge.outstandingPaise, charge.amountPaidPaise);
      await charge.save({ session });

      collection.collectedPaise += claimed.amountPaise;
      await collection.save({ session });

      const receiptNumber = await nextCollectionReceiptNumber(input.societyId, session);
      const [receipt] = await CollectionReceiptModel.create(
        [
          {
            societyId: collection.societyId,
            collectionId: collection._id,
            chargeId: charge._id,
            paymentId: claimed._id,
            flatId: charge.flatId,
            receiptNumber,
            ownerUserId: charge.ownerUserId,
            ownerNameSnapshot: charge.ownerNameSnapshot,
            flatNumberSnapshot: charge.flatNumberSnapshot,
            wingCodeSnapshot: charge.wingCodeSnapshot,
            societyNameSnapshot: society.name,
            collectionTitleSnapshot: collection.title,
            collectionNumberSnapshot: collection.collectionNumber,
            amountPaise: claimed.amountPaise,
            paymentMethod: claimed.paymentMethod,
            transactionReference: input.gatewayPaymentId,
            paidAt: input.paidAt,
            generatedAt: new Date(),
          },
        ],
        { session },
      );

      await writeAuditLog(
        {
          action:
            input.source === 'offline'
              ? 'COLLECTION_PAYMENT_RECORDED_OFFLINE'
              : 'COLLECTION_PAYMENT_SUCCEEDED',
          actorUserId: input.actor?.userId,
          societyId: input.societyId,
          targetType: 'SpecialCollectionPayment',
          targetId: String(claimed._id),
          metadata: {
            receiptId: String(receipt._id),
            amountPaise: claimed.amountPaise,
            source: input.source,
          },
          ipAddress: input.actor?.ipAddress,
          userAgent: input.actor?.userAgent,
        },
        session,
      );
      await writeAuditLog(
        {
          action: 'COLLECTION_RECEIPT_GENERATED',
          actorUserId: input.actor?.userId,
          societyId: input.societyId,
          targetType: 'SpecialCollectionReceipt',
          targetId: String(receipt._id),
          metadata: { receiptNumber, paymentId: String(claimed._id) },
        },
        session,
      );

      return {
        paymentId: String(claimed._id),
        alreadySettled: false,
        receiptId: String(receipt._id),
        chargeStatus: charge.status,
        outstandingPaise: charge.outstandingPaise,
      };
    });
  } catch (error) {
    rethrowPaymentError(error);
  }
}

export async function verifyCollectionPayment(
  societyId: string,
  ownerUserId: string,
  input: { orderId: string; paymentId: string; signature: string },
  actor: Actor,
) {
  const payment = await CollectionPaymentModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    gatewayOrderId: input.orderId,
    ownerUserId,
  });
  if (!payment) throw notFound('Collection payment order not found');
  await assertFinancialAccess({
    userId: ownerUserId,
    societyId,
    flatId: String(payment.flatId),
  });
  const provider = getPaymentProvider();
  const valid = provider.verifyPaymentSignature({
    orderId: input.orderId,
    paymentId: input.paymentId,
    signature: input.signature,
  });
  if (!valid) {
    payment.status = 'FAILED';
    await payment.save();
    await writeAuditLog({
      action: 'COLLECTION_PAYMENT_FAILED',
      actorUserId: actor.userId,
      societyId,
      targetType: 'SpecialCollectionPayment',
      targetId: String(payment._id),
      metadata: { reason: 'INVALID_SIGNATURE' },
    });
    throw forbidden('Invalid payment signature', 'INVALID_GATEWAY_SIGNATURE');
  }
  return settleCollectionPayment({
    societyId,
    payment,
    gatewayPaymentId: input.paymentId,
    signatureVerified: true,
    paidAt: new Date(),
    actor,
    source: 'verify',
  });
}

export async function completeCollectionDemoPayment(
  societyId: string,
  ownerUserId: string,
  input: { orderId: string; outcome: 'success' | 'failure' },
  actor: Actor,
) {
  if (!isDemoPaymentsEnabled()) {
    throw forbidden(
      'Payment simulation is turned off.',
      'DEMO_PAYMENTS_DISABLED',
    );
  }
  const provider = getPaymentProvider();
  if (provider.name !== 'razorpay-mock') {
    throw badRequest(
      'Demo settlement requires the mock payment provider',
      'DEMO_PROVIDER_REQUIRED',
    );
  }
  const payment = await CollectionPaymentModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    gatewayOrderId: input.orderId,
    ownerUserId,
  });
  if (!payment) throw notFound('Collection payment order not found');
  await assertFinancialAccess({
    userId: ownerUserId,
    societyId,
    flatId: String(payment.flatId),
  });
  if (input.outcome === 'failure') {
    if (payment.status === 'SUCCESS') {
      const existingReceipt = await CollectionReceiptModel.findOne({ paymentId: payment._id }).lean();
      return {
        paymentId: String(payment._id),
        alreadySettled: true,
        receiptId: existingReceipt ? String(existingReceipt._id) : undefined,
      };
    }
    if (payment.status !== 'FAILED') {
      payment.status = 'FAILED';
      await payment.save();
      await writeAuditLog({
        action: 'COLLECTION_PAYMENT_FAILED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'SpecialCollectionPayment',
        targetId: String(payment._id),
        metadata: { reason: 'DEMO_FAILURE' },
      });
    }
    throw badRequest('Demo payment failed', 'DEMO_PAYMENT_FAILED');
  }
  return settleCollectionPayment({
    societyId,
    payment,
    gatewayPaymentId: `pay_demo_${String(payment._id)}`,
    signatureVerified: true,
    paidAt: new Date(),
    actor,
    source: 'verify',
  });
}

export async function handleCollectionGatewayWebhook(
  societyIdHint: string | undefined,
  event: WebhookEvent,
) {
  const payment = await CollectionPaymentModel.findOne({ gatewayOrderId: event.orderId });
  if (!payment) return null;
  if (societyIdHint && String(payment.societyId) !== societyIdHint) {
    throw forbidden('Society mismatch for webhook', 'SOCIETY_ISOLATION');
  }
  if (event.status && !['captured', 'authorized', 'SUCCESS', 'success'].includes(event.status)) {
    payment.status = 'FAILED';
    await payment.save();
    return { settled: false, status: 'FAILED', kind: 'collection' as const };
  }
  const result = await settleCollectionPayment({
    societyId: String(payment.societyId),
    payment,
    gatewayPaymentId: event.paymentId ?? `wh_${String(payment._id)}`,
    signatureVerified: true,
    paidAt: new Date(),
    source: 'webhook',
  });
  return { settled: true, kind: 'collection' as const, ...result, eventId: event.eventId };
}

export async function recordOfflineCollectionPayment(
  societyId: string,
  input: {
    chargeId: string;
    amountPaise: number;
    paidAt: Date;
    referenceNumber: string;
    notes?: string;
    idempotencyKey?: string;
  },
  actor: Actor,
) {
  const charge = await CollectionChargeModel.findOne({
    _id: parseObjectId(input.chargeId, 'chargeId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!charge) throw notFound('Collection charge not found');
  const collection = await requireActiveCollection(societyId, String(charge.collectionId));
  if (input.amountPaise > charge.outstandingPaise) {
    throw badRequest('Payment exceeds outstanding amount', 'PAYMENT_EXCEEDS_OUTSTANDING');
  }
  if (!collection.allowPartialPayment && input.amountPaise !== charge.outstandingPaise) {
    throw badRequest('Partial payment is not enabled for this collection', 'PARTIAL_PAYMENT_DISABLED');
  }
  if (input.idempotencyKey) {
    const existing = await CollectionPaymentModel.findOne({
      societyId,
      idempotencyKey: input.idempotencyKey,
    });
    if (existing) {
      const receipt = await CollectionReceiptModel.findOne({ paymentId: existing._id }).lean();
      return {
        paymentId: String(existing._id),
        alreadySettled: existing.status === 'SUCCESS',
        receiptId: receipt ? String(receipt._id) : undefined,
        status: existing.status,
      };
    }
  }

  const payment = await withTransaction(async (session) => {
    const paymentNumber = await nextCollectionPaymentNumber(societyId, session);
    const [doc] = await CollectionPaymentModel.create(
      [
        {
          societyId,
          collectionId: collection._id,
          chargeId: charge._id,
          flatId: charge.flatId,
          ownerUserId: charge.ownerUserId,
          paymentNumber,
          amountPaise: input.amountPaise,
          paymentMethod: 'OFFLINE',
          status: 'PENDING',
          referenceNumber: input.referenceNumber,
          notes: input.notes,
          createdBy: actor.userId,
          idempotencyKey: input.idempotencyKey,
          gatewayPaymentId: `offline_${input.referenceNumber}`,
        },
      ],
      { session },
    );
    return doc;
  });

  return settleCollectionPayment({
    societyId,
    payment,
    gatewayPaymentId: `offline_${input.referenceNumber}`,
    signatureVerified: true,
    paidAt: input.paidAt,
    actor,
    source: 'offline',
  });
}

export async function listCollectionPayments(
  societyId: string,
  query: {
    collectionId?: string;
    chargeId?: string;
    ownerUserId?: string;
    status?: string;
    page?: number;
    limit?: number;
  },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.collectionId) filter.collectionId = parseObjectId(query.collectionId, 'collectionId');
  if (query.chargeId) filter.chargeId = parseObjectId(query.chargeId, 'chargeId');
  if (query.ownerUserId) filter.ownerUserId = parseObjectId(query.ownerUserId, 'ownerUserId');
  if (query.status) filter.status = query.status;

  const [total, rows] = await Promise.all([
    CollectionPaymentModel.countDocuments(filter),
    CollectionPaymentModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);
  const receipts = rows.length
    ? await CollectionReceiptModel.find({ paymentId: { $in: rows.map((row) => row._id) } })
        .select('_id paymentId')
        .lean()
    : [];
  const chargeIds = [...new Set(rows.map((row) => String(row.chargeId)))];
  const charges = chargeIds.length
    ? await CollectionChargeModel.find({ _id: { $in: chargeIds } })
        .select('_id wingCodeSnapshot flatNumberSnapshot')
        .lean()
    : [];
  const receiptByPayment = new Map(receipts.map((row) => [String(row.paymentId), String(row._id)]));
  const chargeById = new Map(charges.map((row) => [String(row._id), row]));
  return {
    items: rows.map((row) => {
      const charge = chargeById.get(String(row.chargeId));
      return serializePayment(
        { ...row, receiptId: receiptByPayment.get(String(row._id)) },
        {
          wingCodeSnapshot: charge?.wingCodeSnapshot,
          flatNumberSnapshot: charge?.flatNumberSnapshot,
        },
      );
    }),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getCollectionReceipt(
  societyId: string,
  receiptId: string,
  options?: { ownerUserId?: string },
) {
  const receipt = await CollectionReceiptModel.findOne({
    _id: parseObjectId(receiptId, 'receiptId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!receipt) throw notFound('Receipt not found');
  if (options?.ownerUserId && String(receipt.ownerUserId) !== options.ownerUserId) {
    throw forbidden('Receipt access denied', 'RECEIPT_ACCESS_DENIED');
  }
  const pdf = buildReceiptPdf({
    receiptNumber: receipt.receiptNumber,
    societyName: receipt.societyNameSnapshot,
    flatNumber: receipt.flatNumberSnapshot,
    wingCode: receipt.wingCodeSnapshot,
    ownerName: receipt.ownerNameSnapshot,
    amountPaise: receipt.amountPaise,
    paymentMethod: receipt.paymentMethod,
    transactionReference: receipt.transactionReference,
    paidAt: receipt.paidAt,
    description: receipt.collectionTitleSnapshot
      ? `One-time collection - ${receipt.collectionTitleSnapshot}`
      : 'One-time collection',
    collectionNumber: receipt.collectionNumberSnapshot,
    collectionTitle: receipt.collectionTitleSnapshot,
    paymentStatus: 'SUCCESSFUL',
  });
  return {
    receipt: {
      id: String(receipt._id),
      receiptNumber: receipt.receiptNumber,
      collectionId: String(receipt.collectionId),
      chargeId: String(receipt.chargeId),
      paymentId: String(receipt.paymentId),
      flatId: String(receipt.flatId),
      amountPaise: receipt.amountPaise,
      paymentMethod: receipt.paymentMethod,
      paidAt: receipt.paidAt.toISOString(),
      generatedAt: receipt.generatedAt.toISOString(),
      ownerNameSnapshot: receipt.ownerNameSnapshot,
      flatNumberSnapshot: receipt.flatNumberSnapshot,
      wingCodeSnapshot: receipt.wingCodeSnapshot,
      flatLabel: formatFlatLabel(receipt.wingCodeSnapshot, receipt.flatNumberSnapshot),
      collectionTitleSnapshot: receipt.collectionTitleSnapshot,
      collectionNumberSnapshot: receipt.collectionNumberSnapshot,
      transactionReference: receipt.transactionReference,
    },
    pdfBase64: pdf.toString('base64'),
  };
}

export async function getCollectionReceiptForPayment(
  societyId: string,
  paymentId: string,
  options?: { ownerUserId?: string },
) {
  const payment = await CollectionPaymentModel.findOne({
    _id: parseObjectId(paymentId, 'paymentId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!payment) throw notFound('Payment not found');
  if (options?.ownerUserId && String(payment.ownerUserId) !== options.ownerUserId) {
    throw forbidden('Payment access denied', 'PAYMENT_ACCESS_DENIED');
  }
  if (payment.status !== 'SUCCESS') {
    throw badRequest(
      'Receipts are only available for confirmed successful payments',
      'RECEIPT_NOT_AVAILABLE',
    );
  }
  const existing = await CollectionReceiptModel.findOne({ paymentId: payment._id });
  if (!existing) throw notFound('Receipt not found');
  return getCollectionReceipt(societyId, String(existing._id), options);
}
