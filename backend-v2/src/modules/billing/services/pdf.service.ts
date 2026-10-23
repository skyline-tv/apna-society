import { formatFlatLabel } from '../../../utils/flat-label';
import { paiseToRupeesDisplay } from '../utils/money';

export type ReceiptPdfInput = {
  receiptNumber: string;
  societyName: string;
  flatNumber: string;
  wingCode: string;
  ownerName: string;
  amountPaise: number;
  paymentMethod: string;
  transactionReference?: string;
  paidAt: Date;
  billNumber?: string;
  billingPeriod?: string;
  baseAmountPaise?: number;
  additionalServicesPaise?: number;
  principalAmountPaise?: number;
  interestAmountPaise?: number;
  paymentStatus?: string;
};

function formatPaidAtIst(paidAt: Date): string {
  const formatted = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Kolkata',
    day: '2-digit',
    month: 'short',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hour12: true,
  }).format(paidAt);
  return `${formatted} IST`;
}

function paymentMethodLabel(method: string): string {
  switch (method) {
    case 'OFFLINE':
    case 'CASH':
      return 'Cash / offline';
    case 'CHEQUE':
      return 'Cheque';
    case 'UPI':
      return 'UPI';
    case 'BANK_TRANSFER':
    case 'NEFT':
      return 'Bank transfer';
    case 'DEMO':
      return 'Demo gateway';
    default:
      return method || '-';
  }
}

function inr(paise: number): string {
  return `INR ${paiseToRupeesDisplay(paise)}`;
}

/**
 * Minimal PDF generator (no external dependency).
 * Produces a simple single-page PDF with receipt text.
 */
export function buildReceiptPdf(input: ReceiptPdfInput): Buffer {
  const flatLabel = formatFlatLabel(input.wingCode, input.flatNumber) || '-';
  const lines = [
    'APNA SOCIETY',
    'Payment Receipt',
    '----------------------------------------------',
    `Society: ${input.societyName}`,
    `Receipt number: ${input.receiptNumber}`,
    `Payment status: ${input.paymentStatus ?? 'SUCCESSFUL'}`,
    `Payment date: ${formatPaidAtIst(input.paidAt)}`,
    `Wing / flat: ${flatLabel}`,
    `Resident / payer: ${input.ownerName || '-'}`,
    input.billNumber ? `Bill number: ${input.billNumber}` : undefined,
    input.billingPeriod ? `Billing period: ${input.billingPeriod}` : undefined,
    '----------------------------------------------',
    input.baseAmountPaise != null ? `Base maintenance: ${inr(input.baseAmountPaise)}` : undefined,
    input.additionalServicesPaise != null && input.additionalServicesPaise > 0
      ? `Additional services: ${inr(input.additionalServicesPaise)}`
      : undefined,
    input.principalAmountPaise != null
      ? `Applied to principal: ${inr(input.principalAmountPaise)}`
      : undefined,
    input.interestAmountPaise != null && input.interestAmountPaise > 0
      ? `Interest: ${inr(input.interestAmountPaise)}`
      : undefined,
    `Total amount paid: ${inr(input.amountPaise)}`,
    `Payment method: ${paymentMethodLabel(input.paymentMethod)}`,
    `Transaction / reference: ${input.transactionReference?.trim() || '-'}`,
    '----------------------------------------------',
    'This is an authorized receipt for a confirmed payment.',
    'This document is generated from verified society records.',
    'Thank you for paying your maintenance on time.',
  ].filter((line): line is string => Boolean(line));

  const title = lines.slice(0, 2);
  const body = lines.slice(2);
  const ops: string[] = [];
  ops.push(`BT /F1 16 Tf 50 750 Td (${escapePdf(title[0] ?? 'APNA SOCIETY')}) Tj ET`);
  ops.push(`BT /F1 12 Tf 50 728 Td (${escapePdf(title[1] ?? 'Payment Receipt')}) Tj ET`);
  body.forEach((line, index) => {
    const y = 700 - index * 16;
    if (y < 60) return;
    ops.push(`BT /F1 10 Tf 50 ${y} Td (${escapePdf(truncatePdfLine(line))}) Tj ET`);
  });
  const content = ops.join('\n');

  const objects: string[] = [];
  objects.push('1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj');
  objects.push('2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj');
  objects.push(
    '3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources<< /Font<< /F1 5 0 R >> >> >>endobj',
  );
  objects.push(`4 0 obj<< /Length ${Buffer.byteLength(content, 'utf8')} >>stream\n${content}\nendstream endobj`);
  objects.push('5 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>endobj');

  let pdf = '%PDF-1.4\n';
  const offsets = [0];
  for (const obj of objects) {
    offsets.push(Buffer.byteLength(pdf, 'utf8'));
    pdf += `${obj}\n`;
  }
  const xrefStart = Buffer.byteLength(pdf, 'utf8');
  pdf += `xref\n0 ${objects.length + 1}\n`;
  pdf += '0000000000 65535 f \n';
  for (let i = 1; i < offsets.length; i += 1) {
    pdf += `${offsets[i].toString().padStart(10, '0')} 00000 n \n`;
  }
  pdf += `trailer<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xrefStart}\n%%EOF`;
  return Buffer.from(pdf, 'utf8');
}

function truncatePdfLine(value: string, max = 92): string {
  if (value.length <= max) return value;
  return `${value.slice(0, max - 3)}...`;
}

function escapePdf(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');
}
