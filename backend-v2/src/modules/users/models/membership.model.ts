import { Schema, model, type Document, type Types } from 'mongoose';
import { ROLES, type Role } from '../../../config/constants';

export interface MembershipDocument extends Document {
  societyId: Types.ObjectId;
  userId: Types.ObjectId;
  role: Role;
  /** Null for society-scoped memberships (ADMIN). ObjectId for flat-scoped resident roles. */
  flatId?: Types.ObjectId | null;
  wingId?: Types.ObjectId | null;
  isActive: boolean;
  startsAt: Date;
  endsAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

const membershipSchema = new Schema<MembershipDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    role: { type: String, enum: ROLES, required: true },
    flatId: { type: Schema.Types.ObjectId, ref: 'Flat', default: null },
    wingId: { type: Schema.Types.ObjectId, ref: 'Wing', default: null },
    isActive: { type: Boolean, default: true },
    startsAt: { type: Date, default: Date.now },
    endsAt: { type: Date },
  },
  { timestamps: true },
);

// Flat-scoped resident memberships. Partial unique avoids colliding with society-scoped rows.
membershipSchema.index(
  { societyId: 1, userId: 1, role: 1, flatId: 1 },
  {
    unique: true,
    partialFilterExpression: {
      isActive: true,
      flatId: { $type: 'objectId' },
    },
  },
);

// Society-scoped memberships (ADMIN / GUARD posts) use flatId: null explicitly.
// MongoDB partial indexes do not support $exists:false.
membershipSchema.index(
  { societyId: 1, userId: 1, role: 1 },
  {
    unique: true,
    partialFilterExpression: {
      isActive: true,
      flatId: null,
    },
  },
);

membershipSchema.index({ societyId: 1, role: 1, isActive: 1 });
membershipSchema.index({ userId: 1, isActive: 1 });
membershipSchema.index({ societyId: 1, flatId: 1, isActive: 1 });
membershipSchema.index({ societyId: 1, userId: 1, isActive: 1 });

export const MembershipModel = model<MembershipDocument>('Membership', membershipSchema);
