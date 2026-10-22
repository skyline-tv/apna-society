import { describe, expect, it } from 'vitest';
import {
  MAX_ACTIVE_ADDITIONAL_SERVICES_PER_FLAT,
  pickNextActiveSlot,
} from '../../src/modules/billing/utils/additional-service-limit';

describe('additional service per-flat cap', () => {
  it('caps active slots at 10', () => {
    expect(MAX_ACTIVE_ADDITIONAL_SERVICES_PER_FLAT).toBe(10);
  });

  it('assigns the lowest free slot from 1', () => {
    expect(pickNextActiveSlot([])).toBe(1);
    expect(pickNextActiveSlot([1, 2, 4])).toBe(3);
    expect(pickNextActiveSlot([1, 2, 3, 4, 5, 6, 7, 8, 9])).toBe(10);
  });

  it('returns null when all 10 slots are taken', () => {
    expect(pickNextActiveSlot([1, 2, 3, 4, 5, 6, 7, 8, 9, 10])).toBeNull();
  });

  it('ignores missing slots from legacy inactive rows', () => {
    expect(pickNextActiveSlot([1, undefined, null, 2])).toBe(3);
  });
});
