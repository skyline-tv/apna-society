import { Schema, model, type Document, type Types } from 'mongoose';

export interface SequenceDocument extends Document {
  societyId: Types.ObjectId;
  key: string;
  value: number;
}

const sequenceSchema = new Schema<SequenceDocument>({
  societyId: { type: Schema.Types.ObjectId, ref: 'Society', required: true },
  key: { type: String, required: true },
  value: { type: Number, required: true, default: 0 },
});

sequenceSchema.index({ societyId: 1, key: 1 }, { unique: true });

export const SequenceModel = model<SequenceDocument>('Sequence', sequenceSchema);

export async function nextSequence(
  societyId: Types.ObjectId | string,
  key: string,
  session?: import('mongoose').ClientSession,
): Promise<number> {
  const updated = await SequenceModel.findOneAndUpdate(
    { societyId, key },
    { $inc: { value: 1 } },
    { upsert: true, new: true, session },
  );
  return updated.value;
}
