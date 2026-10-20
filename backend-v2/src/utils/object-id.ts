import { Types } from 'mongoose';
import { badRequest } from '../shared/errors/app-error';

export function isObjectId(value: string): boolean {
  return Types.ObjectId.isValid(value) && String(new Types.ObjectId(value)) === value;
}

export function parseObjectId(value: string, field = 'id'): Types.ObjectId {
  if (!isObjectId(value)) {
    throw badRequest(`Invalid ${field}`, 'INVALID_OBJECT_ID');
  }
  return new Types.ObjectId(value);
}

export const objectIdSchemaMessage = 'Must be a valid ObjectId';
