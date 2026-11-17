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

const PAGE_W = 595;
const PAGE_H = 842;
const LEFT = 42;
const RIGHT = 553;
const CONTENT_W = RIGHT - LEFT;

/** HTML receipt template tokens (#0F3A5F / #1B5E8F / …). */
const NAVY = '0.059 0.227 0.373';
const ACCENT_BLUE = '0.106 0.369 0.561';
const WHITE = '1 1 1';
const INK = '0.102 0.141 0.200';
const MUTED = '0.420 0.467 0.529';
const BLUE = '0.106 0.369 0.561';
const GREEN = '0.118 0.557 0.353';
const GREEN_BG = '0.902 0.961 0.929';
const BORDER = '0.867 0.894 0.925';
const TINT = '0.953 0.969 0.984';
const HEADER_LABEL = '0.663 0.769 0.859';
const COL = [LEFT, LEFT + 36, LEFT + 250, LEFT + 390, RIGHT];

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
  return refs;
}

/**
 * Official society payment receipt (A4).
 * Matches the HTML receipt template (navy header, tint meta card, charge table).
 */
export function buildReceiptPdf(input: ReceiptPdfInput): Buffer {
  const ops: string[] = [];
  const watermark = input.watermark ?? (isDemoMode() ? DEMO_MODE_LABEL : undefined);
  const status = (input.paymentStatus ?? 'SUCCESSFUL').trim() || 'SUCCESSFUL';
  const payer = displayPayerName(input.ownerName || '');
  const wingFlat = wingAndFlatLine(input.wingCode, input.flatNumber);
  const towards = wrapText(towardsLine(input), 78);
  const societyName = 'Proposed Monarch Solitaire A to E';
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
    const x = Math.max(LEFT + 160, RIGHT - estimateWidth(value, size, bold));
    text(font, size, x, y, value, color);
  };
  const fillRect = (x: number, y: number, w: number, h: number, color: string) => {
    ops.push(`${color} rg ${x.toFixed(2)} ${y.toFixed(2)} ${w.toFixed(2)} ${h.toFixed(2)} re f`);
  };
  const strokeRect = (x: number, y: number, w: number, h: number, color = BORDER) => {
    ops.push(`${color} RG 0.8 w ${x.toFixed(2)} ${y.toFixed(2)} ${w.toFixed(2)} ${h.toFixed(2)} re S`);
  };
  const hLine = (x1: number, x2: number, y: number) => {
    ops.push(`${BORDER} RG 0.6 w ${x1.toFixed(2)} ${y.toFixed(2)} m ${x2.toFixed(2)} ${y.toFixed(2)} l S`);
  };
  const vLine = (x: number, y1: number, y2: number) => {
    ops.push(`${BORDER} RG 0.6 w ${x.toFixed(2)} ${y1.toFixed(2)} m ${x.toFixed(2)} ${y2.toFixed(2)} l S`);
  };

  // White page
  fillRect(0, 0, PAGE_W, PAGE_H, WHITE);

  if (watermark) {
    const mark = pdfLatin(watermark);
    ops.push('q 0.90 0.78 0.40 rg 0.22 g');
    ops.push(
      `BT /F2 28 Tf 0.72 0.72 -0.72 0.72 118 210 Tm (${escapePdf(mark)}) Tj ET`,
    );
    ops.push('Q');
  }

  // Full-bleed navy header + blue accent bar
  const headerH = 96;
  const headerBot = PAGE_H - headerH;
  fillRect(0, headerBot, PAGE_W, headerH, NAVY);
  fillRect(0, headerBot, PAGE_W, 4, ACCENT_BLUE);

  text('F2', 16, LEFT, PAGE_H - 52, societyName, WHITE);
  rightText('F1', 8, PAGE_H - 36, 'RECEIPT', HEADER_LABEL);
  rightText('F2', 14, PAGE_H - 54, pdfLatin(input.receiptNumber), WHITE, true);

  const statusLabel = status.toUpperCase();
  const badgeW = Math.max(92, estimateWidth(statusLabel, 8, true) + 30);
  const badgeH = 16;
  const badgeX = RIGHT - badgeW;
  const badgeY = PAGE_H - 78;
  fillRect(badgeX, badgeY, badgeW, badgeH, GREEN_BG);
  // Soft pill corners approximated as filled rect; green status dot
  ops.push(`${GREEN} rg ${badgeX + 9} ${badgeY + 5} 5 5 re f`);
  text('F2', 8, badgeX + 18, badgeY + 4.5, statusLabel, GREEN);

  // Tint meta card
  let y = headerBot - 24;
  const cardPadX = 14;
  const midX = LEFT + CONTENT_W / 2;
  const leftCol = LEFT + cardPadX;
  const rightCol = midX + cardPadX;
  const towardsH = towards.length * 13;
  const rowH = 40;
  const cardH = 10 + rowH * 2 + 12 + towardsH + 16;
  const cardTop = y;
  const cardBot = cardTop - cardH;
  fillRect(LEFT, cardBot, CONTENT_W, cardH, TINT);
  strokeRect(LEFT, cardBot, CONTENT_W, cardH);

  // Row 1 — date / method
  y = cardTop - 16;
  text('F1', 8, leftCol, y, 'PAYMENT DATE', MUTED);
  text('F1', 8, rightCol, y, 'PAYMENT METHOD', MUTED);
  y -= 14;
  text('F2', 11, leftCol, y, paidAt, INK);
  text('F2', 11, rightCol, y, method, INK);
  const row1Bot = cardTop - rowH;
  hLine(LEFT + 1, RIGHT - 1, row1Bot);
  vLine(midX, cardTop - 1, row1Bot);

  // Row 2 — name / wing-flat
  y = row1Bot - 14;
  text('F1', 8, leftCol, y, 'NAME', MUTED);
  text('F1', 8, rightCol, y, 'WING / FLAT NO', MUTED);
  y -= 14;
  text('F2', 11, leftCol, y, pdfLatin(payer), INK);
  text('F2', 11, rightCol, y, pdfLatin(wingFlat), BLUE);
  const row2Bot = row1Bot - rowH;
  hLine(LEFT + 1, RIGHT - 1, row2Bot);
  vLine(midX, row1Bot, row2Bot);

  // Full-width towards
  y = row2Bot - 14;
  text('F1', 8, leftCol, y, 'TOWARDS', MUTED);
  y -= 13;
  for (const line of towards) {
    text('F2', 10, leftCol, y, line, INK);
    y -= 13;
  }

  y = cardBot - 24;

  const items = lines.filter((row) => !row.total);
  const total = lines.find((row) => row.total);
  const tableW = CONTENT_W;
  const box = (bot: number, h: number, fill?: string) => {
    if (fill) fillRect(LEFT, bot, tableW, h, fill);
    strokeRect(LEFT, bot, tableW, h);
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

  const headerHRow = 22;
  box(y - headerHRow, headerHRow, NAVY);
  text('F2', 7, COL[0] + 10, y - 14, '#', WHITE);
  text('F2', 7, COL[1] + 8, y - 14, 'PARTICULARS / CHARGE DESCRIPTION', WHITE);
  text('F2', 7, COL[2] + 8, y - 14, 'PERIOD / TENURE', WHITE);
  cellRight(COL[4], y - 14, 'AMOUNT', 7, WHITE);
  y -= headerHRow;

  items.forEach((row, idx) => {
    const labelLines = wrapText(row.label, 36);
    const periodLines = wrapText(row.period?.trim() ? row.period : '-', 22);
    const h = Math.max(34, 16 + Math.max(labelLines.length, periodLines.length) * 11);
    box(y - h, h, WHITE);
    text('F1', 10, COL[0] + 12, y - 20, String(idx + 1), INK);
    let ly = y - 20;
    for (const line of labelLines) {
      text('F1', 10, COL[1] + 8, ly, line);
      ly -= 11;
    }
    ly = y - 20;
    for (const line of periodLines) {
      text('F1', 10, COL[2] + 8, ly, line, INK);
      ly -= 11;
    }
    cellRight(COL[4], y - 20, inr(row.amountPaise), 10);
    y -= h;
  });

  if (total) {
    const h = 34;
    box(y - h, h, TINT);
    text('F2', 9, COL[1] + 8, y - 20, 'TOTAL AMOUNT PAID', NAVY);
    cellRight(COL[4], y - 20, inr(total.amountPaise), 14, NAVY, 'F2');
    y -= h;
  }

  if (refs.length) {
    y -= 22;
    hLine(LEFT, RIGHT, y + 10);
    y -= 2;
    for (const ref of refs) {
      text('F1', 8, LEFT, y, ref.label.toUpperCase(), MUTED);
      y -= 14;
      const valueLines = wrapText(ref.value, 78);
      for (const line of valueLines) {
        text('F2', 12, LEFT, y, line, NAVY);
        y -= 14;
      }
      y -= 6;
    }
  }

  const footerY = 42;
  hLine(LEFT, RIGHT, footerY + 34);
  text(
    'F1',
    8,
    LEFT,
    footerY + 18,
    watermark
      ? 'SIMULATED PAYMENT - SAMPLE DATA - NOT A REAL TRANSACTION'
      : 'This is an authorized receipt for a confirmed payment, generated from verified society records.',
    MUTED,
  );
  text(
    'F1',
    8,
    LEFT,
    footerY + 6,
    watermark
      ? pdfLatin(watermark)
      : 'No signature is required for digitally issued receipts.',
    MUTED,
  );
  rightText('F2', 9, footerY + 18, 'AUTHORIZED', GREEN, true);
  rightText('F1', 7, footerY + 6, societyName.toUpperCase(), MUTED);

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
