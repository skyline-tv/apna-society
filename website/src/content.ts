// All legal text lives here. Edit wording without touching layout.
// Anything written as [TO CONFIRM: ...] is a fact that could not be verified from the code
// and must be replaced (or removed) before submitting to Google Play.
export type Block = string | string[]
export interface Section { id: string; title: string; body: Block[] }
export interface PageDef { path: string; nav: string; title: string; description: string; intro: string; updated?: string; sections: Section[] }

export const APP = 'Apna Society'
export const DEVELOPER = 'SkyLine Tech Ventures'
export const DEVELOPER_SITE = 'https://skylinetv.in'
export const LAST_UPDATED = '24 October 2026'
export const SUPPORT_EMAIL = '[TO CONFIRM: support email address]'
/** Set this when the listing is live. The landing page hides the store button while empty. */
export const PLAY_STORE_URL = ''

export const landing = {
  eyebrow: 'Society management app',
  headline: 'Simplifying society management.',
  lede: 'Bills, visitors, vehicles and the gate — in one app for the committee, residents and security.',
  primaryCta: { label: 'Talk to us', to: '/support' },
  secondaryCta: { label: 'Privacy policy', to: '/privacy-policy' },
  storeCta: { label: 'Get it on Google Play', to: PLAY_STORE_URL },
  featuresTitle: 'What the app does',
  featuresLede: 'Built for Indian residential societies: wings, flats, maintenance and the gate.',
  features: [
    { id: 'billing', title: 'Maintenance billing', body: 'Raise monthly bills, other charges and late interest. Admin records cash or cheque at the office. Residents get a PDF receipt.' },
    { id: 'visitors', title: 'Visitors at the gate', body: 'The guard registers a visitor. The owner or tenant approves from their phone. Entry and exit are recorded, with OTP when needed.' },
    { id: 'vehicles', title: 'Vehicles and parking', body: 'Residents register their vehicles. The guard can verify a vehicle at the gate against the society record.' },
    { id: 'roles', title: 'The right screen for each role', body: 'Admin, owner, tenant and guard each see only what their role allows. A rented flat splits financial access and day-to-day residential access.' },
    { id: 'collections', title: 'Collections and charges', body: 'One-time collections and special charges sit next to monthly maintenance, so the society’s accounts stay in one place.' },
    { id: 'announce', title: 'Announcements', body: 'The committee can send notices to residents instead of relying only on the WhatsApp group.' },
  ],
  rolesTitle: 'Who it’s for',
  rolesLede: 'One app. Four roles. Each person opens the screens that apply to them.',
  roles: [
    { id: 'admin', title: 'Admin', body: 'Flats, residents, bills, cash and cheque collection, reports, guards and announcements.' },
    { id: 'owner', title: 'Owner', body: 'Maintenance bills and receipts for their flat. Visitors and residential tools when they live there.' },
    { id: 'tenant', title: 'Tenant', body: 'Visitors, vehicles and day-to-day residential access for the flat they occupy.' },
    { id: 'guard', title: 'Security guard', body: 'Visitor entry and exit, OTP at the gate, vehicle checks, and voice registration in Hinglish.' },
  ],
  howTitle: 'How it works',
  steps: [
    { n: '1', title: 'The society is set up', body: 'Admin adds wings, flats, residents and guards. Each person signs in with their own account.' },
    { n: '2', title: 'Work goes to the right person', body: 'Bills land on the owner’s flat. A visitor request goes to whoever lives there — owner or tenant.' },
    { n: '3', title: 'The gate and the books stay in sync', body: 'The guard handles entry and exit. Receipts and visitor records stay with the society.' },
  ],
  ctaTitle: 'Need this for your society?',
  ctaBody: 'Write to us for help with the app, or to ask about using Apna Society in your society.',
  ctaButton: { label: 'Contact support', to: '/support' },
  mock: {
    society: 'Your society',
    role: 'Owner · A-102',
    dueLabel: 'Due this month',
    dueValue: '₹4,200',
    visitLabel: 'At the gate',
    visitValue: '1 visitor waiting',
    tabs: ['Bills', 'Visitors', 'More'],
  },
} as const

export const privacy: PageDef = {
  path: '/privacy-policy', nav: 'Privacy Policy',
  title: 'Privacy Policy | Apna Society',
  description: 'How Apna Society, developed by SkyLine Tech Ventures, collects, uses, stores and deletes information.',
  intro: `This policy explains what ${APP} collects, why, who can see it, and how you can ask us to delete it.`,
  updated: LAST_UPDATED,
  sections: [
    { id: 'about', title: 'About the app', body: [
      `${APP} is a society management app developed by ${DEVELOPER}. Residential societies use it to manage residents, maintenance billing and payments, visitor entry and exit, and communication between the society committee, owners, tenants and security guards.`,
      `In this policy, "we" means ${DEVELOPER}.`] },
    { id: 'collect', title: 'Information we collect', body: [
      'We collect only what the app features need:',
      ['Name and contact details, including email address and mobile number',
       'Login and authentication data',
       'Society, wing and flat details',
       'Vehicle and parking information',
       'Visitor details and entry and exit records',
       'Maintenance bills, payments and receipts, including one-time collections and special charges',
       '[TO CONFIRM: technical or device information the app actually collects, such as app version or crash logs. Remove this line if none.]']] },
    { id: 'use', title: 'How we use information', body: [
      'We use your information to:',
      ['Create your account and sign you in',
       'Show you the society, flat, billing and visitor information that applies to your role',
       'Record and display maintenance bills, payments and receipts',
       'Record visitor entry and exit at the gate',
       'Respond to support requests']] },
    { id: 'roles', title: 'Who can see your information', body: [
      'What you can see depends on your role in the society. Each role sees only the screens built for it.',
      ['Admin: resident records and billing for their society',
       'Owner: maintenance bills and visitor records for their own flat',
       'Tenant: their own visitors and complaints',
       'Guard: visitor entry and exit records at the gate',
       '[TO CONFIRM: exact data visibility for each role against the permission rules in the app]'],
      'We do not sell personal information.'] },
    { id: 'security', title: 'Storage and security', body: [
      '[TO CONFIRM: where data is stored, whether it is encrypted in transit and at rest, and how access to it is controlled. Describe only what is implemented.]'] },
    { id: 'third-parties', title: 'Third-party services', body: [
      '[TO CONFIRM: list each third-party service the app or backend uses (for example hosting, SMS or OTP, push notifications, analytics, crash reporting, payments) and what data it receives. If none, say so.]'] },
    { id: 'retention', title: 'Retention and deletion', body: [
      'We keep your information while your account is active. You can ask us to delete your account at any time. See the Account Deletion page for how, and for what is deleted and what is kept.',
      'Financial records such as maintenance bills, payments and receipts may be kept after deletion because the society needs them for its accounts.'] },
    { id: 'rights', title: 'Your rights', body: [
      'You can ask us to:',
      ['Tell you what information we hold about you', 'Correct information that is wrong', 'Delete your account and associated information'],
      'Contact us using the details on the Support page.'] },
    { id: 'changes', title: 'Changes and contact', body: [
      `If we change this policy, we will update the date at the top of this page. Questions about this policy can be sent to ${DEVELOPER} through the Support page.`] },
  ] }

export const deletion: PageDef = {
  path: '/account-deletion', nav: 'Account Deletion',
  title: 'Delete your account | Apna Society',
  description: 'How to ask for your Apna Society account and data to be deleted, and what is kept for society records.',
  intro: 'You can ask us to delete your Apna Society account and the personal information linked to it.',
  updated: LAST_UPDATED,
  sections: [
    { id: 'request', title: 'How to request deletion', body: [
      `Email ${DEVELOPER} at ${SUPPORT_EMAIL} from the email address, or with the mobile number, registered on your account. Include:`,
      ['Your full name', 'Your society, wing and flat number', 'The mobile number or email address on the account', 'The words "Delete my account"'] ] },
    { id: 'steps', title: 'What happens next', body: [
      ['We confirm the request comes from the account holder.', 'We delete or anonymise the information described below.', 'We confirm by email or message once it is done.'],
      '[TO CONFIRM: how long deletion takes. State a timeline only if it will be met.]'] },
    { id: 'deleted', title: 'What we delete or anonymise', body: [
      ['Your profile: name, email address and mobile number', 'Your login and authentication data', 'Vehicle and parking details linked to you', '[TO CONFIRM: whether visitor records linked to you are deleted or anonymised]'] ] },
    { id: 'kept', title: 'What may be kept', body: [
      'Maintenance bills, payments, receipts, one-time collections and special charges may be kept, because your society needs them for its financial and accounting records. Where possible they are kept without your personal details.'] },
  ] }

export const support: PageDef = {
  path: '/support', nav: 'Support',
  title: 'Support | Apna Society',
  description: 'Get help with Apna Society: login, maintenance billing and payments, receipts, visitor management and technical issues.',
  intro: 'Get help with the Apna Society app.',
  sections: [
    { id: 'help', title: 'What we can help with', body: [
      ['Using the app', 'Login and account problems', 'Maintenance bills and payments', 'Receipts', 'Visitor management', 'Reporting a technical issue'] ] },
    { id: 'contact', title: 'Contact us', body: [
      `Email: ${SUPPORT_EMAIL}`, `Developer: ${DEVELOPER}, ${DEVELOPER_SITE}`,
      'When you write, include your name, society, wing and flat number, your role (Admin, Owner, Tenant or Guard), and what went wrong. Add a screenshot if you can. Never send your password.'] },
    { id: 'billing', title: 'Billing questions', body: [
      'Maintenance charges are set by your society committee. For a question about an amount, contact your society admin first. Contact us if a payment or receipt does not show correctly in the app.'] },
    { id: 'delete', title: 'Delete your account', body: ['See the Account Deletion page for how to request it.'] },
  ] }

export const pages = [privacy, deletion, support]
export const routes = ['/', ...pages.map(p => p.path)]
export const home = {
  title: 'Apna Society — Simplifying Society Management',
  description: 'Society management for admins, owners, tenants and guards. Maintenance bills, visitors, vehicles and the gate — in one app by SkyLine Tech Ventures.',
}
export const mainNav = [
  { to: '/#features', label: 'Features' },
  { to: '/#roles', label: 'Who it’s for' },
  { to: '/support', label: 'Support' },
] as const
