import { Schema, model, type Document, type Types } from 'mongoose';

export const DEVICE_PLATFORMS = ['android', 'ios', 'web'] as const;
export type DevicePlatform = (typeof DEVICE_PLATFORMS)[number];

export interface DeviceTokenDocument extends Document {
  userId: Types.ObjectId;
  societyId: Types.ObjectId;
  token: string;
  platform: DevicePlatform;
  deviceId?: string;
  isActive: boolean;
  lastSeenAt: Date;
  deactivatedAt?: Date;
  deactivationReason?: string;
  createdAt: Date;
  updatedAt: Date;
}

const deviceTokenSchema = new Schema<DeviceTokenDocument>(
  {
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    token: { type: String, required: true, trim: true, maxlength: 4096 },
    platform: { type: String, enum: DEVICE_PLATFORMS, required: true },
    deviceId: { type: String, trim: true, maxlength: 128 },
    isActive: { type: Boolean, required: true, default: true },
    lastSeenAt: { type: Date, required: true, default: Date.now },
    deactivatedAt: { type: Date },
    deactivationReason: { type: String, trim: true, maxlength: 80 },
  },
  { timestamps: true },
);

deviceTokenSchema.index({ token: 1 }, { unique: true });
deviceTokenSchema.index({ userId: 1, isActive: 1 });
deviceTokenSchema.index({ societyId: 1, userId: 1, isActive: 1 });
deviceTokenSchema.index({ deviceId: 1, userId: 1 }, { sparse: true });

export const DeviceTokenModel = model<DeviceTokenDocument>('DeviceToken', deviceTokenSchema);
