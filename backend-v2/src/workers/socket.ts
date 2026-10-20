import type { Server as HttpServer } from 'http';
import { Server, type Socket } from 'socket.io';
import { getCorsOrigins, getEnv } from '../config/env';
import { verifyAccessToken } from '../modules/auth/services/token.service';
import { MembershipModel } from '../modules/users/models/membership.model';
import { setAnnouncementSocketIoServer } from '../modules/announcements/services/announcement-events.service';
import { setComplaintSocketIoServer } from '../modules/complaints/services/complaint-events.service';
import { setFacilitySocketIoServer } from '../modules/facilities/services/facility-events.service';
import { setNotificationSocketIoServer } from '../modules/notifications/services/notification-events.service';
import { setStaffSocketIoServer } from '../modules/staff/services/staff-events.service';
import {
  residentVisitorRoom,
  setSocketIoServer,
  societyGuardsRoom,
} from '../modules/visitors/services/visitor-events.service';
import { getLogger } from '../utils/logger';
import { isObjectId } from '../utils/object-id';

interface AuthedSocket extends Socket {
  data: {
    userId?: string;
    roles?: string[];
    societyIds?: string[];
  };
}

/**
 * Socket.IO with JWT auth and society-scoped visitor rooms.
 * OTP values are never emitted.
 */
export function attachSocketServer(httpServer: HttpServer): Server {
  const env = getEnv();
  const io = new Server(httpServer, {
    cors: {
      origin: getCorsOrigins(env),
      credentials: true,
    },
    path: '/socket.io',
  });

  io.use((socket: AuthedSocket, next) => {
    try {
      const token =
        (socket.handshake.auth?.token as string | undefined) ||
        (typeof socket.handshake.headers.authorization === 'string' &&
        socket.handshake.headers.authorization.startsWith('Bearer ')
          ? socket.handshake.headers.authorization.slice('Bearer '.length)
          : undefined);
      if (!token) {
        next(new Error('AUTH_REQUIRED'));
        return;
      }
      const payload = verifyAccessToken(token);
      socket.data.userId = payload.sub;
      socket.data.roles = payload.roles;
      socket.data.societyIds = payload.societyIds;
      next();
    } catch {
      next(new Error('INVALID_TOKEN'));
    }
  });

  io.on('connection', (socket: AuthedSocket) => {
    getLogger().debug({ socketId: socket.id, userId: socket.data.userId }, 'Socket connected');
    socket.emit('ready', { service: 'apna-society-backend-v2' });

    socket.on('join:resident', async (payload: { societyId?: string }, ack?) => {
      try {
        const societyId = payload?.societyId;
        const userId = socket.data.userId;
        if (!userId || !societyId || !isObjectId(societyId)) {
          ack?.({ ok: false, code: 'INVALID_SOCIETY' });
          return;
        }
        if (!socket.data.societyIds?.includes(societyId)) {
          ack?.({ ok: false, code: 'SOCIETY_ISOLATION' });
          return;
        }
        // Guards must not join resident-only rooms.
        if (socket.data.roles?.includes('GUARD') && !socket.data.roles.includes('OWNER') && !socket.data.roles.includes('TENANT') && !socket.data.roles.includes('ADMIN')) {
          ack?.({ ok: false, code: 'FORBIDDEN_ROLE' });
          return;
        }
        const membership = await MembershipModel.findOne({
          societyId,
          userId,
          isActive: true,
          role: { $in: ['OWNER', 'TENANT', 'ADMIN'] },
        })
          .select('_id')
          .lean();
        if (!membership) {
          ack?.({ ok: false, code: 'SOCIETY_ISOLATION' });
          return;
        }
        await socket.join(residentVisitorRoom(societyId, userId));
        ack?.({ ok: true, room: residentVisitorRoom(societyId, userId) });
      } catch {
        ack?.({ ok: false, code: 'JOIN_FAILED' });
      }
    });

    socket.on('join:guards', async (payload: { societyId?: string }, ack?) => {
      try {
        const societyId = payload?.societyId;
        const userId = socket.data.userId;
        if (!userId || !societyId || !isObjectId(societyId)) {
          ack?.({ ok: false, code: 'INVALID_SOCIETY' });
          return;
        }
        if (!socket.data.roles?.includes('GUARD') && !socket.data.roles?.includes('ADMIN')) {
          ack?.({ ok: false, code: 'FORBIDDEN_ROLE' });
          return;
        }
        const membership = await MembershipModel.findOne({
          societyId,
          userId,
          isActive: true,
          role: { $in: ['GUARD', 'ADMIN'] },
        })
          .select('_id')
          .lean();
        if (!membership) {
          ack?.({ ok: false, code: 'SOCIETY_ISOLATION' });
          return;
        }
        await socket.join(societyGuardsRoom(societyId));
        ack?.({ ok: true, room: societyGuardsRoom(societyId) });
      } catch {
        ack?.({ ok: false, code: 'JOIN_FAILED' });
      }
    });
  });

  setSocketIoServer(io);
  setComplaintSocketIoServer(io);
  setFacilitySocketIoServer(io);
  setStaffSocketIoServer(io);
  setAnnouncementSocketIoServer(io);
  setNotificationSocketIoServer(io);
  getLogger().info(
    'Socket.IO attached with visitor/complaint/facility/staff/announcement/notification room auth',
  );
  return io;
}
