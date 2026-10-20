import swaggerJsdoc from 'swagger-jsdoc';
import { API_PREFIX } from '../config/constants';
import { getEnv } from '../config/env';

const errorResponses = {
  400: { description: 'Validation error', content: { 'application/json': { schema: { $ref: '#/components/schemas/ErrorResponse' } } } },
  401: { description: 'Unauthorized', content: { 'application/json': { schema: { $ref: '#/components/schemas/ErrorResponse' } } } },
  403: { description: 'Forbidden / society isolation', content: { 'application/json': { schema: { $ref: '#/components/schemas/ErrorResponse' } } } },
  404: { description: 'Not found', content: { 'application/json': { schema: { $ref: '#/components/schemas/ErrorResponse' } } } },
  409: { description: 'Conflict', content: { 'application/json': { schema: { $ref: '#/components/schemas/ErrorResponse' } } } },
};

const adminSecurity = [{ bearerAuth: [] }];

export function buildOpenApiSpec() {
  const env = getEnv();
  return swaggerJsdoc({
    definition: {
      openapi: '3.0.3',
      info: {
        title: 'Apna Society API v2',
        version: '2.10.0',
        description:
          'Apna Society backend: auth, society/flat admin, occupancy, billing/payments, visitor/security, vehicle/parking, complaints/maintenance, staff, facilities, announcements, notifications, admin reports/analytics, and production-hardened ops.',
      },
      servers: [{ url: `http://localhost:${env.PORT}`, description: 'Local' }],
      components: {
        securitySchemes: {
          bearerAuth: { type: 'http', scheme: 'bearer', bearerFormat: 'JWT' },
        },
        schemas: {
          ErrorResponse: {
            type: 'object',
            properties: {
              success: { type: 'boolean', example: false },
              error: {
                type: 'object',
                properties: {
                  code: { type: 'string' },
                  message: { type: 'string' },
                  requestId: { type: 'string' },
                  details: {},
                },
              },
            },
          },
          TokenPair: {
            type: 'object',
            properties: {
              accessToken: { type: 'string' },
              refreshToken: { type: 'string' },
              expiresIn: { type: 'string', example: '15m' },
              tokenType: { type: 'string', example: 'Bearer' },
            },
          },
          Society: {
            type: 'object',
            properties: {
              id: { type: 'string' },
              name: { type: 'string' },
              code: { type: 'string' },
              address: { type: 'string' },
              city: { type: 'string' },
              state: { type: 'string' },
              pincode: { type: 'string' },
              contactEmail: { type: 'string' },
              contactPhone: { type: 'string' },
              timezone: { type: 'string', example: 'Asia/Kolkata' },
              currency: { type: 'string', example: 'INR' },
              maintenanceDayOfMonth: { type: 'integer' },
              isActive: { type: 'boolean' },
              createdAt: { type: 'string', format: 'date-time' },
              updatedAt: { type: 'string', format: 'date-time' },
            },
          },
          Wing: {
            type: 'object',
            properties: {
              id: { type: 'string' },
              societyId: { type: 'string' },
              name: { type: 'string' },
              code: { type: 'string' },
              floors: { type: 'integer' },
              flatsPerFloor: { type: 'integer' },
              sortOrder: { type: 'integer' },
              isActive: { type: 'boolean' },
              flatCount: { type: 'integer' },
              createdAt: { type: 'string', format: 'date-time' },
              updatedAt: { type: 'string', format: 'date-time' },
            },
          },
          Flat: {
            type: 'object',
            properties: {
              id: { type: 'string' },
              number: { type: 'string' },
              wingId: { type: 'string' },
              wingCode: { type: 'string' },
              floor: { type: 'integer' },
              position: { type: 'integer' },
              flatType: { type: 'string', enum: ['2BHK', '3BHK'] },
              maintenanceRate: { type: 'number' },
              occupancyStatus: {
                type: 'string',
                enum: ['OWNER_OCCUPIED', 'TENANT_OCCUPIED', 'VACANT'],
              },
              isActive: { type: 'boolean' },
              activeOwner: { type: 'object' },
              activeTenant: { type: 'object' },
            },
          },
          Dashboard: {
            type: 'object',
            properties: {
              totals: { type: 'object' },
              wings: { type: 'array', items: { type: 'object' } },
            },
          },
        },
      },
      paths: {
        '/health': {
          get: { tags: ['Health'], summary: 'Liveness probe', responses: { 200: { description: 'OK' } } },
        },
        [`${API_PREFIX}/health`]: {
          get: { tags: ['Health'], summary: 'API + database health', responses: { 200: { description: 'OK' } } },
        },
        [`${API_PREFIX}/auth/request-otp`]: {
          post: {
            tags: ['Auth'],
            summary: 'Request email OTP',
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['email'],
                    properties: { email: { type: 'string', format: 'email' } },
                  },
                },
              },
            },
            responses: { 200: { description: 'Generic success' }, 429: { description: 'Rate limited' } },
          },
        },
        [`${API_PREFIX}/auth/verify-otp`]: {
          post: {
            tags: ['Auth'],
            summary: 'Verify OTP and issue tokens',
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['email', 'otp'],
                    properties: {
                      email: { type: 'string', format: 'email' },
                      otp: { type: 'string' },
                    },
                  },
                },
              },
            },
            responses: { 200: { description: 'Token pair' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/auth/refresh`]: {
          post: {
            tags: ['Auth'],
            summary: 'Rotate refresh token',
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['refreshToken'],
                    properties: { refreshToken: { type: 'string' } },
                  },
                },
              },
            },
            responses: { 200: { description: 'New token pair' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/auth/logout`]: {
          post: {
            tags: ['Auth'],
            summary: 'Revoke current refresh session',
            responses: { 200: { description: 'Logged out' } },
          },
        },
        [`${API_PREFIX}/auth/logout-all`]: {
          post: {
            tags: ['Auth'],
            summary: 'Revoke all sessions',
            security: adminSecurity,
            responses: { 200: { description: 'All sessions revoked' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/auth/me`]: {
          get: {
            tags: ['Auth'],
            summary: 'Authenticated profile',
            security: adminSecurity,
            responses: { 200: { description: 'Profile' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/society`]: {
          get: {
            tags: ['Admin Society'],
            summary: 'Get current admin society',
            description: 'Admin only. Society context resolved from membership (optional x-society-id).',
            security: adminSecurity,
            parameters: [
              {
                name: 'x-society-id',
                in: 'header',
                required: false,
                schema: { type: 'string' },
                description: 'Optional society ObjectId; must match an ADMIN membership',
              },
            ],
            responses: {
              200: {
                description: 'Society',
                content: {
                  'application/json': {
                    schema: {
                      type: 'object',
                      properties: {
                        success: { type: 'boolean' },
                        data: { $ref: '#/components/schemas/Society' },
                      },
                    },
                  },
                },
              },
              ...errorResponses,
            },
          },
          patch: {
            tags: ['Admin Society'],
            summary: 'Update society configuration fields',
            description: 'Cannot change society code or id. Audited.',
            security: adminSecurity,
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    properties: {
                      name: { type: 'string' },
                      address: { type: 'string' },
                      city: { type: 'string' },
                      state: { type: 'string' },
                      pincode: { type: 'string' },
                      contactEmail: { type: 'string', format: 'email' },
                      contactPhone: { type: 'string' },
                      timezone: { type: 'string', example: 'Asia/Kolkata' },
                      currency: { type: 'string' },
                      maintenanceDayOfMonth: { type: 'integer' },
                      isActive: { type: 'boolean' },
                    },
                  },
                },
              },
            },
            responses: { 200: { description: 'Updated society' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/society/configuration`]: {
          get: {
            tags: ['Admin Society'],
            summary: 'Society configuration with wing/flat totals',
            security: adminSecurity,
            responses: { 200: { description: 'Configuration snapshot' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/wings`]: {
          get: {
            tags: ['Admin Wings'],
            summary: 'List wings with flat counts',
            security: adminSecurity,
            responses: { 200: { description: 'Wing list' }, ...errorResponses },
          },
          post: {
            tags: ['Admin Wings'],
            summary: 'Create wing',
            security: adminSecurity,
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['name', 'code'],
                    properties: {
                      name: { type: 'string' },
                      code: { type: 'string' },
                      floors: { type: 'integer', default: 7 },
                      flatsPerFloor: { type: 'integer', default: 4 },
                      sortOrder: { type: 'integer' },
                      isActive: { type: 'boolean' },
                    },
                  },
                },
              },
            },
            responses: { 201: { description: 'Created' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/wings/{wingId}`]: {
          get: {
            tags: ['Admin Wings'],
            summary: 'Get wing',
            security: adminSecurity,
            parameters: [{ name: 'wingId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Wing' }, ...errorResponses },
          },
          patch: {
            tags: ['Admin Wings'],
            summary: 'Update wing',
            security: adminSecurity,
            parameters: [{ name: 'wingId', in: 'path', required: true, schema: { type: 'string' } }],
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    properties: {
                      name: { type: 'string' },
                      code: { type: 'string' },
                      floors: { type: 'integer' },
                      flatsPerFloor: { type: 'integer' },
                      sortOrder: { type: 'integer' },
                      isActive: { type: 'boolean' },
                    },
                  },
                },
              },
            },
            responses: { 200: { description: 'Updated wing' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/flats`]: {
          get: {
            tags: ['Admin Flats'],
            summary: 'List flats with filters and pagination',
            security: adminSecurity,
            parameters: [
              { name: 'wingId', in: 'query', schema: { type: 'string' } },
              { name: 'floor', in: 'query', schema: { type: 'integer' } },
              { name: 'flatType', in: 'query', schema: { type: 'string', enum: ['2BHK', '3BHK'] } },
              {
                name: 'occupancyStatus',
                in: 'query',
                schema: { type: 'string', enum: ['OWNER_OCCUPIED', 'TENANT_OCCUPIED', 'VACANT'] },
              },
              { name: 'isActive', in: 'query', schema: { type: 'string', enum: ['true', 'false'] } },
              { name: 'search', in: 'query', schema: { type: 'string' }, description: 'Flat number search' },
              { name: 'page', in: 'query', schema: { type: 'integer', default: 1 } },
              { name: 'limit', in: 'query', schema: { type: 'integer', default: 20, maximum: 100 } },
              {
                name: 'sortBy',
                in: 'query',
                schema: {
                  type: 'string',
                  enum: ['number', 'floor', 'position', 'maintenanceRate', 'createdAt', 'updatedAt'],
                },
              },
              { name: 'sortOrder', in: 'query', schema: { type: 'string', enum: ['asc', 'desc'] } },
            ],
            responses: { 200: { description: 'Paginated flats' }, ...errorResponses },
          },
          post: {
            tags: ['Admin Flats'],
            summary: 'Create flat',
            security: adminSecurity,
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['wingId', 'number', 'floor', 'position', 'flatType', 'maintenanceRate'],
                    properties: {
                      wingId: { type: 'string' },
                      number: { type: 'string' },
                      floor: { type: 'integer' },
                      position: { type: 'integer' },
                      flatType: { type: 'string', enum: ['2BHK', '3BHK'] },
                      maintenanceRate: { type: 'number' },
                      parking: {
                        type: 'object',
                        properties: {
                          hasParking: { type: 'boolean' },
                          slotLabel: { type: 'string' },
                        },
                      },
                      notes: { type: 'string' },
                    },
                  },
                },
              },
            },
            responses: { 201: { description: 'Created' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/flats/{flatId}`]: {
          get: {
            tags: ['Admin Flats'],
            summary: 'Get flat',
            security: adminSecurity,
            parameters: [{ name: 'flatId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Flat' }, ...errorResponses },
          },
          patch: {
            tags: ['Admin Flats'],
            summary: 'Update flat (soft-deactivate with safeguards)',
            description:
              'Does not accept occupancyStatus, activeOwnerUserId or activeTenantUserId. Use occupancy lifecycle endpoints.',
            security: adminSecurity,
            parameters: [{ name: 'flatId', in: 'path', required: true, schema: { type: 'string' } }],
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    properties: {
                      number: { type: 'string' },
                      floor: { type: 'integer' },
                      position: { type: 'integer' },
                      flatType: { type: 'string', enum: ['2BHK', '3BHK'] },
                      maintenanceRate: { type: 'number' },
                      isActive: { type: 'boolean' },
                      forceDeactivate: { type: 'boolean' },
                      deactivationReason: { type: 'string' },
                      parking: { type: 'object' },
                      notes: { type: 'string' },
                    },
                  },
                },
              },
            },
            responses: { 200: { description: 'Updated flat' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/flats/{flatId}/residents`]: {
          get: {
            tags: ['Admin Flats'],
            summary: 'Active residents + occupancy history foundation',
            security: adminSecurity,
            parameters: [{ name: 'flatId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Residents snapshot' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/flats/{flatId}/assign-owner`]: {
          post: {
            tags: ['Occupancy'],
            summary: 'Assign owner to a vacant flat',
            security: adminSecurity,
            parameters: [{ name: 'flatId', in: 'path', required: true, schema: { type: 'string' } }],
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['userId', 'effectiveFrom'],
                    properties: {
                      userId: { type: 'string' },
                      effectiveFrom: { type: 'string', format: 'date-time' },
                      notes: { type: 'string' },
                    },
                  },
                },
              },
            },
            responses: { 201: { description: 'Owner assigned' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/flats/{flatId}/assign-tenant`]: {
          post: {
            tags: ['Occupancy'],
            summary: 'Assign tenant to an owner-occupied flat',
            security: adminSecurity,
            parameters: [{ name: 'flatId', in: 'path', required: true, schema: { type: 'string' } }],
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['userId', 'effectiveFrom'],
                    properties: {
                      userId: { type: 'string' },
                      effectiveFrom: { type: 'string', format: 'date-time' },
                      notes: { type: 'string' },
                    },
                  },
                },
              },
            },
            responses: { 201: { description: 'Tenant assigned' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/flats/{flatId}/end-owner-occupancy`]: {
          post: {
            tags: ['Occupancy'],
            summary: 'End owner occupancy (tenant must be ended first)',
            security: adminSecurity,
            parameters: [{ name: 'flatId', in: 'path', required: true, schema: { type: 'string' } }],
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['effectiveTo', 'reason'],
                    properties: {
                      effectiveTo: { type: 'string', format: 'date-time' },
                      reason: { type: 'string' },
                      notes: { type: 'string' },
                    },
                  },
                },
              },
            },
            responses: { 200: { description: 'Owner occupancy ended' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/flats/{flatId}/end-tenant-occupancy`]: {
          post: {
            tags: ['Occupancy'],
            summary: 'End tenant occupancy (owner remains)',
            security: adminSecurity,
            parameters: [{ name: 'flatId', in: 'path', required: true, schema: { type: 'string' } }],
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['effectiveTo', 'reason'],
                    properties: {
                      effectiveTo: { type: 'string', format: 'date-time' },
                      reason: { type: 'string' },
                      notes: { type: 'string' },
                    },
                  },
                },
              },
            },
            responses: { 200: { description: 'Tenant occupancy ended' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/flats/{flatId}/occupancy-history`]: {
          get: {
            tags: ['Occupancy'],
            summary: 'Flat occupancy history',
            security: adminSecurity,
            parameters: [
              { name: 'flatId', in: 'path', required: true, schema: { type: 'string' } },
              { name: 'page', in: 'query', schema: { type: 'integer' } },
              { name: 'limit', in: 'query', schema: { type: 'integer' } },
            ],
            responses: { 200: { description: 'History' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/occupancies`]: {
          get: {
            tags: ['Occupancy'],
            summary: 'List occupancy records',
            security: adminSecurity,
            parameters: [
              { name: 'status', in: 'query', schema: { type: 'string', enum: ['ACTIVE', 'ENDED'] } },
              { name: 'role', in: 'query', schema: { type: 'string', enum: ['OWNER', 'TENANT'] } },
              { name: 'flatId', in: 'query', schema: { type: 'string' } },
              { name: 'userId', in: 'query', schema: { type: 'string' } },
              { name: 'page', in: 'query', schema: { type: 'integer' } },
              { name: 'limit', in: 'query', schema: { type: 'integer' } },
            ],
            responses: { 200: { description: 'Occupancy list' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/users`]: {
          get: {
            tags: ['Admin Users'],
            summary: 'Search/list society users',
            security: adminSecurity,
            parameters: [
              { name: 'search', in: 'query', schema: { type: 'string' } },
              { name: 'role', in: 'query', schema: { type: 'string' } },
              { name: 'isActive', in: 'query', schema: { type: 'string', enum: ['true', 'false'] } },
              { name: 'page', in: 'query', schema: { type: 'integer' } },
              { name: 'limit', in: 'query', schema: { type: 'integer' } },
            ],
            responses: { 200: { description: 'Users' }, ...errorResponses },
          },
          post: {
            tags: ['Admin Users'],
            summary: 'Provision OWNER or TENANT (no flat assignment)',
            security: adminSecurity,
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['name', 'email', 'role'],
                    properties: {
                      name: { type: 'string' },
                      email: { type: 'string', format: 'email' },
                      phone: { type: 'string' },
                      role: { type: 'string', enum: ['OWNER', 'TENANT'] },
                    },
                  },
                },
              },
            },
            responses: { 201: { description: 'Provisioned' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/users/{userId}`]: {
          get: {
            tags: ['Admin Users'],
            summary: 'Get user',
            security: adminSecurity,
            parameters: [{ name: 'userId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'User' }, ...errorResponses },
          },
          patch: {
            tags: ['Admin Users'],
            summary: 'Update resident profile fields (no ADMIN/GUARD privilege changes)',
            security: adminSecurity,
            parameters: [{ name: 'userId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Updated' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/users/{userId}/deactivate`]: {
          post: {
            tags: ['Admin Users'],
            summary: 'Deactivate resident (not self; not ADMIN/GUARD)',
            security: adminSecurity,
            parameters: [{ name: 'userId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Deactivated' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/profile`]: {
          get: {
            tags: ['Resident'],
            summary: 'Resident profile',
            security: adminSecurity,
            responses: { 200: { description: 'Profile' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/flats`]: {
          get: {
            tags: ['Resident'],
            summary: 'Flats accessible to the resident',
            security: adminSecurity,
            responses: { 200: { description: 'Flat list with access flags' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/flats/{flatId}`]: {
          get: {
            tags: ['Resident'],
            summary: 'Resident flat detail (access-filtered)',
            security: adminSecurity,
            parameters: [{ name: 'flatId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Flat' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/flats/{flatId}/occupancy`]: {
          get: {
            tags: ['Resident'],
            summary: 'Occupancy view permitted for the resident',
            security: adminSecurity,
            parameters: [{ name: 'flatId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Occupancy' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/dashboard`]: {
          get: {
            tags: ['Admin Dashboard'],
            summary: 'Society dashboard statistics from MongoDB',
            security: adminSecurity,
            responses: {
              200: {
                description: 'Dashboard stats',
                content: {
                  'application/json': {
                    schema: {
                      type: 'object',
                      properties: {
                        success: { type: 'boolean' },
                        data: { $ref: '#/components/schemas/Dashboard' },
                      },
                    },
                  },
                },
              },
              ...errorResponses,
            },
          },
        },
        [`${API_PREFIX}/admin/billing/generate`]: {
          post: {
            tags: ['Admin Billing'],
            summary: 'Generate monthly or 3-month prepaid maintenance bills',
            description:
              'Bills only active flats with an active owner. Skips vacant/unassigned. Idempotent for overlapping periods (conflicts returned, not overwritten). Due date = 10th of first billing month (society timezone).',
            security: adminSecurity,
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['billingPeriodStart', 'numberOfMonths'],
                    properties: {
                      billingPeriodStart: { type: 'string', format: 'date-time', example: '2026-04-01T00:00:00.000+05:30' },
                      numberOfMonths: { type: 'integer', enum: [1, 3] },
                      notes: { type: 'string' },
                    },
                  },
                },
              },
            },
            responses: { 201: { description: 'Generation summary' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/billing/bills`]: {
          get: {
            tags: ['Admin Billing'],
            summary: 'List bills',
            security: adminSecurity,
            parameters: [
              { name: 'status', in: 'query', schema: { type: 'string' } },
              { name: 'wingCode', in: 'query', schema: { type: 'string' } },
              { name: 'flatId', in: 'query', schema: { type: 'string' } },
              { name: 'ownerUserId', in: 'query', schema: { type: 'string' } },
              { name: 'billingPeriodStart', in: 'query', schema: { type: 'string', format: 'date-time' } },
            ],
            responses: { 200: { description: 'Bill list' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/billing/bills/{billId}`]: {
          get: {
            tags: ['Admin Billing'],
            summary: 'Get bill',
            security: adminSecurity,
            parameters: [{ name: 'billId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Bill' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/billing/bills/{billId}/interest`]: {
          get: {
            tags: ['Admin Billing'],
            summary: 'Interest breakdown as of a date',
            description:
              'Segment simple interest from the immutable principal ledger: floor(principal × 2400bps × days / (10000 × 365)) per civil-day principal level. Accrual starts on the 11th when due is the 10th. Partial payments reduce principal from civil midnight of settlement; past segments are not backfilled. No compounding.',
            security: adminSecurity,
            parameters: [
              { name: 'billId', in: 'path', required: true, schema: { type: 'string' } },
              { name: 'asOf', in: 'query', schema: { type: 'string', format: 'date-time' } },
            ],
            responses: { 200: { description: 'Interest breakdown' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/billing/summary`]: {
          get: {
            tags: ['Admin Billing'],
            summary: 'Billing dashboard summary',
            security: adminSecurity,
            responses: { 200: { description: 'Summary + wing-wise collection' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/billing/eligible-flats`]: {
          get: {
            tags: ['Admin Billing'],
            summary: 'Flats eligible for bill generation',
            security: adminSecurity,
            responses: { 200: { description: 'Eligible flats' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/payments/offline`]: {
          post: {
            tags: ['Admin Payments'],
            summary: 'Record offline payment (requires OFFLINE_PAYMENTS_ENABLED=true)',
            security: adminSecurity,
            responses: { 201: { description: 'Settled payment' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/payments`]: {
          get: {
            tags: ['Admin Payments'],
            summary: 'List payments',
            security: adminSecurity,
            responses: { 200: { description: 'Payments' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/payments/{paymentId}`]: {
          get: {
            tags: ['Admin Payments'],
            summary: 'Get payment',
            security: adminSecurity,
            parameters: [{ name: 'paymentId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Payment' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/receipts/{receiptId}`]: {
          get: {
            tags: ['Admin Receipts'],
            summary: 'Get immutable receipt (+ PDF base64)',
            security: adminSecurity,
            parameters: [{ name: 'receiptId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Receipt' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/billing/bills`]: {
          get: {
            tags: ['Resident Billing'],
            summary: 'List own bills (OWNER + financial access only; tenants rejected)',
            security: adminSecurity,
            responses: { 200: { description: 'Bills' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/billing/bills/{billId}/payment-order`]: {
          post: {
            tags: ['Resident Billing'],
            summary: 'Create UPI payment order for outstanding principal (server-side amount)',
            security: adminSecurity,
            parameters: [{ name: 'billId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 201: { description: 'Order + pending payment' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/billing/verify-payment`]: {
          post: {
            tags: ['Resident Billing'],
            summary: 'Verify gateway signature and settle payment',
            security: adminSecurity,
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['orderId', 'paymentId', 'signature'],
                    properties: {
                      orderId: { type: 'string' },
                      paymentId: { type: 'string' },
                      signature: { type: 'string' },
                    },
                  },
                },
              },
            },
            responses: { 200: { description: 'Settlement result' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/billing/payments`]: {
          get: {
            tags: ['Resident Billing'],
            summary: 'List own payments',
            security: adminSecurity,
            responses: { 200: { description: 'Payments' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/billing/receipts`]: {
          get: {
            tags: ['Resident Billing'],
            summary: 'List own receipts',
            security: adminSecurity,
            responses: { 200: { description: 'Receipts' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/billing/receipts/{receiptId}`]: {
          get: {
            tags: ['Resident Billing'],
            summary: 'Get own receipt (+ PDF base64)',
            security: adminSecurity,
            parameters: [{ name: 'receiptId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Receipt' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/webhooks/payments`]: {
          post: {
            tags: ['Webhooks'],
            summary: 'Payment gateway webhook (Razorpay-compatible signature)',
            description:
              'Requires header x-razorpay-signature. Idempotent settlement. Secrets never logged.',
            parameters: [
              { name: 'x-razorpay-signature', in: 'header', required: true, schema: { type: 'string' } },
            ],
            responses: { 200: { description: 'Webhook processed' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/guards`]: {
          post: {
            tags: ['Admin Guards'],
            summary: 'Provision a guard (no public registration)',
            security: adminSecurity,
            responses: { 201: { description: 'Guard created' }, ...errorResponses },
          },
          get: {
            tags: ['Admin Guards'],
            summary: 'List guards',
            security: adminSecurity,
            responses: { 200: { description: 'Guards' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/guard/visitors`]: {
          post: {
            tags: ['Guard Visitors'],
            summary: 'Register a visitor request for resident approval',
            security: adminSecurity,
            responses: { 201: { description: 'Visitor request created' }, ...errorResponses },
          },
          get: {
            tags: ['Guard Visitors'],
            summary: 'List society visitors (masked phone)',
            security: adminSecurity,
            responses: { 200: { description: 'Visitors' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/guard/visitors/{visitorId}/verify-entry-otp`]: {
          post: {
            tags: ['Guard Visitors'],
            summary: 'Verify entry OTP and mark ENTERED',
            security: adminSecurity,
            parameters: [{ name: 'visitorId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Entered' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/visitors/{visitorId}/approve`]: {
          post: {
            tags: ['Resident Visitors'],
            summary: 'Approve visitor and trigger hashed OTP delivery',
            security: adminSecurity,
            parameters: [{ name: 'visitorId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Approved' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/visitors`]: {
          get: {
            tags: ['Admin Visitors'],
            summary: 'Society visitor history with filters',
            security: adminSecurity,
            responses: { 200: { description: 'Visitors' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/vehicles`]: {
          post: {
            tags: ['Resident Vehicles'],
            summary: 'Register a vehicle for a residentially accessible flat',
            description:
              'Requires residential access (owner when OWNER_OCCUPIED, active tenant when TENANT_OCCUPIED). Registration numbers are normalized (uppercase, no spaces/hyphens). Duplicate active plates in the same society return 409.',
            security: adminSecurity,
            parameters: [
              { name: 'x-society-id', in: 'header', required: false, schema: { type: 'string' } },
            ],
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['flatId', 'vehicleType', 'registrationNumber'],
                    properties: {
                      flatId: { type: 'string' },
                      vehicleType: { type: 'string', enum: ['TWO_WHEELER', 'FOUR_WHEELER', 'OTHER'] },
                      registrationNumber: { type: 'string', example: 'MH12AB1234' },
                      make: { type: 'string' },
                      model: { type: 'string' },
                      colour: { type: 'string' },
                    },
                  },
                },
              },
            },
            responses: {
              201: { description: 'Vehicle registered' },
              ...errorResponses,
            },
          },
          get: {
            tags: ['Resident Vehicles'],
            summary: 'List vehicles for residentially accessible flats',
            security: adminSecurity,
            responses: { 200: { description: 'Vehicles' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/vehicles/{vehicleId}`]: {
          get: {
            tags: ['Resident Vehicles'],
            summary: 'Get vehicle details (residential access required)',
            security: adminSecurity,
            parameters: [{ name: 'vehicleId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Vehicle' }, ...errorResponses },
          },
          patch: {
            tags: ['Resident Vehicles'],
            summary: 'Update permitted vehicle fields',
            security: adminSecurity,
            parameters: [{ name: 'vehicleId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Updated' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/vehicles/{vehicleId}/deactivate`]: {
          post: {
            tags: ['Resident Vehicles'],
            summary: 'Deactivate vehicle (soft; history preserved)',
            security: adminSecurity,
            parameters: [{ name: 'vehicleId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Deactivated' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/parking`]: {
          get: {
            tags: ['Resident Parking'],
            summary: 'Active parking allocations for residentially accessible flats',
            security: adminSecurity,
            responses: { 200: { description: 'Allocations with slot/vehicle' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/parking/allocations/{allocationId}`]: {
          get: {
            tags: ['Resident Parking'],
            summary: 'Allocation detail with slot (residential access required)',
            security: adminSecurity,
            parameters: [
              { name: 'allocationId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 200: { description: 'Allocation' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/vehicles`]: {
          get: {
            tags: ['Admin Vehicles'],
            summary: 'List society vehicles with filters',
            security: adminSecurity,
            responses: { 200: { description: 'Vehicles' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/parking/slots`]: {
          post: {
            tags: ['Admin Parking'],
            summary: 'Create parking slot',
            description: 'Duplicate active slot numbers in the same society return 409.',
            security: adminSecurity,
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['slotNumber', 'parkingType'],
                    properties: {
                      slotNumber: { type: 'string' },
                      parkingType: {
                        type: 'string',
                        enum: ['TWO_WHEELER', 'FOUR_WHEELER', 'OTHER'],
                      },
                      locationDescription: { type: 'string' },
                    },
                  },
                },
              },
            },
            responses: { 201: { description: 'Slot created' }, ...errorResponses },
          },
          get: {
            tags: ['Admin Parking'],
            summary: 'List parking slots (pagination, type, availability filters)',
            security: adminSecurity,
            parameters: [
              {
                name: 'availability',
                in: 'query',
                schema: { type: 'string', enum: ['available', 'occupied', 'all'] },
              },
            ],
            responses: { 200: { description: 'Slots' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/parking/slots/{slotId}`]: {
          get: {
            tags: ['Admin Parking'],
            summary: 'Parking slot details',
            security: adminSecurity,
            parameters: [{ name: 'slotId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Slot' }, ...errorResponses },
          },
          patch: {
            tags: ['Admin Parking'],
            summary: 'Update slot details',
            security: adminSecurity,
            parameters: [{ name: 'slotId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Updated' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/parking/slots/{slotId}/set-active`]: {
          post: {
            tags: ['Admin Parking'],
            summary: 'Activate or deactivate a slot',
            description: 'Cannot deactivate an occupied slot (409 SLOT_OCCUPIED).',
            security: adminSecurity,
            parameters: [{ name: 'slotId', in: 'path', required: true, schema: { type: 'string' } }],
            responses: { 200: { description: 'Updated' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/parking/summary`]: {
          get: {
            tags: ['Admin Parking'],
            summary: 'Parking occupancy and availability summary',
            security: adminSecurity,
            responses: { 200: { description: 'Summary' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/parking/allocations`]: {
          post: {
            tags: ['Admin Parking'],
            summary: 'Allocate a parking slot to a flat/vehicle',
            description:
              'Vehicle, flat, and slot must share society. Slot type must match vehicle type. One active allocation per slot and per vehicle (partial unique indexes + transactions).',
            security: adminSecurity,
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['flatId', 'vehicleId', 'parkingSlotId'],
                    properties: {
                      flatId: { type: 'string' },
                      vehicleId: { type: 'string' },
                      parkingSlotId: { type: 'string' },
                      startsAt: { type: 'string', format: 'date-time' },
                    },
                  },
                },
              },
            },
            responses: { 201: { description: 'Allocated' }, ...errorResponses },
          },
          get: {
            tags: ['Admin Parking'],
            summary: 'List allocations (includes historical ENDED)',
            security: adminSecurity,
            responses: { 200: { description: 'Allocations' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/parking/allocations/{allocationId}`]: {
          get: {
            tags: ['Admin Parking'],
            summary: 'Allocation details',
            security: adminSecurity,
            parameters: [
              { name: 'allocationId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 200: { description: 'Allocation' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/parking/allocations/{allocationId}/release`]: {
          post: {
            tags: ['Admin Parking'],
            summary: 'End/release an active allocation',
            security: adminSecurity,
            parameters: [
              { name: 'allocationId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 200: { description: 'Released' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/guard/vehicles/entry`]: {
          post: {
            tags: ['Guard Vehicles'],
            summary: 'Record vehicle entry',
            description:
              'Optional vehicleId links a registered resident vehicle. Unregistered plates require vehicleType and are never auto-converted into resident Vehicle records. Duplicate active INSIDE sessions for the same plate return 409.',
            security: adminSecurity,
            requestBody: {
              required: true,
              content: {
                'application/json': {
                  schema: {
                    type: 'object',
                    required: ['registrationNumber'],
                    properties: {
                      registrationNumber: { type: 'string' },
                      vehicleType: {
                        type: 'string',
                        enum: ['TWO_WHEELER', 'FOUR_WHEELER', 'OTHER'],
                      },
                      vehicleId: { type: 'string' },
                      notes: { type: 'string' },
                    },
                  },
                },
              },
            },
            responses: { 201: { description: 'Entry recorded' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/guard/vehicles/exit`]: {
          post: {
            tags: ['Guard Vehicles'],
            summary: 'Record vehicle exit by logId or registrationNumber',
            security: adminSecurity,
            responses: { 200: { description: 'Exit recorded' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/guard/vehicles/logs`]: {
          get: {
            tags: ['Guard Vehicles'],
            summary: 'List society vehicle entry/exit logs',
            security: adminSecurity,
            responses: { 200: { description: 'Logs' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/complaints`]: {
          post: {
            tags: ['Resident Complaints'],
            summary: 'Create a complaint for a residentially accessible flat',
            description:
              'Requires residential access. Priority defaults to MEDIUM. Lifecycle history starts with CREATED.',
            security: adminSecurity,
            responses: { 201: { description: 'Created' }, ...errorResponses },
          },
          get: {
            tags: ['Resident Complaints'],
            summary: 'List authorized complaints',
            security: adminSecurity,
            responses: { 200: { description: 'Complaints' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/complaints/{complaintId}`]: {
          get: {
            tags: ['Resident Complaints'],
            summary: 'Complaint detail with public history (no internal notes)',
            security: adminSecurity,
            parameters: [
              { name: 'complaintId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 200: { description: 'Complaint' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/complaints/{complaintId}/cancel`]: {
          post: {
            tags: ['Resident Complaints'],
            summary: 'Cancel own OPEN complaint',
            security: adminSecurity,
            parameters: [
              { name: 'complaintId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 200: { description: 'Cancelled' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/complaints/{complaintId}/attachments`]: {
          post: {
            tags: ['Resident Complaints'],
            summary: 'Upload image attachment (multipart field: file)',
            security: adminSecurity,
            parameters: [
              { name: 'complaintId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 201: { description: 'Uploaded' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/complaints`]: {
          get: {
            tags: ['Admin Complaints'],
            summary: 'List society complaints with filters',
            security: adminSecurity,
            responses: { 200: { description: 'Complaints' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/complaints/summary`]: {
          get: {
            tags: ['Admin Complaints'],
            summary: 'Dashboard counts by status/category/priority',
            security: adminSecurity,
            responses: { 200: { description: 'Summary' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/complaints/categories`]: {
          get: {
            tags: ['Admin Complaints'],
            summary: 'Supported complaint categories',
            security: adminSecurity,
            responses: { 200: { description: 'Categories' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/complaints/{complaintId}/priority`]: {
          patch: {
            tags: ['Admin Complaints'],
            summary: 'Update priority (admin only)',
            security: adminSecurity,
            parameters: [
              { name: 'complaintId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 200: { description: 'Updated' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/complaints/{complaintId}/assign`]: {
          post: {
            tags: ['Admin Complaints'],
            summary: 'Assign INTERNAL (ADMIN/OWNER) or EXTERNAL vendor',
            description:
              'Does not create User records for vendors. Invalid transitions return 409.',
            security: adminSecurity,
            parameters: [
              { name: 'complaintId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 200: { description: 'Assigned' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/complaints/{complaintId}/unassign`]: {
          post: {
            tags: ['Admin Complaints'],
            summary: 'Return ASSIGNED complaint to OPEN',
            security: adminSecurity,
            parameters: [
              { name: 'complaintId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 200: { description: 'Unassigned' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/complaints/{complaintId}/start`]: {
          post: {
            tags: ['Admin Complaints'],
            summary: 'Mark ASSIGNED complaint IN_PROGRESS',
            security: adminSecurity,
            parameters: [
              { name: 'complaintId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 200: { description: 'Started' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/complaints/{complaintId}/resolve`]: {
          post: {
            tags: ['Admin Complaints'],
            summary: 'Resolve with mandatory resolutionNotes',
            security: adminSecurity,
            parameters: [
              { name: 'complaintId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 200: { description: 'Resolved' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/complaints/{complaintId}/close`]: {
          post: {
            tags: ['Admin Complaints'],
            summary: 'Close a RESOLVED complaint (preserves resolution)',
            security: adminSecurity,
            parameters: [
              { name: 'complaintId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 200: { description: 'Closed' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/complaints/{complaintId}/cancel`]: {
          post: {
            tags: ['Admin Complaints'],
            summary: 'Cancel with mandatory reason',
            security: adminSecurity,
            parameters: [
              { name: 'complaintId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 200: { description: 'Cancelled' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/staff`]: {
          post: {
            tags: ['Admin Staff'],
            summary: 'Create society staff employment record (no User created)',
            security: adminSecurity,
            responses: { 201: { description: 'Created' }, ...errorResponses },
          },
          get: {
            tags: ['Admin Staff'],
            summary: 'List staff with filters',
            security: adminSecurity,
            responses: { 200: { description: 'Staff list' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/staff-attendance`]: {
          post: {
            tags: ['Admin Staff'],
            summary: 'Mark attendance (admin only; one record per staff per local date)',
            security: adminSecurity,
            responses: { 201: { description: 'Marked' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/staff-shifts`]: {
          post: {
            tags: ['Admin Staff'],
            summary: 'Create shift (overnight supported; overlaps rejected)',
            security: adminSecurity,
            responses: { 201: { description: 'Created' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/facilities`]: {
          post: {
            tags: ['Admin Facilities'],
            summary: 'Create facility',
            security: adminSecurity,
            responses: { 201: { description: 'Created' }, ...errorResponses },
          },
          get: {
            tags: ['Admin Facilities'],
            summary: 'List facilities',
            security: adminSecurity,
            responses: { 200: { description: 'Facilities' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/facility-bookings/{bookingId}/approve`]: {
          post: {
            tags: ['Admin Facilities'],
            summary: 'Approve pending booking (capacity enforced transactionally)',
            security: adminSecurity,
            parameters: [
              { name: 'bookingId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 200: { description: 'Approved' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/facilities`]: {
          get: {
            tags: ['Resident Facilities'],
            summary: 'List active facilities in society',
            security: adminSecurity,
            responses: { 200: { description: 'Facilities' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/facilities/{facilityId}/bookings`]: {
          post: {
            tags: ['Resident Facilities'],
            summary: 'Create booking (residential access; PENDING unless auto-confirm)',
            description:
              'Only CONFIRMED bookings consume capacity. PENDING expires after FACILITY_PENDING_BOOKING_TTL_MS. Fees are never marked paid in Phase 8.',
            security: adminSecurity,
            parameters: [
              { name: 'facilityId', in: 'path', required: true, schema: { type: 'string' } },
            ],
            responses: { 201: { description: 'Booking created' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/announcements`]: {
          get: {
            tags: ['Admin Announcements'],
            summary: 'List announcements (filters + pagination)',
            security: adminSecurity,
            responses: { 200: { description: 'Announcement list' }, ...errorResponses },
          },
          post: {
            tags: ['Admin Announcements'],
            summary: 'Create draft announcement',
            description:
              'Audience criteria stored on the announcement. Recipients resolved from live occupancy at publish time.',
            security: adminSecurity,
            responses: { 201: { description: 'Draft created' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/announcements/summary`]: {
          get: {
            tags: ['Admin Announcements'],
            summary: 'Announcement dashboard counts by status',
            security: adminSecurity,
            responses: { 200: { description: 'Summary' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/announcements/{announcementId}/publish`]: {
          post: {
            tags: ['Admin Announcements'],
            summary: 'Publish immediately and create recipient notifications',
            security: adminSecurity,
            responses: { 200: { description: 'Published' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/announcements/{announcementId}/schedule`]: {
          post: {
            tags: ['Admin Announcements'],
            summary: 'Schedule publication (worker publishes at/after scheduledAt)',
            security: adminSecurity,
            responses: { 200: { description: 'Scheduled' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/announcements/{announcementId}/recipients`]: {
          get: {
            tags: ['Admin Announcements'],
            summary: 'Delivery summary (eligible / notifications created / reads)',
            description:
              'notificationCreatedCount is persistence count, not confirmed push delivery.',
            security: adminSecurity,
            responses: { 200: { description: 'Recipient summary' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/announcements`]: {
          get: {
            tags: ['Resident Announcements'],
            summary: 'Active announcements visible under current residential occupancy',
            security: adminSecurity,
            responses: { 200: { description: 'Announcements' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/announcements/unread-count`]: {
          get: {
            tags: ['Resident Announcements'],
            summary: 'Unread announcement count for current resident',
            security: adminSecurity,
            responses: { 200: { description: 'Unread count' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/notifications`]: {
          get: {
            tags: ['Resident Notifications'],
            summary: 'List notifications for the authenticated recipient only',
            security: adminSecurity,
            responses: { 200: { description: 'Notifications' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/notifications/unread-count`]: {
          get: {
            tags: ['Resident Notifications'],
            summary: 'Unread notification count',
            security: adminSecurity,
            responses: { 200: { description: 'Unread count' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/resident/notifications/read-all`]: {
          post: {
            tags: ['Resident Notifications'],
            summary: 'Mark all notifications read (idempotent)',
            security: adminSecurity,
            responses: { 200: { description: 'Updated count' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/reports/dashboard`]: {
          get: {
            tags: ['Admin Reports'],
            summary: 'Compact financial, collection, outstanding, and complaint overview',
            description:
              'Admin-only. Date range defaults to last 365 days; max span 3 years. Bill metrics use billingPeriodStart and stored paise snapshots.',
            security: adminSecurity,
            responses: { 200: { description: 'Dashboard analytics' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/reports/financial`]: {
          get: {
            tags: ['Admin Reports'],
            summary: 'Financial report with monthly/yearly summaries and payment breakdowns',
            security: adminSecurity,
            responses: { 200: { description: 'Financial report' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/reports/collections`]: {
          get: {
            tags: ['Admin Reports'],
            summary: 'Collection performance, wing-wise breakdown, monthly trends',
            description:
              'collectionPercentage = floor(collectedPaise * 10000 / billedPaise) / 100; 0 when billed is 0.',
            security: adminSecurity,
            responses: { 200: { description: 'Collection report' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/reports/outstanding`]: {
          get: {
            tags: ['Admin Reports'],
            summary: 'Flat-wise outstanding balances (paginated)',
            security: adminSecurity,
            responses: { 200: { description: 'Outstanding dues' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/reports/complaints`]: {
          get: {
            tags: ['Admin Reports'],
            summary: 'Complaint analytics (status, category, wing, resolution time, workload)',
            security: adminSecurity,
            responses: { 200: { description: 'Complaint analytics' }, ...errorResponses },
          },
        },
        [`${API_PREFIX}/admin/reports/export/{type}`]: {
          get: {
            tags: ['Admin Reports'],
            summary: 'Stream CSV export (financial|collections|outstanding|payments|complaints)',
            description:
              'Formula-injection safe CSV. Streams via Mongo cursor. Amounts exported as rupees from integer paise.',
            security: adminSecurity,
            parameters: [
              {
                name: 'type',
                in: 'path',
                required: true,
                schema: {
                  type: 'string',
                  enum: ['financial', 'collections', 'outstanding', 'payments', 'complaints'],
                },
              },
            ],
            responses: {
              200: { description: 'text/csv stream' },
              ...errorResponses,
            },
          },
        },
      },
    },
    apis: [],
  });
}
