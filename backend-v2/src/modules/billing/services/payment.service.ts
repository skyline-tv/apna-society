import type { ClientSession } from 'mongoose';
import { getEnv, isLivePaymentsEnabled } from '../../../config/env';
import { withTransaction } from '../../../database/connection';
import {
  AppError,
  badRequest,
  conflict,
  forbidden,
  notFound,
} from '../../../shared/errors/app-error';
import { isDuplicateKeyError, mapMongoWriteError } from '../../../utils/mongo-errors';
import { parseObjectId } from '../../../utils/object-id';
import { writeAuditLog } from '../../auth/services/audit.service';
import { notifyBusinessEvent } from '../../notifications/services/business-notify.service';
import { SocietyModel } from '../../society/models/society.model';
import { assertFinancialAccess } from '../../users/services/access-control.service';
import { BillModel } from '../models/bill.model';
import { PaymentModel } from '../models/payment.model';
import {
  appendPrincipalEvent,
  PrincipalLedgerModel,
} from '../models/principal-ledger.model';
import { ReceiptModel } from '../models/receipt.model';
import { nextSequence } from '../models/sequence.model';
import { getPaymentProvider } from '../providers/payment-provider.factory';
import { startOfCivilDay } from '../utils/billing-calendar';
import { computeInterestForBillWithEvents, getBillInterest } from './interest.service';
import { assertBillFinancialInvariants } from './financial-invariants.service';
import { buildReceiptPdf } from './pdf.service';

type Actor = { userId: string; ipAddress?: string; userAgent?: string };

function maybeForceTransactionFailure(step: string): void {
  if (process.env.NODE_ENV !== 'test') return;
  if (process.env.TEST_FORCED_TRANSACTION_FAILURE === step) {
    throw new Error(`TEST_FORCED_TRANSACTION_FAILURE:${step}`);
  }
}

function rethrowPaymentError(error: unknown): never {
  if (
    error instanceof Error &&
    error.message.startsWith('TEST_FORCED_TRANSACTION_FAILURE')
  ) {
    throw error;
  }
  if (error instanceof AppError) throw error;
  if (isDuplicateKeyError(error)) {
    throw conflict('Duplicate payment settlement', 'DUPLICATE_PAYMENT');
  }
  mapMongoWriteError(error, 'Duplicate payment settlement');
}

async function nextPaymentNumber(societyId: string, session: ClientSession): Promise<string> {
  const year = new Date().getUTCFullYear();
  const seq = await nextSequence(societyId, `pay-${year}`, session);
  return `PAY-${year}-${seq.toString().padStart(6, '0')}`;
}

async function nextReceiptNumber(societyId: string, session: ClientSession): Promise<string> {
  const year = new Date().getUTCFullYear();
  const seq = await nextSequence(societyId, `rcpt-${year}`, session);
  return `RCPT-${year}-${seq.toString().padStart(6, '0')}`;
}

function deriveBillStatus(bill: {
  outstandingPrincipalPaise: number;
  amountPaidPaise: number;
  dueDate: Date;
  status: string;
}): 'PAID' | 'PARTIALLY_PAID' | 'OVERDUE' | 'ISSUED' {
  if (bill.outstandingPrincipalPaise <= 0) return 'PAID';
  const overdue = Date.now() > bill.dueDate.getTime();
  if (bill.amountPaidPaise > 0) return overdue ? 'OVERDUE' : 'PARTIALLY_PAID';
  return overdue ? 'OVERDUE' : 'ISSUED';
}

/**
 * Allocation policy:
 * 1) Apply payment to outstanding principal first.
 * 2) Any remainder is recorded as interest allocation (explicit, not mixed into principal).
 * Interest is calculated separately and is never compounded into principal.
 */
export function allocatePayment(
  amountPaise: number,
  outstandingPrincipalPaise: number,
  accruedInterestPaise: number,
): { toPrincipal: number; toInterest: number } {
  const toPrincipal = Math.min(amountPaise, outstandingPrincipalPaise);
  const remainder = amountPaise - toPrincipal;
  const toInterest = Math.min(remainder, accruedInterestPaise);
  return { toPrincipal, toInterest };
}

export async function createPaymentOrder(
  societyId: string,
  billId: string,
  ownerUserId: string,
  actor: Actor,
) {
  const bill = await BillModel.findOne({
    _id: parseObjectId(billId, 'billId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!bill) throw notFound('Bill not found');
  if (bill.status === 'CANCELLED') throw badRequest('Bill is cancelled', 'BILL_CANCELLED');
  if (bill.outstandingPrincipalPaise <= 0) {
    throw badRequest('Bill is already fully paid', 'BILL_ALREADY_PAID');
  }
  if (!bill.ownerUserId || String(bill.ownerUserId) !== ownerUserId) {
    throw forbidden('Only the bill owner may initiate payment', 'NOT_BILL_OWNER');
  }

  await assertFinancialAccess({
    userId: ownerUserId,
    societyId,
    flatId: String(bill.flatId),
  });

  await getBillInterest(societyId, billId);

  // Charge outstanding principal only (interest settled separately / optionally via remainder).
  const amountPaise = bill.outstandingPrincipalPaise;
  const provider = getPaymentProvider();
  const order = await provider.createOrder({
    amountPaise,
    receipt: bill.billNumber,
    notes: { billId: String(bill._id), societyId },
  });

  const payment = await withTransaction(async (session) => {
    const paymentNumber = await nextPaymentNumber(societyId, session);
    const [doc] = await PaymentModel.create(
      [
        {
          societyId,
          billId: bill._id,
          flatId: bill.flatId,
          ownerUserId: bill.ownerUserId,
          paymentNumber,
          amountPaise,
          allocatedToPrincipalPaise: 0,
          allocatedToInterestPaise: 0,
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
        action: 'PAYMENT_INITIATED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'Payment',
        targetId: String(doc._id),
        metadata: {
          billId: String(bill._id),
          amountPaise,
          gatewayOrderId: order.orderId,
        },
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
    billId: String(bill._id),
    amountPaise,
    order,
  };
}

/** Exported for integration tests that force settlement rollback scenarios. */
export async function settleSuccessfulPayment(input: {
  societyId: string;
  payment: InstanceType<typeof PaymentModel>;
  gatewayPaymentId: string;
  signatureVerified: boolean;
  paidAt: Date;
  actor?: Actor;
  source: 'verify' | 'webhook' | 'offline';
}) {
  if (input.payment.status === 'SUCCESS') {
    const existingReceipt = await ReceiptModel.findOne({ paymentId: input.payment._id }).lean();
    return {
      paymentId: String(input.payment._id),
      alreadySettled: true,
      receiptId: existingReceipt ? String(existingReceipt._id) : undefined,
    };
  }

  const society = await SocietyModel.findById(input.societyId).lean();
  if (!society) throw notFound('Society not found');
  const timeZone = society.config?.timezone ?? 'Asia/Kolkata';

  try {
    return await withTransaction(async (session) => {
      const claimed = await PaymentModel.findOneAndUpdate(
        {
          _id: input.payment._id,
          status: { $in: ['PENDING', 'FAILED'] },
        },
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
        const existing = await PaymentModel.findById(input.payment._id).session(session);
        if (existing?.status === 'SUCCESS') {
          const existingReceipt = await ReceiptModel.findOne({
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

      maybeForceTransactionFailure('payment_settle');

      const bill = await BillModel.findById(claimed.billId).session(session);
      if (!bill) throw notFound('Bill not found');

      const rateSnapshot = bill.monthlyRatePaise;
      const ownerSnapshot = String(bill.ownerUserId);

      const ledgerBefore = await PrincipalLedgerModel.find({ billId: bill._id })
        .session(session)
        .sort({ effectiveAt: 1, createdAt: 1 })
        .lean();
      const interest = computeInterestForBillWithEvents(
        bill,
        ledgerBefore,
        input.paidAt,
        timeZone,
      );
      const allocation = allocatePayment(
        claimed.amountPaise,
        bill.outstandingPrincipalPaise,
        interest.accruedInterestPaise,
      );

      if (allocation.toPrincipal > bill.outstandingPrincipalPaise) {
        throw conflict('Payment allocation exceeds outstanding principal', 'ALLOCATION_OVERFLOW');
      }

      bill.amountPaidPaise += allocation.toPrincipal;
      bill.outstandingPrincipalPaise = bill.outstandingPrincipalPaise - allocation.toPrincipal;
      if (bill.outstandingPrincipalPaise < 0) {
        throw conflict('Outstanding principal would become negative', 'NEGATIVE_PRINCIPAL');
      }
      bill.interestAccruedPaise = interest.accruedInterestPaise;
      bill.interestCalculatedAsOf = input.paidAt;
      bill.status = deriveBillStatus(bill);
      bill.updatedBy = input.actor?.userId
        ? parseObjectId(input.actor.userId, 'userId')
        : bill.updatedBy;
      await bill.save({ session });

      if (bill.monthlyRatePaise !== rateSnapshot || String(bill.ownerUserId) !== ownerSnapshot) {
        throw conflict('Bill historical snapshots were mutated', 'SNAPSHOT_MUTATION');
      }

      claimed.allocatedToPrincipalPaise = allocation.toPrincipal;
      claimed.allocatedToInterestPaise = allocation.toInterest;
      await claimed.save({ session });

      if (allocation.toPrincipal > 0) {
        await appendPrincipalEvent(
          {
            societyId: input.societyId,
            billId: bill._id,
            eventType: 'PAYMENT_ALLOCATION',
            deltaPrincipalPaise: -allocation.toPrincipal,
            principalAfterPaise: bill.outstandingPrincipalPaise,
            effectiveAt: startOfCivilDay(input.paidAt, timeZone),
            sourceType: 'payment',
            sourceId: String(claimed._id),
            paymentId: claimed._id,
            notes: `Settlement via ${input.source}`,
          },
          session,
        );
      }

      assertBillFinancialInvariants({
        baseAmountPaise: bill.baseAmountPaise,
        additionalServicesTotalPaise: bill.additionalServicesTotalPaise,
        adjustmentsPaise: bill.adjustmentsPaise,
        totalAmountPaise: bill.totalAmountPaise,
        amountPaidPaise: bill.amountPaidPaise,
        outstandingPrincipalPaise: bill.outstandingPrincipalPaise,
        paymentAllocatedPrincipalPaise: allocation.toPrincipal,
        paymentAmountPaise: claimed.amountPaise,
      });

      const receiptNumber = await nextReceiptNumber(input.societyId, session);
      const [receipt] = await ReceiptModel.create(
        [
          {
            societyId: bill.societyId,
            billId: bill._id,
            paymentId: claimed._id,
            flatId: bill.flatId,
            receiptNumber,
            ownerUserId: bill.ownerUserId,
            ownerNameSnapshot: bill.ownerNameSnapshot,
            ownerEmailSnapshot: bill.ownerEmailSnapshot,
            flatNumberSnapshot: bill.flatNumberSnapshot,
            wingCodeSnapshot: bill.wingCodeSnapshot,
            societyNameSnapshot: society.name,
            amountPaise: claimed.amountPaise,
            paymentMethod: claimed.paymentMethod,
            transactionReference: input.gatewayPaymentId,
            paidAt: input.paidAt,
            generatedAt: new Date(),
            pdfGenerated: true,
          },
        ],
        { session },
      );

      if (receipt.amountPaise !== claimed.amountPaise) {
        throw conflict('Receipt amount does not match payment', 'RECEIPT_AMOUNT_MISMATCH');
      }

      await writeAuditLog(
        {
          action: input.source === 'offline' ? 'PAYMENT_RECORDED_OFFLINE' : 'PAYMENT_SUCCEEDED',
          actorUserId: input.actor?.userId,
          societyId: input.societyId,
          targetType: 'Payment',
          targetId: String(claimed._id),
          metadata: {
            billId: String(bill._id),
            receiptId: String(receipt._id),
            amountPaise: claimed.amountPaise,
            allocatedToPrincipalPaise: allocation.toPrincipal,
            allocatedToInterestPaise: allocation.toInterest,
            source: input.source,
          },
          ipAddress: input.actor?.ipAddress,
          userAgent: input.actor?.userAgent,
        },
        session,
      );

      await writeAuditLog(
        {
          action: 'RECEIPT_GENERATED',
          actorUserId: input.actor?.userId,
          societyId: input.societyId,
          targetType: 'Receipt',
          targetId: String(receipt._id),
          metadata: { receiptNumber, paymentId: String(claimed._id) },
        },
        session,
      );

      return {
        paymentId: String(claimed._id),
        alreadySettled: false,
        receiptId: String(receipt._id),
        billStatus: bill.status,
        outstandingPrincipalPaise: bill.outstandingPrincipalPaise,
        ownerUserId: bill.ownerUserId ? String(bill.ownerUserId) : undefined,
      };
    });
  } catch (error) {
    rethrowPaymentError(error);
  }
}

async function settleAndNotify(input: Parameters<typeof settleSuccessfulPayment>[0]) {
  const result = await settleSuccessfulPayment(input);
  // Invalidate only after settlement transaction committed.
  if (result && !result.alreadySettled) {
    const { invalidateFinancialCaches } = await import('../../../cache/cache-invalidation');
    await invalidateFinancialCaches(input.societyId);
  }
  const ownerUserId =
    result && 'ownerUserId' in result ? (result as { ownerUserId?: string }).ownerUserId : undefined;
  if (result && !result.alreadySettled && ownerUserId) {
    await notifyBusinessEvent({
      societyId: input.societyId,
      recipientUserId: ownerUserId,
      type: 'PAYMENT_SUCCESS',
      title: 'Payment successful',
      body: 'Your maintenance payment was recorded successfully',
      relatedEntityType: 'Payment',
      relatedEntityId: result.paymentId,
      idempotencyKey: `PAYMENT_SUCCESS:${result.paymentId}`,
    });
  }
  return result;
}

export async function verifyResidentPayment(
  societyId: string,
  ownerUserId: string,
  input: { orderId: string; paymentId: string; signature: string },
  actor: Actor,
) {
  const payment = await PaymentModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    gatewayOrderId: input.orderId,
    ownerUserId,
  });
  if (!payment) throw notFound('Payment order not found');

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
      action: 'PAYMENT_FAILED',
      actorUserId: actor.userId,
      societyId,
      targetType: 'Payment',
      targetId: String(payment._id),
      metadata: { reason: 'INVALID_SIGNATURE' },
    });
    if (payment.ownerUserId) await notifyBusinessEvent({
      societyId,
      recipientUserId: String(payment.ownerUserId),
      type: 'PAYMENT_FAILED',
      title: 'Payment failed',
      body: 'Your payment could not be verified',
      relatedEntityType: 'Payment',
      relatedEntityId: String(payment._id),
      idempotencyKey: `PAYMENT_FAILED:${String(payment._id)}:INVALID_SIGNATURE`,
    });
    throw forbidden('Invalid payment signature', 'INVALID_GATEWAY_SIGNATURE');
  }

  return settleAndNotify({
    societyId,
    payment,
    gatewayPaymentId: input.paymentId,
    signatureVerified: true,
    paidAt: new Date(),
    actor,
    source: 'verify',
  });
}

/**
 * Completes a mock/demo checkout on the server.
 * Clients must never hold gateway HMAC secrets — only the mock provider path
 * in non-production may settle without a client-supplied signature.
 */
export async function completeDemoResidentPayment(
  societyId: string,
  ownerUserId: string,
  input: { orderId: string; outcome: 'success' | 'failure' },
  actor: Actor,
) {
  if (isLivePaymentsEnabled()) {
    throw forbidden(
      'Demo payments are disabled when live Razorpay is enabled',
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

  const payment = await PaymentModel.findOne({
    societyId: parseObjectId(societyId, 'societyId'),
    gatewayOrderId: input.orderId,
    ownerUserId,
  });
  if (!payment) throw notFound('Payment order not found');

  await assertFinancialAccess({
    userId: ownerUserId,
    societyId,
    flatId: String(payment.flatId),
  });

  if (input.outcome === 'failure') {
    if (payment.status === 'SUCCESS') {
      const existingReceipt = await ReceiptModel.findOne({ paymentId: payment._id }).lean();
      return {
        paymentId: String(payment._id),
        alreadySettled: true,
        receiptId: existingReceipt ? String(existingReceipt._id) : undefined,
        billStatus: undefined,
        outstandingPrincipalPaise: undefined,
        ownerUserId: payment.ownerUserId ? String(payment.ownerUserId) : undefined,
      };
    }
    if (payment.status !== 'FAILED') {
      payment.status = 'FAILED';
      await payment.save();
      await writeAuditLog({
        action: 'PAYMENT_FAILED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'Payment',
        targetId: String(payment._id),
        metadata: { reason: 'DEMO_FAILURE', source: 'demo-complete' },
      });
      if (payment.ownerUserId) await notifyBusinessEvent({
        societyId,
        recipientUserId: String(payment.ownerUserId),
        type: 'PAYMENT_FAILED',
        title: 'Payment failed',
        body: 'Your demo payment was marked as failed',
        relatedEntityType: 'Payment',
        relatedEntityId: String(payment._id),
        idempotencyKey: `PAYMENT_FAILED:${String(payment._id)}:DEMO_FAILURE`,
      });
    }
    throw badRequest('Demo payment failed', 'DEMO_PAYMENT_FAILED');
  }

  const gatewayPaymentId = `pay_demo_${String(payment._id)}`;
  return settleAndNotify({
    societyId,
    payment,
    gatewayPaymentId,
    signatureVerified: true,
    paidAt: new Date(),
    actor,
    source: 'verify',
  });
}

export async function handleGatewayWebhook(
  societyIdHint: string | undefined,
  rawBody: string,
  signature: string,
  payload: unknown,
) {
  const provider = getPaymentProvider();
  if (!provider.verifyWebhookSignature(rawBody, signature)) {
    throw forbidden('Invalid webhook signature', 'INVALID_WEBHOOK_SIGNATURE');
  }

  const event = provider.parseWebhook(payload);
  if (!event.orderId || !event.paymentId) {
    throw badRequest('Webhook missing order/payment identifiers', 'INVALID_WEBHOOK');
  }

  const payment = await PaymentModel.findOne({ gatewayOrderId: event.orderId });
  if (!payment) {
    throw notFound('Payment order not found for webhook');
  }
  if (societyIdHint && String(payment.societyId) !== societyIdHint) {
    throw forbidden('Society mismatch for webhook', 'SOCIETY_ISOLATION');
  }

  if (event.status && !['captured', 'authorized', 'SUCCESS', 'success'].includes(event.status)) {
    payment.status = 'FAILED';
    await payment.save();
    await writeAuditLog({
      action: 'PAYMENT_FAILED',
      societyId: String(payment.societyId),
      targetType: 'Payment',
      targetId: String(payment._id),
      metadata: { gatewayStatus: event.status, eventId: event.eventId },
    });
    if (payment.ownerUserId) await notifyBusinessEvent({
      societyId: String(payment.societyId),
      recipientUserId: String(payment.ownerUserId),
      type: 'PAYMENT_FAILED',
      title: 'Payment failed',
      body: 'Your payment was not successful',
      relatedEntityType: 'Payment',
      relatedEntityId: String(payment._id),
      idempotencyKey: `PAYMENT_FAILED:${String(payment._id)}:${event.eventId ?? event.status}`,
    });
    return { settled: false, status: 'FAILED' };
  }

  const result = await settleAndNotify({
    societyId: String(payment.societyId),
    payment,
    gatewayPaymentId: event.paymentId,
    signatureVerified: true,
    paidAt: new Date(),
    source: 'webhook',
  });

  return { settled: true, ...result, eventId: event.eventId };
}

export async function recordOfflinePayment(
  societyId: string,
  input: {
    billId: string;
    amountPaise: number;
    paidAt: Date;
    paymentMethod?: 'OFFLINE';
    referenceNumber: string;
    notes?: string;
    idempotencyKey?: string;
  },
  actor: Actor,
) {
  if (!getEnv().OFFLINE_PAYMENTS_ENABLED) {
    throw forbidden('Offline payments are disabled', 'OFFLINE_PAYMENTS_DISABLED');
  }
  if (input.amountPaise <= 0) {
    throw badRequest('amountPaise must be positive', 'INVALID_AMOUNT');
  }

  const bill = await BillModel.findOne({
    _id: parseObjectId(input.billId, 'billId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!bill) throw notFound('Bill not found');
  if (bill.status === 'CANCELLED') throw badRequest('Bill is cancelled', 'BILL_CANCELLED');

  if (input.idempotencyKey) {
    const existing = await PaymentModel.findOne({
      societyId,
      idempotencyKey: input.idempotencyKey,
    });
    if (existing) {
      return {
        paymentId: String(existing._id),
        alreadySettled: existing.status === 'SUCCESS',
        status: existing.status,
      };
    }
  }

  const payment = await withTransaction(async (session) => {
    const paymentNumber = await nextPaymentNumber(societyId, session);
    const [doc] = await PaymentModel.create(
      [
        {
          societyId,
          billId: bill._id,
          flatId: bill.flatId,
          ownerUserId: bill.ownerUserId,
          paymentNumber,
          amountPaise: input.amountPaise,
          allocatedToPrincipalPaise: 0,
          allocatedToInterestPaise: 0,
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

  return settleAndNotify({
    societyId,
    payment,
    gatewayPaymentId: `offline_${input.referenceNumber}`,
    signatureVerified: true,
    paidAt: input.paidAt,
    actor,
    source: 'offline',
  });
}

export async function listPayments(
  societyId: string,
  query: {
    status?: string;
    billId?: string;
    ownerUserId?: string;
    page?: number;
    limit?: number;
  },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.status) filter.status = query.status;
  if (query.billId) filter.billId = parseObjectId(query.billId, 'billId');
  if (query.ownerUserId) filter.ownerUserId = parseObjectId(query.ownerUserId, 'ownerUserId');

  const [total, rows] = await Promise.all([
    PaymentModel.countDocuments(filter),
    PaymentModel.find(filter)
      .sort({ createdAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((row) => ({
      id: String(row._id),
      paymentNumber: row.paymentNumber,
      billId: String(row.billId),
      flatId: String(row.flatId),
      ownerUserId: row.ownerUserId ? String(row.ownerUserId) : undefined,
      amountPaise: row.amountPaise,
      allocatedToPrincipalPaise: row.allocatedToPrincipalPaise,
      allocatedToInterestPaise: row.allocatedToInterestPaise,
      paymentMethod: row.paymentMethod,
      status: row.status,
      paidAt: row.paidAt?.toISOString(),
      referenceNumber: row.referenceNumber,
      gatewayOrderId: row.gatewayOrderId,
      gatewayPaymentId: row.gatewayPaymentId,
    })),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function getPayment(societyId: string, paymentId: string) {
  const payment = await PaymentModel.findOne({
    _id: parseObjectId(paymentId, 'paymentId'),
    societyId: parseObjectId(societyId, 'societyId'),
  }).lean();
  if (!payment) throw notFound('Payment not found');
  return {
    id: String(payment._id),
    paymentNumber: payment.paymentNumber,
    billId: String(payment.billId),
    amountPaise: payment.amountPaise,
    status: payment.status,
    paymentMethod: payment.paymentMethod,
    paidAt: payment.paidAt?.toISOString(),
    allocatedToPrincipalPaise: payment.allocatedToPrincipalPaise,
    allocatedToInterestPaise: payment.allocatedToInterestPaise,
  };
}

export async function getReceipt(
  societyId: string,
  receiptId: string,
  options?: { ownerUserId?: string },
) {
  const receipt = await ReceiptModel.findOne({
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
  });

  return {
    receipt: {
      id: String(receipt._id),
      receiptNumber: receipt.receiptNumber,
      billId: String(receipt.billId),
      paymentId: String(receipt.paymentId),
      flatId: String(receipt.flatId),
      amountPaise: receipt.amountPaise,
      paymentMethod: receipt.paymentMethod,
      paidAt: receipt.paidAt.toISOString(),
      generatedAt: receipt.generatedAt.toISOString(),
      ownerNameSnapshot: receipt.ownerNameSnapshot,
      flatNumberSnapshot: receipt.flatNumberSnapshot,
      wingCodeSnapshot: receipt.wingCodeSnapshot,
      transactionReference: receipt.transactionReference,
    },
    pdfBase64: pdf.toString('base64'),
  };
}

export async function listReceipts(
  societyId: string,
  query: { ownerUserId?: string; page?: number; limit?: number },
) {
  const page = query.page ?? 1;
  const limit = query.limit ?? 20;
  const filter: Record<string, unknown> = {
    societyId: parseObjectId(societyId, 'societyId'),
  };
  if (query.ownerUserId) filter.ownerUserId = parseObjectId(query.ownerUserId, 'ownerUserId');

  const [total, rows] = await Promise.all([
    ReceiptModel.countDocuments(filter),
    ReceiptModel.find(filter)
      .sort({ generatedAt: -1 })
      .skip((page - 1) * limit)
      .limit(limit)
      .lean(),
  ]);

  return {
    items: rows.map((row) => ({
      id: String(row._id),
      receiptNumber: row.receiptNumber,
      billId: String(row.billId),
      paymentId: String(row.paymentId),
      amountPaise: row.amountPaise,
      paidAt: row.paidAt.toISOString(),
      flatNumberSnapshot: row.flatNumberSnapshot,
      wingCodeSnapshot: row.wingCodeSnapshot,
    })),
    pagination: {
      page,
      limit,
      total,
      totalPages: total === 0 ? 0 : Math.ceil(total / limit),
    },
  };
}

export async function refundPayment(
  societyId: string,
  paymentId: string,
  reason: string,
  actor: Actor,
) {
  const payment = await PaymentModel.findOne({
    _id: parseObjectId(paymentId, 'paymentId'),
    societyId: parseObjectId(societyId, 'societyId'),
  });
  if (!payment) throw notFound('Payment not found');
  if (payment.status !== 'SUCCESS') {
    throw badRequest('Only successful payments can be refunded', 'INVALID_PAYMENT_STATUS');
  }

  const society = await SocietyModel.findById(societyId).lean();
  const timeZone = society?.config?.timezone ?? 'Asia/Kolkata';
  const refundedAt = new Date();

  await withTransaction(async (session) => {
    const claimed = await PaymentModel.findOneAndUpdate(
      { _id: payment._id, status: 'SUCCESS' },
      {
        $set: {
          status: 'REFUNDED',
          refundedAt,
          refundReason: reason,
        },
      },
      { session, new: true },
    );
    if (!claimed) {
      throw conflict('Payment already refunded or not refundable', 'PAYMENT_NOT_REFUNDABLE');
    }

    const bill = await BillModel.findById(claimed.billId).session(session);
    if (!bill) throw notFound('Bill not found');

    const rateSnapshot = bill.monthlyRatePaise;
    const ownerSnapshot = String(bill.ownerUserId);
    const restoredPrincipal = claimed.allocatedToPrincipalPaise;

    bill.amountPaidPaise = Math.max(0, bill.amountPaidPaise - restoredPrincipal);
    bill.outstandingPrincipalPaise += restoredPrincipal;
    bill.status = deriveBillStatus(bill);
    await bill.save({ session });

    if (bill.monthlyRatePaise !== rateSnapshot || String(bill.ownerUserId) !== ownerSnapshot) {
      throw conflict('Bill historical snapshots were mutated', 'SNAPSHOT_MUTATION');
    }

    if (restoredPrincipal > 0) {
      await appendPrincipalEvent(
        {
          societyId,
          billId: bill._id,
          eventType: 'REFUND_RESTORATION',
          deltaPrincipalPaise: restoredPrincipal,
          principalAfterPaise: bill.outstandingPrincipalPaise,
          effectiveAt: startOfCivilDay(refundedAt, timeZone),
          sourceType: 'refund',
          sourceId: String(claimed._id),
          paymentId: claimed._id,
          notes: reason,
        },
        session,
      );
    }

    assertBillFinancialInvariants({
      baseAmountPaise: bill.baseAmountPaise,
      additionalServicesTotalPaise: bill.additionalServicesTotalPaise,
      adjustmentsPaise: bill.adjustmentsPaise,
      totalAmountPaise: bill.totalAmountPaise,
      amountPaidPaise: bill.amountPaidPaise,
      outstandingPrincipalPaise: bill.outstandingPrincipalPaise,
    });

    await writeAuditLog(
      {
        action: 'PAYMENT_REFUNDED',
        actorUserId: actor.userId,
        societyId,
        targetType: 'Payment',
        targetId: paymentId,
        metadata: {
          reason,
          amountPaise: claimed.amountPaise,
          restoredPrincipalPaise: restoredPrincipal,
          allocatedToInterestPaise: claimed.allocatedToInterestPaise,
          billId: String(bill._id),
          refundedAt: refundedAt.toISOString(),
        },
        ipAddress: actor.ipAddress,
        userAgent: actor.userAgent,
      },
      session,
    );
  });

  const { invalidateFinancialCaches } = await import('../../../cache/cache-invalidation');
  await invalidateFinancialCaches(societyId);

  return { paymentId, status: 'REFUNDED' as const, refundedAt: refundedAt.toISOString() };
}
