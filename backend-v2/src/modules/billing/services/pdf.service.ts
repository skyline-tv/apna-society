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
  /** Shown as the "Towards" line. */
  description?: string;
  collectionNumber?: string;
  collectionTitle?: string;
};

const LEFT = 50;
const RIGHT = 545;
const BLUE = '0.106 0.310 0.541';
const MUTED = '0.420 0.447 0.431';
const INK = '0.102 0.102 0.094';
const RULE = '0.839 0.878 0.918';

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
  const raw = paiseToRupeesDisplay(paise);
  const negative = raw.startsWith('-');
  const unsigned = negative ? raw.slice(1) : raw;
  const [whole, fraction = '00'] = unsigned.split('.');
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
  return `Rs ${negative ? '-' : ''}${grouped}.${fraction}`;
}

function pdfLatin(value: string): string {
  return value
    .replace(/[·•]/g, ' - ')
    .replace(/[–—]/g, '-')
    .replace(/₹/g, 'Rs ')
    .replace(/\s+/g, ' ')
    .trim();
}

function wrapText(value: string, maxChars: number): string[] {
  const text = pdfLatin(value);
  if (!text) return ['-'];
  if (text.length <= maxChars) return [text];
  const words = text.split(' ');
  const lines: string[] = [];
  let current = '';
  for (const word of words) {
    const next = current ? `${current} ${word}` : word;
    if (next.length <= maxChars) {
      current = next;
      continue;
    }
    if (current) lines.push(current);
    if (word.length > maxChars) {
      for (let i = 0; i < word.length; i += maxChars) {
        lines.push(word.slice(i, i + maxChars));
      }
      current = '';
    } else {
      current = word;
    }
  }
  if (current) lines.push(current);
  return lines.slice(0, 4);
}

function estimateWidth(text: string, size: number, bold = false): number {
  return text.length * size * (bold ? 0.55 : 0.5);
}

function towardsLine(input: ReceiptPdfInput): string {
  if (input.description?.trim()) return pdfLatin(input.description);
  if (input.collectionTitle?.trim()) {
    return pdfLatin(`One-time collection - ${input.collectionTitle}`);
  }
  if (input.billingPeriod?.trim()) {
    return pdfLatin(`Monthly maintenance - ${input.billingPeriod}`);
  }
  if (input.collectionNumber?.trim()) return 'One-time collection';
  if (input.billNumber?.trim()) return 'Monthly maintenance';
  return 'Payment';
}

function isCollectionReceipt(input: ReceiptPdfInput): boolean {
  return Boolean(
    input.collectionNumber ||
      input.collectionTitle ||
      input.receiptNumber.toUpperCase().startsWith('COLRCPT'),
  );
}

type AmountLine = { label: string; amountPaise: number; total?: boolean };

function amountLines(input: ReceiptPdfInput): AmountLine[] {
  const lines: AmountLine[] = [];
  if (isCollectionReceipt(input)) {
    lines.push({ label: 'Special collection', amountPaise: input.amountPaise });
  } else {
    const additional =
      input.additionalServicesPaise != null && input.additionalServicesPaise > 0
        ? input.additionalServicesPaise
        : 0;
    const billed = (input.baseAmountPaise ?? 0) + additional;
    const paidPrincipal = input.principalAmountPaise;
    const paidInFull =
      paidPrincipal == null || billed === 0 || paidPrincipal >= billed;

    if (paidInFull && input.baseAmountPaise != null) {
      lines.push({ label: 'Base maintenance', amountPaise: input.baseAmountPaise });
      if (additional > 0) {
        lines.push({ label: 'Additional services', amountPaise: additional });
      }
    } else if (paidPrincipal != null) {
      lines.push({ label: 'Applied to principal', amountPaise: paidPrincipal });
    }

    if (input.interestAmountPaise != null && input.interestAmountPaise > 0) {
      lines.push({ label: 'Interest', amountPaise: input.interestAmountPaise });
    }
  }
  lines.push({ label: 'Total amount paid', amountPaise: input.amountPaise, total: true });
  return lines;
}

function extraRefs(input: ReceiptPdfInput): { label: string; value: string }[] {
  const refs: { label: string; value: string }[] = [];
  if (input.collectionNumber?.trim()) {
    refs.push({ label: 'Collection reference', value: pdfLatin(input.collectionNumber) });
  } else if (input.billNumber?.trim()) {
    refs.push({ label: 'Bill number', value: pdfLatin(input.billNumber) });
  }
  const txn = input.transactionReference?.trim();
  if (txn) refs.push({ label: 'Transaction reference', value: pdfLatin(txn) });
  return refs;
}

/**
 * Official Apna Society payment receipt (A4, brand blue).
 * Dependency-free PDF 1.4 using standard Type1 fonts.
 */
export function buildReceiptPdf(input: ReceiptPdfInput): Buffer {
  const ops: string[] = [];
  const flatLabel = formatFlatLabel(input.wingCode, input.flatNumber) || '-';
  const status = (input.paymentStatus ?? 'SUCCESSFUL').trim() || 'SUCCESSFUL';
  const payerLines = wrapText(input.ownerName || '-', 42);
  const towards = wrapText(towardsLine(input), 78);
  const society = wrapText(input.societyName || 'Monarch Solitaire', 70);
  const method = pdfLatin(paymentMethodLabel(input.paymentMethod));
  const paidAt = formatPaidAtIst(input.paidAt);
  const lines = amountLines(input);
  const refs = extraRefs(input);

  const text = (
    font: 'F1' | 'F2' | 'F3' | 'F4',
    size: number,
    x: number,
    y: number,
    value: string,
    color = INK,
  ) => {
    ops.push(
      `BT /${font} ${size} Tf ${color} rg ${x.toFixed(2)} ${y.toFixed(2)} Td (${escapePdf(truncatePdfLine(value, 110))}) Tj ET`,
    );
  };
  const rightText = (
    font: 'F1' | 'F2' | 'F3' | 'F4',
    size: number,
    y: number,
    value: string,
    color = INK,
    bold = false,
  ) => {
    const x = Math.max(LEFT + 180, RIGHT - estimateWidth(value, size, bold));
    text(font, size, x, y, value, color);
  };

  // Inner border
  ops.push(`${RULE} RG 0.8 w 28 28 539 786 re S`);

  // AS mark
  ops.push(`${BLUE} RG 1.2 w 50 742 34 34 re S`);
  text('F4', 13, 56.5, 753, 'AS', BLUE);

  text('F4', 20, 94, 762, 'Apna Society', BLUE);
  text('F1', 8, 94, 746, 'OFFICIAL PAYMENT RECEIPT', MUTED);

  rightText('F2', 8, 772, 'RECEIPT', BLUE, true);
  rightText('F4', 14, 754, pdfLatin(input.receiptNumber), INK, true);

  // Status badge
  const statusLabel = status.toUpperCase();
  const badgeW = Math.max(72, estimateWidth(statusLabel, 8, true) + 14);
  const badgeX = RIGHT - badgeW;
  ops.push(`${BLUE} RG 0.8 w ${badgeX.toFixed(2)} 736 ${badgeW.toFixed(2)} 14 re S`);
  text('F2', 8, badgeX + 7, 740, statusLabel, BLUE);

  ops.push(`${BLUE} RG 1 w ${LEFT} 726 m ${RIGHT} 726 l S`);

  let y = 706;
  for (const line of society) {
    text('F1', 11, LEFT, y, line, INK);
    y -= 14;
  }

  y -= 8;
  text('F1', 8, LEFT, y, 'PAYMENT DATE', MUTED);
  text('F1', 8, 320, y, 'PAYMENT METHOD', MUTED);
  y -= 14;
  text('F2', 11, LEFT, y, paidAt);
  text('F2', 11, 320, y, method);

  y -= 28;
  text('F1', 8, LEFT, y, 'RECEIVED WITH THANKS FROM', MUTED);
  y -= 20;
  for (const line of payerLines) {
    text('F3', 20, LEFT, y, line, INK);
    y -= 22;
  }
  text('F2', 11, LEFT, y, `Wing / Flat ${pdfLatin(flatLabel)}`, BLUE);

  y -= 24;
  text('F1', 8, LEFT, y, 'TOWARDS', MUTED);
  y -= 14;
  for (const line of towards) {
    text('F2', 12, LEFT, y, line);
    y -= 15;
  }

  y -= 8;
  for (const row of lines) {
    ops.push(`${RULE} RG 0.4 w ${LEFT} ${y + 10} m ${RIGHT} ${y + 10} l S`);
    if (row.total) {
      y -= 6;
      text('F2', 12, LEFT, y, row.label, BLUE);
      rightText('F4', 16, y - 1, inr(row.amountPaise), BLUE, true);
      y -= 22;
    } else {
      text('F1', 11, LEFT, y, row.label);
      rightText('F2', 11, y, inr(row.amountPaise), INK, true);
      y -= 18;
    }
  }

  if (refs.length) {
    y -= 6;
    for (let i = 0; i < refs.length; i += 2) {
      const leftRef = refs[i];
      const rightRef = refs[i + 1];
      if (leftRef) {
        text('F1', 8, LEFT, y, leftRef.label.toUpperCase(), MUTED);
        text('F2', 11, LEFT, y - 14, leftRef.value);
      }
      if (rightRef) {
        text('F1', 8, 320, y, rightRef.label.toUpperCase(), MUTED);
        text('F2', 11, 320, y - 14, rightRef.value);
      }
      y -= 32;
    }
  }

  const footerY = 52;
  text(
    'F1',
    9,
    LEFT,
    footerY + 16,
    'This is an authorized receipt for a confirmed payment, generated from verified society records.',
    MUTED,
  );
  text('F1', 9, LEFT, footerY, 'No signature is required for digitally issued receipts.', MUTED);
  ops.push(`${RULE} RG 0.6 w 365 ${footerY + 28} m 545 ${footerY + 28} l S`);
  const societyFooter = wrapText(input.societyName || 'Monarch Solitaire', 32);
  rightText('F1', 8, footerY + 16, 'AUTHORIZED', MUTED);
  let authY = footerY;
  for (const line of [...societyFooter].reverse()) {
    rightText('F1', 8, authY, line.toUpperCase(), MUTED);
    authY += 11;
  }

  return assemblePdf(ops.join('\n'));
}

function assemblePdf(content: string): Buffer {
  const objects = [
    '1 0 obj<< /Type /Catalog /Pages 2 0 R >>endobj',
    '2 0 obj<< /Type /Pages /Kids [3 0 R] /Count 1 >>endobj',
    '3 0 obj<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources<< /Font<< /F1 5 0 R /F2 6 0 R /F3 7 0 R /F4 8 0 R >> >> >>endobj',
    `4 0 obj<< /Length ${Buffer.byteLength(content, 'utf8')} >>stream\n${content}\nendstream endobj`,
    '5 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>endobj',
    '6 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>endobj',
    '7 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman >>endobj',
    '8 0 obj<< /Type /Font /Subtype /Type1 /BaseFont /Times-Bold >>endobj',
  ];

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
