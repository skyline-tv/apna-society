import { getEmailService } from '../../auth/services/email.service';
import { getLogger } from '../../../utils/logger';
import { getEnv } from '../../../config/env';

/**
 * Email-only visitor entry OTP delivery (no SMS).
 * Test inbox captures OTPs for automated tests without logging OTP values in production.
 */
export const testVisitorOtpInbox: Array<{
  email: string;
  otp: string;
  visitorName: string;
  flatLabel: string;
  at: Date;
}> = [];

export async function deliverVisitorEntryOtp(input: {
  toEmail: string;
  otp: string;
  visitorName: string;
  flatLabel: string;
}): Promise<void> {
  const env = getEnv();
  if (env.NODE_ENV === 'test') {
    testVisitorOtpInbox.push({
      email: input.toEmail,
      otp: input.otp,
      visitorName: input.visitorName,
      flatLabel: input.flatLabel,
      at: new Date(),
    });
    return;
  }

  await getEmailService().sendVisitorEntryOtpEmail({
    to: input.toEmail,
    otp: input.otp,
    visitorName: input.visitorName,
    flatLabel: input.flatLabel,
  });
  getLogger().info(
    { to: input.toEmail, flatLabel: input.flatLabel },
    'Visitor entry OTP emailed (OTP value not logged)',
  );
}

export function clearTestVisitorOtpInbox(): void {
  testVisitorOtpInbox.length = 0;
}
