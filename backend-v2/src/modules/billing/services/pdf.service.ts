import { DEMO_MODE_LABEL, isDemoMode } from '../../../config/demo';
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
  /** Diagonal overlay. Set automatically in DEMO_MODE. */
  watermark?: string;
};

const LEFT = 50;
const RIGHT = 545;
const BLUE = '0.043 0.235 0.408';
/** Slate-700 — labels stay readable on white paper / print. */
const MUTED = '0.200 0.255 0.333';
const INK = '0.059 0.090 0.165';
const RULE = '0.392 0.455 0.545';
const BORDER = '0.886 0.910 0.941';
const HEADER_BG = '0.945 0.961 0.973';
const FOOTER_BG = '0.976 0.980 0.984';
const COL = [50, 86, 298, 436, 545];

function formatPaidAtIst(paidAt: Date): string {
  return new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Kolkata',
    day: '2-digit',
    month: 'short',
    year: 'numeric',
  }).format(paidAt);
}

function displayPayerName(ownerName: string): string {
  const name = ownerName.trim();
  if (!name || name === '-' || /^unassigned$/i.test(name)) return '-';
  return name;
}

function wingAndFlatLine(wingCode: string, flatNumber: string): string {
  const label = formatFlatLabel(wingCode, flatNumber);
  const wing = (wingCode ?? '').trim().toUpperCase();
  if (!label) return '-';
  if (wing && label.startsWith(`${wing}-`)) {
    return `Wing ${wing} - Flat ${label.slice(wing.length + 1)}`;
  }
  if (wing && label === wing) return `Wing ${wing}`;
  return `Flat ${label}`;
}

function paymentMethodLabel(method: string): string {
  switch (method) {
    case 'OFFLINE':
      return 'Cash / offline';
    case 'CASH':
      return 'Cash';
    case 'CHEQUE':
      return 'Cheque';
    case 'UPI':
      return 'UPI';
    case 'NEFT':
      return 'NEFT';
    case 'BANK_TRANSFER':
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

type AmountLine = {
  label: string;
  amountPaise: number;
  period?: string;
  total?: boolean;
};

function amountLines(input: ReceiptPdfInput): AmountLine[] {
  const period = input.billingPeriod?.trim() || undefined;
  const lines: AmountLine[] = [];
  if (isCollectionReceipt(input)) {
    lines.push({
      label: 'Special collection',
      amountPaise: input.amountPaise,
      period: input.collectionNumber,
    });
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
      lines.push({
        label: 'Base Maintenance Charges',
        amountPaise: input.baseAmountPaise,
        period,
      });
      if (additional > 0) {
        lines.push({
          label: 'Additional services',
          amountPaise: additional,
          period,
        });
      }
    } else if (paidPrincipal != null) {
      lines.push({
        label: 'Applied to principal',
        amountPaise: paidPrincipal,
        period,
      });
    }

    if (input.interestAmountPaise != null && input.interestAmountPaise > 0) {
      lines.push({
        label: 'Interest',
        amountPaise: input.interestAmountPaise,
        period,
      });
    }
  }
  lines.push({
    label: 'Total Amount Paid',
    amountPaise: input.amountPaise,
    total: true,
  });
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
 * Official society payment receipt (A4, brand blue).
 * Issued in the society's name — no product branding.
 * Dependency-free PDF 1.4 using standard Type1 fonts.
 */
export function buildReceiptPdf(input: ReceiptPdfInput): Buffer {
  const ops: string[] = [];
  const watermark = input.watermark ?? (isDemoMode() ? DEMO_MODE_LABEL : undefined);
  const status = (input.paymentStatus ?? 'SUCCESSFUL').trim() || 'SUCCESSFUL';
  const payerLines = wrapText(displayPayerName(input.ownerName || ''), 42);
  const wingFlat = wingAndFlatLine(input.wingCode, input.flatNumber);
  const towards = wrapText(towardsLine(input), 78);
  const society = wrapText(input.societyName || 'Monarch Solitaire A to E', 32);
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

  if (watermark) {
    const mark = pdfLatin(watermark);
    ops.push('q 0.90 0.78 0.40 rg 0.22 g');
    ops.push(
      `BT /F2 28 Tf 0.72 0.72 -0.72 0.72 118 210 Tm (${escapePdf(mark)}) Tj ET`,
    );
    ops.push('Q');
  }

  ops.push(`${BORDER} RG 0.8 w 18 18 559 806 re S`);
  ops.push(`${BORDER} RG 0.8 w 32 32 531 778 re S`);

  let titleY = 766;
  for (const line of society) {
    text('F4', 16, LEFT, titleY, line, BLUE);
    titleY -= 16;
  }

  rightText('F2', 8, 772, 'RECEIPT', BLUE, true);
  rightText('F4', 13, 754, pdfLatin(input.receiptNumber), INK, true);

  const statusLabel = status.toUpperCase();
  const badgeW = Math.max(72, estimateWidth(statusLabel, 8, true) + 14);
  const badgeX = RIGHT - badgeW;
  ops.push(`${BLUE} RG 0.8 w ${badgeX.toFixed(2)} 736 ${badgeW.toFixed(2)} 14 re S`);
  text('F2', 8, badgeX + 7, 740, statusLabel, BLUE);

  ops.push(`${RULE} RG 0.8 w ${LEFT} 726 m ${RIGHT} 726 l S`);

  let y = 706;
  text('F1', 8, LEFT, y, 'PAYMENT DATE', MUTED);
  text('F1', 8, 320, y, 'PAYMENT METHOD', MUTED);
  y -= 14;
  text('F2', 11, LEFT, y, paidAt);
  text('F2', 11, 320, y, method);

  y -= 16;
  for (const line of payerLines) {
    text('F2', 11, LEFT, y, line, INK);
    y -= 13;
  }
  text('F2', 11, LEFT, y, pdfLatin(wingFlat), BLUE);

  y -= 24;
  text('F1', 8, LEFT, y, 'TOWARDS', MUTED);
  y -= 14;
  for (const line of towards) {
    text('F2', 11, LEFT, y, line);
    y -= 14;
  }

  y -= 6;
  const items = lines.filter((row) => !row.total);
  const total = lines.find((row) => row.total);
  const tableW = RIGHT - LEFT;
  const vlines = (top: number, bot: number, splits: number[]) => {
    ops.push(`${BORDER} RG 0.5 w`);
    for (const x of splits) {
      ops.push(`${x.toFixed(2)} ${bot.toFixed(2)} m ${x.toFixed(2)} ${top.toFixed(2)} l S`);
    }
  };
  const box = (bot: number, h: number, fill?: string) => {
    if (fill) {
      ops.push(
        `${fill} rg ${LEFT.toFixed(2)} ${bot.toFixed(2)} ${tableW.toFixed(2)} ${h.toFixed(2)} re f`,
      );
    }
    ops.push(
      `${BORDER} RG 0.6 w ${LEFT.toFixed(2)} ${bot.toFixed(2)} ${tableW.toFixed(2)} ${h.toFixed(2)} re S`,
    );
  };
  const cellRight = (
    right: number,
    ty: number,
    value: string,
    size: number,
    color = INK,
    font: 'F1' | 'F2' | 'F3' | 'F4' = 'F2',
  ) => {
    text(font, size, right - 8 - estimateWidth(value, size, font !== 'F1'), ty, value, color);
  };

  const headerH = 22;
  box(y - headerH, headerH, HEADER_BG);
  vlines(y, y - headerH, [COL[1], COL[2], COL[3]]);
  text('F2', 7, COL[0] + 12, y - 14, '#', MUTED);
  text('F2', 7, COL[1] + 8, y - 14, 'PARTICULARS / CHARGE DESCRIPTION', MUTED);
  text('F2', 7, COL[2] + 8, y - 14, 'PERIOD / TENURE', MUTED);
  cellRight(COL[4], y - 14, 'AMOUNT', 7, MUTED);
  y -= headerH;

  items.forEach((row, idx) => {
    const labelLines = wrapText(row.label, 36);
    const periodLines = wrapText(row.period?.trim() ? row.period : '-', 22);
    const h = Math.max(24, 12 + Math.max(labelLines.length, periodLines.length) * 11);
    box(y - h, h);
    vlines(y, y - h, [COL[1], COL[2], COL[3]]);
    text('F1', 9, COL[0] + 14, y - 15, String(idx + 1), MUTED);
    let ly = y - 15;
    for (const line of labelLines) {
      text('F1', 9, COL[1] + 8, ly, line);
      ly -= 11;
    }
    ly = y - 15;
    for (const line of periodLines) {
      text('F1', 8, COL[2] + 8, ly, line, MUTED);
      ly -= 11;
    }
    cellRight(COL[4], y - 15, inr(row.amountPaise), 9);
    y -= h;
  });

  if (total) {
    const h = 28;
    box(y - h, h, FOOTER_BG);
    ops.push(
      `${BORDER} RG 0.5 w ${COL[3].toFixed(2)} ${(y - h).toFixed(2)} m ${COL[3].toFixed(2)} ${y.toFixed(2)} l S`,
    );
    cellRight(COL[3], y - 17, 'TOTAL AMOUNT PAID', 9, BLUE);
    cellRight(COL[4], y - 17, inr(total.amountPaise), 12, BLUE, 'F4');
    y -= h;
  }

  if (refs.length) {
    // Keep refs clear of the charge table and of each other.
    y -= 18;
    ops.push(`${BORDER} RG 0.6 w ${LEFT} ${y + 8} m ${RIGHT} ${y + 8} l S`);
    y -= 4;
    for (const ref of refs) {
      text('F1', 8, LEFT, y, ref.label.toUpperCase(), MUTED);
      y -= 14;
      const valueLines = wrapText(ref.value, 78);
      for (const line of valueLines) {
        text('F2', 11, LEFT, y, line, INK);
        y -= 13;
      }
      y -= 10;
    }
  }

  const footerY = 52;
  text(
    'F1',
    9,
    LEFT,
    footerY + 16,
    watermark
      ? 'SIMULATED PAYMENT - SAMPLE DATA - NOT A REAL TRANSACTION'
      : 'This is an authorized receipt for a confirmed payment, generated from verified society records.',
    MUTED,
  );
  text(
    'F1',
    9,
    LEFT,
    footerY,
    watermark
      ? pdfLatin(watermark)
      : 'No signature is required for digitally issued receipts.',
    MUTED,
  );
  ops.push(`${RULE} RG 0.6 w 365 ${footerY + 28} m 545 ${footerY + 28} l S`);
  const societyFooter = wrapText(input.societyName || 'Monarch Solitaire A to E', 32);
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
