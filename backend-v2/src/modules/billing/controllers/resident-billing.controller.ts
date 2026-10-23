import type { Request, Response } from 'express';
import { forbidden } from '../../../shared/errors/app-error';
import { getBill, listBills } from '../services/bill-generation.service';
import { getBillInterest } from '../services/interest.service';
import {
  completeDemoResidentPayment,
  createPaymentOrder,
  getReceipt,
  getReceiptForPayment,
  listPayments,
  listReceipts,
  verifyResidentPayment,
} from '../services/payment.service';
import type {
  CompleteDemoPaymentInput,
  ListBillsQuery,
  VerifyPaymentInput,
} from '../validators/billing.validators';
import { BillModel } from '../models/bill.model';
import { parseObjectId } from '../../../utils/object-id';
import { assertFinancialAccess } from '../../users/services/access-control.service';

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

async function assertOwnerFinancialForBill(req: Request, billId: string) {
  const bill = await BillModel.findOne({
    _id: parseObjectId(billId, 'billId'),
    societyId: parseObjectId(societyId(req), 'societyId'),
  }).lean();
  if (!bill) {
    return null;
  }
  if (!bill.ownerUserId || String(bill.ownerUserId) !== req.user!.id) {
    throw forbidden('Only the bill owner may access this bill', 'NOT_BILL_OWNER');
  }
  await assertFinancialAccess({
    userId: req.user!.id,
    societyId: societyId(req),
    flatId: String(bill.flatId),
  });
  return bill;
}

export async function residentListBillsHandler(req: Request, res: Response): Promise<void> {
  const query = req.query as unknown as ListBillsQuery;
  const data = await listBills(societyId(req), {
    ...query,
    ownerUserId: req.user!.id,
  });
  res.json({ success: true, data });
}

export async function residentGetBillHandler(req: Request, res: Response): Promise<void> {
  await assertOwnerFinancialForBill(req, String(req.params.billId));
  const data = await getBill(societyId(req), String(req.params.billId));
  res.json({ success: true, data });
}

export async function residentBillInterestHandler(req: Request, res: Response): Promise<void> {
  await assertOwnerFinancialForBill(req, String(req.params.billId));
  const asOf = req.query.asOf ? new Date(String(req.query.asOf)) : new Date();
  const data = await getBillInterest(societyId(req), String(req.params.billId), asOf);
  res.json({ success: true, data });
}

export async function residentListPaymentsHandler(req: Request, res: Response): Promise<void> {
  const page = Number(req.query.page ?? 1);
  const limit = Number(req.query.limit ?? 20);
  const data = await listPayments(societyId(req), {
    ownerUserId: req.user!.id,
    status: req.query.status ? String(req.query.status) : undefined,
    billId: req.query.billId ? String(req.query.billId) : undefined,
    page,
    limit,
  });
  res.json({ success: true, data });
}

export async function residentPaymentReceiptHandler(req: Request, res: Response): Promise<void> {
  const data = await getReceiptForPayment(societyId(req), String(req.params.paymentId), {
    ownerUserId: req.user!.id,
  });
  res.json({ success: true, data });
}

export async function createPaymentOrderHandler(req: Request, res: Response): Promise<void> {
  const data = await createPaymentOrder(
    societyId(req),
    String(req.params.billId),
    req.user!.id,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function verifyPaymentHandler(req: Request, res: Response): Promise<void> {
  const data = await verifyResidentPayment(
    societyId(req),
    req.user!.id,
    req.body as VerifyPaymentInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function completeDemoPaymentHandler(req: Request, res: Response): Promise<void> {
  const data = await completeDemoResidentPayment(
    societyId(req),
    req.user!.id,
    req.body as CompleteDemoPaymentInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function residentListReceiptsHandler(req: Request, res: Response): Promise<void> {
  const page = Number(req.query.page ?? 1);
  const limit = Number(req.query.limit ?? 20);
  const data = await listReceipts(societyId(req), {
    ownerUserId: req.user!.id,
    page,
    limit,
  });
  res.json({ success: true, data });
}

export async function residentGetReceiptHandler(req: Request, res: Response): Promise<void> {
  const data = await getReceipt(societyId(req), String(req.params.receiptId), {
    ownerUserId: req.user!.id,
  });
  res.json({ success: true, data });
}
