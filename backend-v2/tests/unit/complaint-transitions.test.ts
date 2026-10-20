import { describe, expect, it } from 'vitest';
import { assertTransition } from '../../src/modules/complaints/services/complaint-transitions';
import { AppError } from '../../src/shared/errors/app-error';

describe('complaint status transitions', () => {
  it('allows the happy path', () => {
    expect(() => assertTransition('OPEN', 'ASSIGNED')).not.toThrow();
    expect(() => assertTransition('ASSIGNED', 'IN_PROGRESS')).not.toThrow();
    expect(() => assertTransition('IN_PROGRESS', 'RESOLVED')).not.toThrow();
    expect(() => assertTransition('RESOLVED', 'CLOSED')).not.toThrow();
  });

  it('allows cancel/unassign/reassign edges', () => {
    expect(() => assertTransition('OPEN', 'CANCELLED')).not.toThrow();
    expect(() => assertTransition('ASSIGNED', 'OPEN')).not.toThrow();
    expect(() => assertTransition('IN_PROGRESS', 'ASSIGNED')).not.toThrow();
  });

  it('rejects invalid and terminal transitions', () => {
    expect(() => assertTransition('OPEN', 'RESOLVED')).toThrow(AppError);
    expect(() => assertTransition('CLOSED', 'OPEN')).toThrow(AppError);
    expect(() => assertTransition('CANCELLED', 'ASSIGNED')).toThrow(AppError);
    try {
      assertTransition('RESOLVED', 'IN_PROGRESS');
    } catch (error) {
      expect((error as AppError).code).toBe('INVALID_STATUS_TRANSITION');
    }
  });
});
