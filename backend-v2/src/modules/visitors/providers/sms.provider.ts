/**
 * @deprecated SMS is not supported. Visitor OTP is email-only.
 * Re-exports kept so older test imports continue to resolve during migration.
 */
export {
  clearTestVisitorOtpInbox,
  deliverVisitorEntryOtp,
  testVisitorOtpInbox,
} from './visitor-otp-email.provider';
