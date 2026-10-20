import multer from 'multer';
import type { NextFunction, Request, Response } from 'express';
import { getEnv } from '../../../config/env';
import { badRequest } from '../../../shared/errors/app-error';

/** Single-file multipart field name: `file`. */
export const complaintAttachmentUpload = (
  req: Request,
  res: Response,
  next: NextFunction,
): void => {
  const max = getEnv().COMPLAINT_ATTACHMENT_MAX_BYTES;
  const handler = multer({
    storage: multer.memoryStorage(),
    limits: { files: 1, fileSize: max },
  }).single('file');

  handler(req, res, (err: unknown) => {
    if (err instanceof multer.MulterError) {
      if (err.code === 'LIMIT_FILE_SIZE') {
        next(badRequest('Attachment exceeds maximum size', 'ATTACHMENT_TOO_LARGE'));
        return;
      }
      next(badRequest(err.message, 'UPLOAD_ERROR'));
      return;
    }
    if (err) {
      next(err);
      return;
    }
    if (!req.file) {
      next(badRequest('file is required', 'FILE_REQUIRED'));
      return;
    }
    next();
  });
};
