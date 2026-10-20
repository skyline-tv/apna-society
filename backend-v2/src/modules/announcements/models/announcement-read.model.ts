import { Schema, model, type Document, type Types } from 'mongoose';

export interface AnnouncementReadDocument extends Document {
  societyId: Types.ObjectId;
  announcementId: Types.ObjectId;
  userId: Types.ObjectId;
  isRead: boolean;
  firstReadAt?: Date;
  lastReadAt?: Date;
  createdAt: Date;
  updatedAt: Date;
}

const announcementReadSchema = new Schema<AnnouncementReadDocument>(
  {
    societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
    announcementId: { type: Schema.Types.ObjectId, ref: 'Announcement', required: true },
    userId: { type: Schema.Types.ObjectId, ref: 'User', required: true },
    isRead: { type: Boolean, required: true, default: true },
    firstReadAt: { type: Date },
    lastReadAt: { type: Date },
  },
  { timestamps: true },
);

announcementReadSchema.index({ announcementId: 1, userId: 1 }, { unique: true });
announcementReadSchema.index({ societyId: 1, userId: 1, isRead: 1 });

export const AnnouncementReadModel = model<AnnouncementReadDocument>(
  'AnnouncementRead',
  announcementReadSchema,
);
