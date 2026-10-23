import type { Request, Response } from 'express';
import { forbidden } from '../../../shared/errors/app-error';
import { assertFinancialAccess } from '../../users/services/access-control.service';
import { CollectionChargeModel } from '../models/collection-charge.model';
import { parseObjectId } from '../../../utils/object-id';
import {
  getResidentCollectionCharge,
  listResidentCollectionCharges,
} from '../services/collection.service';
import {
  completeCollectionDemoPayment,
  createCollectionPaymentOrder,
  getCollectionReceipt,
  getCollectionReceiptForPayment,
  listCollectionPayments,
  verifyCollectionPayment,
} from '../services/collection-payment.service';
import type {
  CompleteCollectionDemoInput,
  CreateCollectionPaymentOrderInput,
  VerifyCollectionPaymentInput,
} from '../validators/collection.validators';

function societyId(req: Request): string {
  return String(req.societyId);
}

function actorFrom(req: Request) {
  return {
    userId: req.user!.id,
    ipAddress: req.ip,
    userAgent: req.get('user-agent') ?? undefined,
  };
}

export async function residentListCollectionsHandler(req: Request, res: Response): Promise<void> {
  const data = await listResidentCollectionCharges(societyId(req), req.user!.id);
  res.json({ success: true, data });
}

export async function residentGetChargeHandler(req: Request, res: Response): Promise<void> {
  const data = await getResidentCollectionCharge(
    societyId(req),
    String(req.params.chargeId),
    req.user!.id,
  );
  await assertFinancialAccess({
    userId: req.user!.id,
    societyId: societyId(req),
    flatId: data.flatId,
  });
  res.json({ success: true, data });
}

export async function residentCreatePaymentOrderHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const body = req.body as CreateCollectionPaymentOrderInput;
  const data = await createCollectionPaymentOrder(
    societyId(req),
    String(req.params.chargeId),
    req.user!.id,
    body.amountPaise,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function residentVerifyCollectionPaymentHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const data = await verifyCollectionPayment(
    societyId(req),
    req.user!.id,
    req.body as VerifyCollectionPaymentInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function residentDemoCollectionPaymentHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const data = await completeCollectionDemoPayment(
    societyId(req),
    req.user!.id,
    req.body as CompleteCollectionDemoInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function residentListCollectionPaymentsHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const data = await listCollectionPayments(societyId(req), {
    ownerUserId: req.user!.id,
    chargeId: req.query.chargeId ? String(req.query.chargeId) : undefined,
    status: req.query.status ? String(req.query.status) : undefined,
    page: Number(req.query.page ?? 1),
    limit: Number(req.query.limit ?? 20),
  });
  res.json({ success: true, data });
}

export async function residentCollectionReceiptHandler(req: Request, res: Response): Promise<void> {
  const data = await getCollectionReceipt(societyId(req), String(req.params.receiptId), {
    ownerUserId: req.user!.id,
  });
  res.json({ success: true, data });
}

export async function residentCollectionPaymentReceiptHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const data = await getCollectionReceiptForPayment(
    societyId(req),
    String(req.params.paymentId),
    { ownerUserId: req.user!.id },
  );
  res.json({ success: true, data });
}

export async function assertResidentChargeOwner(req: Request, chargeId: string) {
  const charge = await CollectionChargeModel.findOne({
    _id: parseObjectId(chargeId, 'chargeId'),
    societyId: parseObjectId(societyId(req), 'societyId'),
  }).lean();
  if (!charge) return null;
  if (!charge.ownerUserId || String(charge.ownerUserId) !== req.user!.id) {
    throw forbidden('Only the flat owner may access this collection', 'NOT_CHARGE_OWNER');
  }
  return charge;
}
