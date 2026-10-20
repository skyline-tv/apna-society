import { conflict } from '../../../shared/errors/app-error';
import type { ComplaintStatus } from '../models/complaint.model';

const TERMINAL: ComplaintStatus[] = ['CLOSED', 'CANCELLED'];

/**
 * Valid status transitions for the complaint lifecycle.
 * Assignment/reassignment/priority are handled as separate actions that may also change status.
 */
export function assertTransition(from: ComplaintStatus, to: ComplaintStatus): void {
  if (from === to) return;
  if (TERMINAL.includes(from)) {
    throw conflict(
      `Complaint is ${from} and cannot transition to ${to}`,
      'INVALID_STATUS_TRANSITION',
    );
  }

  const allowed: Record<ComplaintStatus, ComplaintStatus[]> = {
    OPEN: ['ASSIGNED', 'CANCELLED'],
    ASSIGNED: ['OPEN', 'IN_PROGRESS', 'ASSIGNED', 'CANCELLED'],
    IN_PROGRESS: ['ASSIGNED', 'RESOLVED', 'CANCELLED'],
    RESOLVED: ['CLOSED'],
    CLOSED: [],
    CANCELLED: [],
  };

  if (!allowed[from].includes(to)) {
    throw conflict(
      `Invalid status transition from ${from} to ${to}`,
      'INVALID_STATUS_TRANSITION',
    );
  }
}
