import type { Request, Response } from 'express';
import { getCollectionReport, getOutstandingReport } from '../services/collection-report.service';
import { getComplaintAnalytics } from '../services/complaint-analytics.service';
import { getReportsDashboard } from '../services/dashboard-analytics.service';
import {
  exportCollectionsCsv,
  exportComplaintsCsv,
  exportFinancialCsv,
  exportOutstandingCsv,
  exportPaymentsCsv,
} from '../services/export-report.service';
import { getFinancialReport } from '../services/financial-report.service';

function societyId(req: Request): string {
  return String(req.societyId);
}

export async function financialReportHandler(req: Request, res: Response): Promise<void> {
  const data = await getFinancialReport(societyId(req), req.query as never);
  res.json({ success: true, data });
}

export async function collectionReportHandler(req: Request, res: Response): Promise<void> {
  const data = await getCollectionReport(societyId(req), req.query as never);
  res.json({ success: true, data });
}

export async function outstandingReportHandler(req: Request, res: Response): Promise<void> {
  const data = await getOutstandingReport(societyId(req), req.query as never);
  res.json({ success: true, data });
}

export async function complaintAnalyticsHandler(req: Request, res: Response): Promise<void> {
  const data = await getComplaintAnalytics(societyId(req), req.query as never);
  res.json({ success: true, data });
}

export async function reportsDashboardHandler(req: Request, res: Response): Promise<void> {
  const data = await getReportsDashboard(societyId(req), req.query as never);
  res.json({ success: true, data });
}

export async function exportReportHandler(req: Request, res: Response): Promise<void> {
  const type = String(req.params.type);
  const query = req.query as never;
  const sid = societyId(req);

  switch (type) {
    case 'financial':
      await exportFinancialCsv(sid, query, res);
      return;
    case 'collections':
      await exportCollectionsCsv(sid, query, res);
      return;
    case 'outstanding':
      await exportOutstandingCsv(sid, query, res);
      return;
    case 'payments':
      await exportPaymentsCsv(sid, query, res);
      return;
    case 'complaints':
      await exportComplaintsCsv(sid, query, res);
      return;
    default:
      res.status(400).json({
        success: false,
        error: { code: 'INVALID_EXPORT_TYPE', message: 'Unknown export type' },
      });
  }
}
