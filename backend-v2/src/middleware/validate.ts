import type { NextFunction, Request, Response } from 'express';
import type { AnyZodObject, ZodEffects, ZodTypeAny } from 'zod';
import { badRequest } from '../shared/errors/app-error';

type Schema = AnyZodObject | ZodEffects<AnyZodObject> | ZodTypeAny;

export function validateBody(schema: Schema) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    const parsed = schema.safeParse(req.body);
    if (!parsed.success) {
      next(
        badRequest('Validation failed', 'VALIDATION_ERROR', parsed.error.flatten()),
      );
      return;
    }
    req.body = parsed.data;
    next();
  };
}

export function validateQuery(schema: Schema) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    const parsed = schema.safeParse(req.query);
    if (!parsed.success) {
      next(
        badRequest('Validation failed', 'VALIDATION_ERROR', parsed.error.flatten()),
      );
      return;
    }
    req.query = parsed.data as Request['query'];
    next();
  };
}

export function validateParams(schema: Schema) {
  return (req: Request, _res: Response, next: NextFunction): void => {
    const parsed = schema.safeParse(req.params);
    if (!parsed.success) {
      next(
        badRequest('Validation failed', 'VALIDATION_ERROR', parsed.error.flatten()),
      );
      return;
    }
    req.params = parsed.data as Request['params'];
    next();
  };
}
