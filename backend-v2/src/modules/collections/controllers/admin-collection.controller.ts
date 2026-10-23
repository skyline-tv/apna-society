import type { Request, Response } from 'express';
import { getRequestSocietyId } from '../../../middleware/admin-society';
import {
  addCollectionFlats,
  adjustCollectionCharge,
  cancelCollection,
  closeCollection,
  createCollection,
  exportCollectionChargesCsv,
  getCollection,
  getCollectionDashboard,
  listChargeAdjustments,
  listCollectionCharges,
  listCollections,
  previewAddCollectionFlats,
  previewCollection,
  removeCollectionFlats,
  updateCollection,
} from '../services/collection.service';
import {
  getCollectionReceipt,
  getCollectionReceiptForPayment,
  listCollectionPayments,
  recordOfflineCollectionPayment,
} from '../services/collection-payment.service';
import type {
  AddCollectionFlatsInput,
  AdjustChargeInput,
  CancelCollectionInput,
  CreateCollectionInput,
  ListChargesQuery,
  ListCollectionPaymentsQuery,
  ListCollectionsQuery,
  OfflineCollectionPaymentInput,
  PreviewCollectionInput,
  RemoveCollectionFlatsInput,
  UpdateCollectionInput,
} from '../validators/collection.validators';

function actorFrom(req: Request) {
  return {
    userId: req.user!.id,
    ipAddress: req.ip,
    userAgent: req.get('user-agent') ?? undefined,
  };
}

export async function previewCollectionHandler(req: Request, res: Response): Promise<void> {
  const data = await previewCollection(
    getRequestSocietyId(req),
    req.body as PreviewCollectionInput,
  );
  res.json({ success: true, data });
}

export async function createCollectionHandler(req: Request, res: Response): Promise<void> {
  const data = await createCollection(
    getRequestSocietyId(req),
    req.body as CreateCollectionInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function listCollectionsHandler(req: Request, res: Response): Promise<void> {
  const data = await listCollections(
    getRequestSocietyId(req),
    req.query as unknown as ListCollectionsQuery,
  );
  res.json({ success: true, data });
}

export async function getCollectionHandler(req: Request, res: Response): Promise<void> {
  const data = await getCollection(getRequestSocietyId(req), String(req.params.collectionId));
  res.json({ success: true, data });
}

export async function updateCollectionHandler(req: Request, res: Response): Promise<void> {
  const data = await updateCollection(
    getRequestSocietyId(req),
    String(req.params.collectionId),
    req.body as UpdateCollectionInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function previewAddCollectionFlatsHandler(req: Request, res: Response): Promise<void> {
  const data = await previewAddCollectionFlats(
    getRequestSocietyId(req),
    String(req.params.collectionId),
    req.body as AddCollectionFlatsInput,
  );
  res.json({ success: true, data });
}

export async function addCollectionFlatsHandler(req: Request, res: Response): Promise<void> {
  const data = await addCollectionFlats(
    getRequestSocietyId(req),
    String(req.params.collectionId),
    req.body as AddCollectionFlatsInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function removeCollectionFlatsHandler(req: Request, res: Response): Promise<void> {
  const data = await removeCollectionFlats(
    getRequestSocietyId(req),
    String(req.params.collectionId),
    req.body as RemoveCollectionFlatsInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function closeCollectionHandler(req: Request, res: Response): Promise<void> {
  const data = await closeCollection(
    getRequestSocietyId(req),
    String(req.params.collectionId),
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function cancelCollectionHandler(req: Request, res: Response): Promise<void> {
  const data = await cancelCollection(
    getRequestSocietyId(req),
    String(req.params.collectionId),
    req.body as CancelCollectionInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function collectionDashboardHandler(req: Request, res: Response): Promise<void> {
  const data = await getCollectionDashboard(
    getRequestSocietyId(req),
    String(req.params.collectionId),
  );
  res.json({ success: true, data });
}

export async function listCollectionChargesHandler(req: Request, res: Response): Promise<void> {
  const data = await listCollectionCharges(
    getRequestSocietyId(req),
    String(req.params.collectionId),
    req.query as unknown as ListChargesQuery,
  );
  res.json({ success: true, data });
}

export async function exportCollectionChargesHandler(req: Request, res: Response): Promise<void> {
  const data = await exportCollectionChargesCsv(
    getRequestSocietyId(req),
    String(req.params.collectionId),
  );
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="${data.filename}"`);
  res.send(data.csv);
}

export async function adjustChargeHandler(req: Request, res: Response): Promise<void> {
  const data = await adjustCollectionCharge(
    getRequestSocietyId(req),
    String(req.params.chargeId),
    req.body as AdjustChargeInput,
    actorFrom(req),
  );
  res.json({ success: true, data });
}

export async function listChargeAdjustmentsHandler(req: Request, res: Response): Promise<void> {
  const data = await listChargeAdjustments(
    getRequestSocietyId(req),
    String(req.params.chargeId),
  );
  res.json({ success: true, data });
}

export async function listAdminCollectionPaymentsHandler(req: Request, res: Response): Promise<void> {
  const query = req.query as unknown as ListCollectionPaymentsQuery;
  const data = await listCollectionPayments(getRequestSocietyId(req), {
    collectionId: String(req.params.collectionId),
    status: query.status,
    chargeId: query.chargeId,
    page: query.page,
    limit: query.limit,
  });
  res.json({ success: true, data });
}

export async function offlineCollectionPaymentHandler(req: Request, res: Response): Promise<void> {
  const data = await recordOfflineCollectionPayment(
    getRequestSocietyId(req),
    req.body as OfflineCollectionPaymentInput,
    actorFrom(req),
  );
  res.status(201).json({ success: true, data });
}

export async function adminCollectionReceiptHandler(req: Request, res: Response): Promise<void> {
  const data = await getCollectionReceipt(
    getRequestSocietyId(req),
    String(req.params.receiptId),
  );
  res.json({ success: true, data });
}

export async function adminCollectionPaymentReceiptHandler(
  req: Request,
  res: Response,
): Promise<void> {
  const data = await getCollectionReceiptForPayment(
    getRequestSocietyId(req),
    String(req.params.paymentId),
  );
  res.json({ success: true, data });
}
