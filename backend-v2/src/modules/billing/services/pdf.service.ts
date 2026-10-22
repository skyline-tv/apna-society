import { formatFlatLabel } from '../../../utils/flat-label';
import { paiseToRupeesDisplay } from '../utils/money';

/**
 * Minimal PDF generator (no external dependency).
 * Produces a simple single-page PDF with receipt text.
 */
export function buildReceiptPdf(input: {
  receiptNumber: string;
  societyName: string;
  flatNumber: string;
  wingCode: string;
  ownerName: string;
  amountPaise: number;
  paymentMethod: string;
  transactionReference?: string;
  paidAt: Date;
}): Buffer {
  const lines = [
    'Apna Society — Payment Receipt',
    `Society: ${input.societyName}`,
    `Receipt: ${input.receiptNumber}`,
    `Flat: ${formatFlatLabel(input.wingCode, input.flatNumber)}`,
    `Owner: ${input.ownerName}`,
    `Amount: INR ${paiseToRupeesDisplay(input.amountPaise)}`,
    `Method: ${input.paymentMethod}`,
    `Reference: ${input.transactionReference ?? '-'}`,
    `Paid at: ${input.paidAt.toISOString()}`,
  ];

  const content = lines.map((line, index) => `BT /F1 11 Tf 50 ${750 - index * 18} Td (${escapePdf(line)}) Tj ET`).join('\n');

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

function escapePdf(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/\(/g, '\\(').replace(/\)/g, '\\)');
}
