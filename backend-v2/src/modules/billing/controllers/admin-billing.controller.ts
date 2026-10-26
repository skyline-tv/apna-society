import type { Request, Response } from 'express';
import { getRequestSocietyId } from '../../../middleware/admin-society';
import {
  adjustBill,
  cancelBill,
  deleteAllBills,
  generateBills,
  getBill,
  listBills,
  listEligibleFlats,
} from '../services/bill-generation.service';
import { getBillingSummary } from '../services/billing-summary.service';
import { getBillInterest } from '../services/interest.service';
import {
  getPayment,
  getReceipt,
  getReceiptForPayment,
  listPayments,
  listReceipts,
  recordOfflinePayment,
  refundPayment,
} from '../services/payment.service';
import type {
  AdjustBillInput,
  BillingSummaryQuery,
  GenerateBillsInput,
  ListBillsQuery,
  ListPaymentsQuery,
  OfflinePaymentInput,
} from '../validators/billing.validators';

function actorFrom(req: Request) {
  return {
    userId: req.user!.id,
    ipAddress: req.ip,
    userAgent: req.get('user-agent') ?? undefined,
  };
}

export async function generateBillsHandler(req: Request, res: Response): Promise<void> {
  const body = req.body as GenerateBillsInput;
  const data = await generateBills(getRequestSocietyId(req), body, actorFrom(req));
  res.status(201).json({ success: true, data });
}

export async function listBillsHandler(req: Request, res: Response): Promise<void> {
  const query = req.query as unknown as ListBillsQuery;
  const data = await listBills(getRequestSocietyId(req), query);
  res.json({ success: true, data });
}

export async function getBillHandler(req: Request, res: Response): Promise<void> {
  const data = await getBill(getRequestSocietyId(req), String(req.params.billId));
  res.json({ success: true, data });
}

export async function billingSummaryHandler(req: Request, res: Response): Promise<void> {
  const query = req.query as unknown as BillingSummaryQuery;
  const data = await getBillingSummary(getRequestSocietyId(req), query);
  res.json({ success: true, data });
}

export async function eligibleFlatsHandler(req: Request, res: Response): Promise<void> {
  const data = await listEligibleFlats(getRequestSocietyId(req));
  res.json({ success: true, data });
}

export async function billInterestHandler(req: Request, res: Response): Promise<void> {
  const asOf = req.query.asOf ? new Date(String(req.query.asOf)) : new Date();
  const data = await getBillInterest(
    getRequestSocietyId(req),
    String(req.params.billId),
    asOf,
  );
  res.json({ success: true, data });
}

export async function adjustBillHandler(req: Request, res: Response): Promise<void> {
  const data = await adjustBill(
    getRequestSocietyId(req),
    String(req.params.billId),
    req.body as AdjustBillInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function cancelBillHandler(req: Request, res: Response): Promise<void> {
  const data = await cancelBill(
    getRequestSocietyId(req),
    String(req.params.billId),
    String((req.body as { reason: string }).reason),
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function deleteAllBillsHandler(req: Request, res: Response): Promise<void> {
  const data = await deleteAllBills(getRequestSocietyId(req), actorFrom(req));
  res.json({ success: true, data });
}

export async function offlinePaymentHandler(req: Request, res: Response): Promise<void> {
  const data = await recordOfflinePayment(
    getRequestSocietyId(req),
    req.body as OfflinePaymentInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function listPaymentsHandler(req: Request, res: Response): Promise<void> {
  const query = req.query as unknown as ListPaymentsQuery;
  const data = await listPayments(getRequestSocietyId(req), query);
  res.json({ success: true, data });
}

export async function getPaymentHandler(req: Request, res: Response): Promise<void> {
  const data = await getPayment(getRequestSocietyId(req), String(req.params.paymentId));
  res.json({ success: true, data });
}

export async function refundPaymentHandler(req: Request, res: Response): Promise<void> {
  const data = await refundPayment(
    getRequestSocietyId(req),
    String(req.params.paymentId),
    String((req.body as { reason: string }).reason),
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function getAdminReceiptHandler(req: Request, res: Response): Promise<void> {
  const data = await getReceipt(getRequestSocietyId(req), String(req.params.receiptId));
  res.json({ success: true, data });
}

export async function getAdminPaymentReceiptHandler(req: Request, res: Response): Promise<void> {
  const data = await getReceiptForPayment(
    getRequestSocietyId(req),
    String(req.params.paymentId),
  );
  res.json({ success: true, data });
}

export async function listAdminReceiptsHandler(req: Request, res: Response): Promise<void> {
  const page = Number(req.query.page ?? 1);
  const limit = Number(req.query.limit ?? 20);
  const data = await listReceipts(getRequestSocietyId(req), { page, limit });
  res.json({ success: true, data });
}
