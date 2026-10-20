import { describe, expect, it } from 'vitest';
import { collectionPercentage } from '../../src/modules/reports/utils/report-math';
import {
  csvRow,
  escapeCsvCell,
  formatPaiseAsRupees,
} from '../../src/modules/reports/utils/csv';
import { normalizeReportDateRange } from '../../src/modules/reports/utils/filters';

describe('collectionPercentage', () => {
  it('returns 0 for zero billed amount', () => {
    expect(collectionPercentage(0, 0)).toBe(0);
    expect(collectionPercentage(100, 0)).toBe(0);
  });

  it('computes two-decimal percentage with integer arithmetic', () => {
    // 250000 / 400000 = 62.5%
    expect(collectionPercentage(250_000, 400_000)).toBe(62.5);
    // floor truncates toward zero for the scaled ratio
    expect(collectionPercentage(1, 3)).toBe(33.33);
  });
});

describe('CSV safety', () => {
  it('prefixes formula-like cells', () => {
    expect(escapeCsvCell('=CMD()')).toBe("'=CMD()");
    expect(escapeCsvCell('+1+1')).toBe("'+1+1");
    expect(escapeCsvCell('-2+3')).toBe("'-2+3");
    expect(escapeCsvCell('@SUM(A1)')).toBe("'@SUM(A1)");
  });

  it('quotes commas and escapes quotes', () => {
    expect(escapeCsvCell('a,b')).toBe('"a,b"');
    expect(escapeCsvCell('say "hi"')).toBe('"say ""hi"""');
  });

  it('formats paise as rupees without floating money math', () => {
    expect(formatPaiseAsRupees(400_000)).toBe('4000.00');
    expect(formatPaiseAsRupees(1)).toBe('0.01');
  });

  it('builds rows ending with newline', () => {
    expect(csvRow(['a', 'b'])).toBe('a,b\n');
  });
});

describe('normalizeReportDateRange', () => {
  it('rejects inverted and oversized ranges', () => {
    expect(() =>
      normalizeReportDateRange({
        from: new Date('2026-06-01'),
        to: new Date('2026-01-01'),
      }),
    ).toThrow();
    expect(() =>
      normalizeReportDateRange({
        from: new Date('2020-01-01'),
        to: new Date('2026-01-01'),
      }),
    ).toThrow();
  });
});
