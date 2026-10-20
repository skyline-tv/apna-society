import { UserModel } from '../models/user.model';

export async function listUsers(limit = 100) {
  const users = await UserModel.find()
    .select('-__v')
    .sort({ createdAt: -1 })
    .limit(limit)
    .lean();

  return users.map((user) => ({
    id: String(user._id),
    email: user.email,
    name: user.name,
    roles: user.roles,
    isActive: user.isActive,
    canLogin: user.canLogin,
    primarySocietyId: user.primarySocietyId ? String(user.primarySocietyId) : undefined,
  }));
}
