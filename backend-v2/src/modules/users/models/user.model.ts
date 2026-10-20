import { Schema, model, type Document, type Types } from 'mongoose';
import { ROLES, type Role } from '../../../config/constants';

export interface UserDocument extends Document {
  email: string;
  /** Unique login username (normalized lowercase). Required for password auth. */
  username?: string;
  /** bcrypt hash — never select by default; never return in API responses. */
  passwordHash?: string;
  /** When true, client must force a password change before normal use. */
  mustChangePassword: boolean;
  failedLoginAttempts: number;
  lockUntil?: Date;
  passwordChangedAt?: Date;
  name: string;
  /** Free-form display phone (legacy). Prefer mobileE164 for contact. */
  phone?: string;
  /** E.164 digits without '+', e.g. 919876543210. Contact / legacy OTP — not primary login. */
  mobileE164?: string;
  /** Set when ownership of mobileE164 has been confirmed (admin or OTP). */
  mobileVerifiedAt?: Date;
  roles: Role[];
  isActive: boolean;
  canLogin: boolean;
  primarySocietyId?: Types.ObjectId;
  lastLoginAt?: Date;
  provisionedBy?: Types.ObjectId;
  createdAt: Date;
  updatedAt: Date;
}

const userSchema = new Schema<UserDocument>(
  {
    email: {
      type: String,
      required: true,
      unique: true,
      lowercase: true,
      trim: true,
      index: true,
    },
    username: {
      type: String,
      unique: true,
      sparse: true,
      lowercase: true,
      trim: true,
      index: true,
    },
    passwordHash: {
      type: String,
      select: false,
    },
    mustChangePassword: {
      type: Boolean,
      default: false,
    },
    failedLoginAttempts: {
      type: Number,
      default: 0,
    },
    lockUntil: { type: Date },
    passwordChangedAt: { type: Date },
    name: { type: String, required: true, trim: true },
    phone: { type: String, trim: true },
    mobileE164: {
      type: String,
      trim: true,
      sparse: true,
      unique: true,
    },
    mobileVerifiedAt: { type: Date },
    roles: {
      type: [String],
      enum: ROLES,
      default: [],
      validate: {
        validator: (roles: Role[]) => roles.length > 0,
        message: 'User must have at least one role',
      },
    },
    isActive: { type: Boolean, default: true },
    canLogin: { type: Boolean, default: true },
    primarySocietyId: { type: Schema.Types.ObjectId, ref: 'Society' },
    lastLoginAt: { type: Date },
    provisionedBy: { type: Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true },
);

userSchema.index({ roles: 1, isActive: 1 });
userSchema.index({ primarySocietyId: 1, isActive: 1 });
userSchema.index({ name: 'text', email: 'text', phone: 'text', mobileE164: 'text', username: 'text' });
userSchema.index({ phone: 1, isActive: 1 });
userSchema.index({ mobileE164: 1, isActive: 1 });

export const UserModel = model<UserDocument>('User', userSchema);
