import { Schema, model, type Document, type Types } from 'mongoose';

export type AuditAction =
  | 'AUTH_OTP_REQUESTED'
  | 'AUTH_OTP_VERIFIED'
  | 'AUTH_OTP_FAILED'
  | 'AUTH_LOGIN_SUCCESS'
  | 'AUTH_LOGIN_FAILED'
  | 'AUTH_PASSWORD_CHANGED'
  | 'AUTH_PASSWORD_RESET'
  | 'AUTH_REFRESH'
  | 'AUTH_REFRESH_REUSE'
  | 'AUTH_LOGOUT'
  | 'AUTH_LOGOUT_ALL'
  | 'USER_PROVISIONED'
  | 'SECURITY_EVENT'
  | 'SOCIETY_UPDATED'
  | 'WING_CREATED'
  | 'WING_UPDATED'
  | 'FLAT_CREATED'
  | 'FLAT_UPDATED'
  | 'FLAT_DEACTIVATED'
  | 'USER_CREATED'
  | 'USER_UPDATED'
  | 'USER_DEACTIVATED'
  | 'OWNER_ASSIGNED'
  | 'OWNER_OCCUPANCY_ENDED'
  | 'TENANT_ASSIGNED'
  | 'TENANT_OCCUPANCY_ENDED'
  | 'BILL_GENERATED'
  | 'BILL_CANCELLED'
  | 'BILL_ADJUSTED'
  | 'BILL_OWNER_ATTACHED'
  | 'ADDITIONAL_SERVICE_CREATED'
  | 'ADDITIONAL_SERVICE_UPDATED'
  | 'ADDITIONAL_SERVICE_DEACTIVATED'
  | 'PAYMENT_INITIATED'
  | 'PAYMENT_SUCCEEDED'
  | 'PAYMENT_FAILED'
  | 'PAYMENT_RECORDED_OFFLINE'
  | 'PAYMENT_REFUNDED'
  | 'RECEIPT_GENERATED'
  | 'GUARD_CREATED'
  | 'GUARD_UPDATED'
  | 'GUARD_DEACTIVATED'
  | 'VISITOR_REQUESTED'
  | 'VISITOR_APPROVED'
  | 'VISITOR_REJECTED'
  | 'VISITOR_CANCELLED'
  | 'VISITOR_OTP_VERIFIED'
  | 'VISITOR_ENTERED'
  | 'VISITOR_EXITED'
  | 'VISITOR_EXPIRED'
  | 'PARCEL_AUTHORIZED'
  | 'PARCEL_RECEIVED'
  | 'PARCEL_DELIVERED'
  | 'PARCEL_COLLECTED'
  | 'PARCEL_CANCELLED'
  | 'VEHICLE_REGISTERED'
  | 'VEHICLE_UPDATED'
  | 'VEHICLE_DEACTIVATED'
  | 'PARKING_SLOT_CREATED'
  | 'PARKING_SLOT_UPDATED'
  | 'PARKING_SLOT_ACTIVATED'
  | 'PARKING_SLOT_DEACTIVATED'
  | 'PARKING_ALLOCATED'
  | 'PARKING_RELEASED'
  | 'VEHICLE_ENTRY'
  | 'VEHICLE_EXIT'
  | 'COMPLAINT_CREATED'
  | 'COMPLAINT_ASSIGNED'
  | 'COMPLAINT_REASSIGNED'
  | 'COMPLAINT_UNASSIGNED'
  | 'COMPLAINT_PRIORITY_CHANGED'
  | 'COMPLAINT_STARTED'
  | 'COMPLAINT_RESOLVED'
  | 'COMPLAINT_CLOSED'
  | 'COMPLAINT_CANCELLED'
  | 'COMPLAINT_ATTACHMENT_ADDED'
  | 'STAFF_CREATED'
  | 'STAFF_UPDATED'
  | 'STAFF_DEACTIVATED'
  | 'STAFF_TERMINATED'
  | 'STAFF_REACTIVATED'
  | 'STAFF_ATTENDANCE_MARKED'
  | 'STAFF_ATTENDANCE_CHECKED_OUT'
  | 'STAFF_ATTENDANCE_CORRECTED'
  | 'STAFF_SHIFT_CREATED'
  | 'STAFF_SHIFT_UPDATED'
  | 'STAFF_SHIFT_CANCELLED'
  | 'FACILITY_CREATED'
  | 'FACILITY_UPDATED'
  | 'FACILITY_ACTIVATED'
  | 'FACILITY_DEACTIVATED'
  | 'FACILITY_BOOKING_CREATED'
  | 'FACILITY_BOOKING_APPROVED'
  | 'FACILITY_BOOKING_REJECTED'
  | 'FACILITY_BOOKING_CANCELLED'
  | 'ANNOUNCEMENT_CREATED'
  | 'ANNOUNCEMENT_UPDATED'
  | 'ANNOUNCEMENT_PUBLISHED'
  | 'ANNOUNCEMENT_SCHEDULED'
  | 'ANNOUNCEMENT_CANCELLED'
  | 'ANNOUNCEMENT_ARCHIVED'
  | 'ANNOUNCEMENT_ATTACHMENT_ADDED'
  | 'ANNOUNCEMENT_ATTACHMENT_REMOVED';

export interface AuditLogDocument extends Document {
  societyId?: Types.ObjectId;
  actorUserId?: Types.ObjectId;
  action: AuditAction;
  targetType?: string;
  targetId?: string;
  metadata?: Record<string, unknown>;
  ipAddress?: string;
  userAgent?: string;
  createdAt: Date;
  updatedAt: Date;
}

const auditLogSchema = new Schema<AuditLogDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', index: true },
    actorUserId: { type: Schema.Types.ObjectId, ref: 'User', index: true },
    action: { type: String, required: true, index: true },
    targetType: { type: String },
    targetId: { type: String },
    metadata: { type: Schema.Types.Mixed },
    ipAddress: { type: String },
    userAgent: { type: String },
  },
  { timestamps: true },
);

auditLogSchema.index({ societyId: 1, action: 1, createdAt: -1 });
auditLogSchema.index({ actorUserId: 1, createdAt: -1 });
auditLogSchema.index({ createdAt: -1 });

export const AuditLogModel = model<AuditLogDocument>('AuditLog', auditLogSchema);
