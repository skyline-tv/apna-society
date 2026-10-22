import { describe, expect, it } from 'vitest';
import { formatFlatLabel } from '../../src/utils/flat-label';

describe('formatFlatLabel', () => {
  it('joins wing and bare number', () => {
    expect(formatFlatLabel('E', '303')).toBe('E-303');
    expect(formatFlatLabel('A', '101')).toBe('A-101');
  });

  it('does not duplicate a wing already stored on the number', () => {
    expect(formatFlatLabel('E', 'E-303')).toBe('E-303');
    expect(formatFlatLabel('E', 'E-E-303')).toBe('E-303');
    expect(formatFlatLabel('B', 'B204')).toBe('B-204');
  });

  it('handles missing parts', () => {
    expect(formatFlatLabel('', '303')).toBe('303');
    expect(formatFlatLabel('C', '')).toBe('C');
    expect(formatFlatLabel(null, null)).toBe('');
  });
});
