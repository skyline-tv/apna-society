import { useState } from "react";
import {
  Home, Users, CreditCard, Bell, Shield, ChevronRight, ChevronLeft,
  Search, Plus, CheckCircle, Clock, AlertCircle, Building2, Phone,
  Lock, Eye, EyeOff, FileText, Download, MoreVertical, Calendar,
  TrendingUp, LogOut, Settings, User, Edit, X, MessageSquare,
  ClipboardList, UserPlus, Receipt, AlertTriangle, Wrench, DoorOpen,
  BarChart3, Key, Zap, Info, RefreshCw, LayoutGrid, Archive,
  ChevronDown, Filter, IndianRupee, MapPin, CheckCheck, Send,
  ShieldCheck, Star, Wifi, BellRing,
} from "lucide-react";

// ─── TYPES ──────────────────────────────────────────────────────────────────
type Role = "admin" | "owner" | "tenant" | "guard";
type View = "demo" | "auth" | Role;

interface Nav {
  view: View;
  tab: string;
  screen: string;
  detail: Record<string, unknown> | null;
}

// ─── MOCK DATA ───────────────────────────────────────────────────────────────
const RESIDENTS = [
  { id:"R001", flat:"A-101", wing:"A", floor:1,  owner:"Rajesh Mehta",    ownerPhone:"98765 43210", tenant:null,           tenantPhone:null,        status:"occupied", balance:7000,  overdue:true,  months:"Sep–Oct 2025" },
  { id:"R002", flat:"A-204", wing:"A", floor:2,  owner:"Priya Sharma",    ownerPhone:"98234 56789", tenant:"Vikram Iyer",   tenantPhone:"98345 67890",status:"occupied", balance:0,     overdue:false, months:null },
  { id:"R003", flat:"B-302", wing:"B", floor:3,  owner:"Suresh Nair",     ownerPhone:"99345 67890", tenant:null,           tenantPhone:null,        status:"occupied", balance:10500, overdue:true,  months:"Aug–Oct 2025" },
  { id:"R004", flat:"C-405", wing:"C", floor:4,  owner:"Anita Desai",     ownerPhone:"98456 78901", tenant:null,           tenantPhone:null,        status:"vacant",   balance:0,     overdue:false, months:null },
  { id:"R005", flat:"D-501", wing:"D", floor:5,  owner:"Ramesh Gupta",    ownerPhone:"98567 89012", tenant:"Meena Pillai", tenantPhone:"98678 90123",status:"occupied", balance:3500,  overdue:false, months:"Oct 2025" },
  { id:"R006", flat:"E-701", wing:"E", floor:7,  owner:"Kavitha Rao",     ownerPhone:"98789 01234", tenant:null,           tenantPhone:null,        status:"occupied", balance:4000,  overdue:false, months:"Oct 2025" },
  { id:"R007", flat:"B-205", wing:"B", floor:2,  owner:"Dinesh Patel",    ownerPhone:"98890 12345", tenant:null,           tenantPhone:null,        status:"occupied", balance:0,     overdue:false, months:null },
  { id:"R008", flat:"C-301", wing:"C", floor:3,  owner:"Lakshmi Venkat",  ownerPhone:"98901 23456", tenant:"Arun Kumar",   tenantPhone:"99012 34567",status:"occupied", balance:3500,  overdue:false, months:"Oct 2025" },
];

const BILLS = [
  { id:"B001", flat:"A-204", resident:"Priya Sharma",   amount:3500,  months:"October 2025",   status:"paid",    paidOn:"03 Oct 2025", receipt:"RCP-1024", mode:"UPI",           interest:0   },
  { id:"B002", flat:"B-302", resident:"Suresh Nair",    amount:10500, months:"Aug–Oct 2025",   status:"overdue", dueDate:"01 Sep 2025", receipt:null,       mode:null,            interest:315 },
  { id:"B003", flat:"D-501", resident:"Ramesh Gupta",   amount:3500,  months:"October 2025",   status:"pending", dueDate:"31 Oct 2025", receipt:null,       mode:null,            interest:0   },
  { id:"B004", flat:"E-701", resident:"Kavitha Rao",    amount:4000,  months:"October 2025",   status:"pending", dueDate:"31 Oct 2025", receipt:null,       mode:null,            interest:0   },
  { id:"B005", flat:"A-101", resident:"Rajesh Mehta",   amount:7000,  months:"Sep–Oct 2025",   status:"overdue", dueDate:"01 Oct 2025", receipt:null,       mode:null,            interest:210 },
  { id:"B006", flat:"B-205", resident:"Dinesh Patel",   amount:3500,  months:"October 2025",   status:"paid",    paidOn:"01 Oct 2025", receipt:"RCP-1019", mode:"Bank Transfer",  interest:0   },
  { id:"B007", flat:"C-301", resident:"Lakshmi Venkat", amount:3500,  months:"October 2025",   status:"pending", dueDate:"31 Oct 2025", receipt:null,       mode:null,            interest:0   },
];

const COMPLAINTS = [
  { id:"C001", flat:"A-204", resident:"Priya Sharma",   category:"Plumbing",     title:"Water leakage in bathroom",       priority:"high",   status:"open",        date:"18 Oct 2025", assigned:null,            resolvedOn:null        },
  { id:"C002", flat:"B-302", resident:"Suresh Nair",    category:"Electrical",   title:"Power fluctuation in kitchen",    priority:"high",   status:"in-progress", date:"15 Oct 2025", assigned:"Electrician Team",resolvedOn:null       },
  { id:"C003", flat:"D-501", resident:"Ramesh Gupta",   category:"Common Area",  title:"Lift not working on Floor 5",     priority:"medium", status:"resolved",    date:"10 Oct 2025", assigned:"AMC Team",       resolvedOn:"12 Oct 2025"},
  { id:"C004", flat:"E-701", resident:"Kavitha Rao",    category:"Housekeeping", title:"Corridor needs cleaning",         priority:"low",    status:"open",        date:"20 Oct 2025", assigned:null,            resolvedOn:null        },
  { id:"C005", flat:"C-301", resident:"Lakshmi Venkat", category:"Security",     title:"Gate intercom not working",       priority:"medium", status:"open",        date:"19 Oct 2025", assigned:null,            resolvedOn:null        },
];

const VISITORS = [
  { id:"V001", name:"Ravi Shankar",    flat:"A-204", host:"Priya Sharma",  purpose:"Family Visit",  status:"active",  date:"22 Oct 2025", time:"14:30", entryTime:"14:35", exitTime:null,    otp:"847293" },
  { id:"V002", name:"Amazon Delivery", flat:"B-302", host:"Suresh Nair",   purpose:"Delivery",      status:"pending", date:"22 Oct 2025", time:"11:00", entryTime:null,    exitTime:null,    otp:"362841" },
  { id:"V003", name:"Plumber",         flat:"E-701", host:"Kavitha Rao",   purpose:"Maintenance",   status:"exited",  date:"22 Oct 2025", time:"10:00", entryTime:"10:05", exitTime:"11:20", otp:"591047" },
  { id:"V004", name:"Anand Mehta",     flat:"D-501", host:"Ramesh Gupta",  purpose:"Family Visit",  status:"pending", date:"22 Oct 2025", time:"16:00", entryTime:null,    exitTime:null,    otp:"724516" },
  { id:"V005", name:"Swiggy Delivery", flat:"A-101", host:"Rajesh Mehta",  purpose:"Food Delivery", status:"pending", date:"22 Oct 2025", time:"20:15", entryTime:null,    exitTime:null,    otp:"935028" },
];

const ANNOUNCEMENTS = [
  { id:"AN001", title:"Society AGM — 28 October 2025",  body:"All residents are invited to the Annual General Meeting at Community Hall, Wing A Ground Floor at 6:00 PM. Agenda: Budget approval, new committee election.", date:"20 Oct 2025", important:true,  read:false },
  { id:"AN002", title:"Water Supply Interruption",       body:"Water supply will be interrupted on 24th October from 9 AM to 1 PM due to overhead tank maintenance. Please store water in advance.",                          date:"19 Oct 2025", important:true,  read:true  },
  { id:"AN003", title:"Diwali Celebration",              body:"Society Diwali celebration on 1st November at 7 PM at the central courtyard. Fireworks, rangoli, and dinner. All residents welcome.",                         date:"17 Oct 2025", important:false, read:true  },
  { id:"AN004", title:"Parking Allotment Update",        body:"Revised parking allotments for Wing B and C residents have been posted on the notice board near the main gate.",                                              date:"15 Oct 2025", important:false, read:true  },
];

const STAFF = [
  { id:"S001", name:"Mahesh Kumar",    role:"Security Guard", shift:"Morning (6AM–2PM)",  phone:"99123 45678", attendance:"present" },
  { id:"S002", name:"Ramnaresh Yadav", role:"Security Guard", shift:"Evening (2PM–10PM)", phone:"99234 56789", attendance:"present" },
  { id:"S003", name:"Govind Singh",    role:"Security Guard", shift:"Night (10PM–6AM)",   phone:"99345 67890", attendance:"present" },
  { id:"S004", name:"Rajendra Mishra", role:"Housekeeping",   shift:"Morning (7AM–3PM)",  phone:"99456 78901", attendance:"absent"  },
  { id:"S005", name:"Shanti Devi",     role:"Housekeeping",   shift:"Morning (7AM–3PM)",  phone:"99567 89012", attendance:"present" },
  { id:"S006", name:"Raju Kamat",      role:"Plumber",        shift:"On Call",            phone:"99678 90123", attendance:"present" },
];

const FACILITIES = [
  { id:"F001", name:"Community Hall",      capacity:100, status:"available", charge:2000, desc:"AC hall with projector and sound system" },
  { id:"F002", name:"Terrace Garden",      capacity:50,  status:"booked",    charge:500,  desc:"Open terrace with seating and festive lighting" },
  { id:"F003", name:"Indoor Gym",          capacity:20,  status:"available", charge:0,    desc:"Fully equipped gym open 5 AM – 10 PM" },
  { id:"F004", name:"Multipurpose Court",  capacity:20,  status:"available", charge:200,  desc:"Badminton and basketball court" },
];

// ─── DESIGN SYSTEM ────────────────────────────────────────────────────────────
const STATUS_MAP: Record<string, { bg: string; text: string; label: string }> = {
  paid:          { bg:"bg-[#E7F4ED]", text:"text-[#2B6349]", label:"Paid"        },
  pending:       { bg:"bg-[#FEF3C7]", text:"text-[#B45309]", label:"Pending"     },
  overdue:       { bg:"bg-[#FEE2E2]", text:"text-[#C53030]", label:"Overdue"     },
  open:          { bg:"bg-[#FEE2E2]", text:"text-[#C53030]", label:"Open"        },
  "in-progress": { bg:"bg-[#EBF0FE]", text:"text-[#3B5ADB]", label:"In Progress" },
  resolved:      { bg:"bg-[#E7F4ED]", text:"text-[#2B6349]", label:"Resolved"    },
  approved:      { bg:"bg-[#E7F4ED]", text:"text-[#2B6349]", label:"Approved"    },
  active:        { bg:"bg-[#E7F4ED]", text:"text-[#2B6349]", label:"Inside"      },
  exited:        { bg:"bg-[#F0EBE4]", text:"text-[#78706A]", label:"Exited"      },
  occupied:      { bg:"bg-[#E7F4ED]", text:"text-[#2B6349]", label:"Occupied"    },
  vacant:        { bg:"bg-[#F0EBE4]", text:"text-[#78706A]", label:"Vacant"      },
  high:          { bg:"bg-[#FEE2E2]", text:"text-[#C53030]", label:"High"        },
  medium:        { bg:"bg-[#FEF3C7]", text:"text-[#B45309]", label:"Medium"      },
  low:           { bg:"bg-[#EBF0FE]", text:"text-[#3B5ADB]", label:"Low"         },
  present:       { bg:"bg-[#E7F4ED]", text:"text-[#2B6349]", label:"Present"     },
  absent:        { bg:"bg-[#FEE2E2]", text:"text-[#C53030]", label:"Absent"      },
  available:     { bg:"bg-[#E7F4ED]", text:"text-[#2B6349]", label:"Available"   },
  booked:        { bg:"bg-[#FEF3C7]", text:"text-[#B45309]", label:"Booked"      },
};

function Chip({ status }: { status: string }) {
  const s = STATUS_MAP[status] ?? { bg:"bg-gray-100", text:"text-gray-600", label: status };
  return (
    <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-semibold tracking-wide uppercase ${s.bg} ${s.text}`}>
      {s.label}
    </span>
  );
}

function PrimaryBtn({ children, onClick, disabled = false, sm = false }: { children: React.ReactNode; onClick?: () => void; disabled?: boolean; sm?: boolean }) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      className={`bg-[#2B6349] text-white font-semibold rounded-xl flex items-center justify-center gap-2 active:opacity-90 disabled:opacity-40 transition-opacity ${sm ? "px-4 h-9 text-[13px]" : "w-full h-12 text-[15px]"}`}
    >
      {children}
    </button>
  );
}

function SecondaryBtn({ children, onClick, sm = false }: { children: React.ReactNode; onClick?: () => void; sm?: boolean }) {
  return (
    <button
      onClick={onClick}
      className={`border border-[#2B6349] text-[#2B6349] font-semibold rounded-xl flex items-center justify-center gap-2 active:opacity-90 transition-opacity ${sm ? "px-4 h-9 text-[13px]" : "w-full h-12 text-[15px]"}`}
    >
      {children}
    </button>
  );
}

function GhostBtn({ children, onClick }: { children: React.ReactNode; onClick?: () => void }) {
  return (
    <button onClick={onClick} className="text-[#2B6349] font-semibold text-[14px] flex items-center gap-1 active:opacity-70">
      {children}
    </button>
  );
}

function Card({ children, className = "", onClick }: { children: React.ReactNode; className?: string; onClick?: () => void }) {
  return (
    <div
      className={`bg-white rounded-2xl border border-[#E8E1D8] ${onClick ? "cursor-pointer active:scale-[0.99]" : ""} transition-transform ${className}`}
      onClick={onClick}
    >
      {children}
    </div>
  );
}

function StatCard({ label, value, icon: Icon, color = "#2B6349", sub }: { label: string; value: string; icon: React.FC<{ size?: number; color?: string }>; color?: string; sub?: string }) {
  const paleBg: Record<string, string> = {
    "#2B6349":"#E7F4ED", "#D97706":"#FEF3C7", "#C53030":"#FEE2E2", "#3B5ADB":"#EBF0FE", "#78706A":"#F0EBE4",
  };
  return (
    <Card className="p-4">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-[10px] font-semibold text-[#9C9490] uppercase tracking-widest mb-1">{label}</p>
          <p className="text-[22px] font-bold text-[#1A1714] leading-tight">{value}</p>
          {sub && <p className="text-[11px] text-[#9C9490] mt-0.5">{sub}</p>}
        </div>
        <div className="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" style={{ backgroundColor: paleBg[color] ?? "#F0EBE4" }}>
          <Icon size={18} color={color} />
        </div>
      </div>
    </Card>
  );
}

function InputField({
  label, placeholder, type = "text", value, onChange, rightEl,
}: {
  label?: string; placeholder?: string; type?: string; value: string; onChange: (v: string) => void; rightEl?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col gap-1.5">
      {label && <label className="text-[13px] font-medium text-[#3D3830]">{label}</label>}
      <div className="relative">
        <input
          type={type}
          placeholder={placeholder}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          className="w-full h-12 bg-white border border-[#E2DBD3] rounded-xl text-[14px] text-[#1A1714] placeholder-[#B0A99F] pl-4 pr-11 focus:outline-none focus:border-[#2B6349] focus:ring-1 focus:ring-[#2B6349]/30 transition"
        />
        {rightEl && <div className="absolute right-3.5 top-1/2 -translate-y-1/2">{rightEl}</div>}
      </div>
    </div>
  );
}

function SearchBar({ placeholder, value, onChange }: { placeholder?: string; value: string; onChange: (v: string) => void }) {
  return (
    <div className="relative">
      <Search size={15} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-[#9C9490]" />
      <input
        type="text"
        placeholder={placeholder ?? "Search…"}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full h-10 bg-white border border-[#E2DBD3] rounded-xl text-[13px] text-[#1A1714] placeholder-[#B0A99F] pl-9 pr-4 focus:outline-none focus:border-[#2B6349] transition"
      />
    </div>
  );
}

function Divider() {
  return <div className="h-px bg-[#EDE8DF] mx-4" />;
}

function SectionHeader({ title, action, onAction }: { title: string; action?: string; onAction?: () => void }) {
  return (
    <div className="flex items-center justify-between px-4 mb-3">
      <p className="text-[13px] font-semibold text-[#78706A] uppercase tracking-widest">{title}</p>
      {action && <GhostBtn onClick={onAction}>{action} <ChevronRight size={13} /></GhostBtn>}
    </div>
  );
}

function ListRow({ icon: Icon, iconBg, label, sub, right, onClick }: {
  icon: React.FC<{ size?: number; color?: string }>; iconBg: string; label: string; sub?: string; right?: React.ReactNode; onClick?: () => void;
}) {
  return (
    <button
      onClick={onClick}
      className="flex items-center gap-3 px-4 py-3.5 w-full text-left active:bg-[#F4EFE7] transition-colors"
    >
      <div className="w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0" style={{ backgroundColor: iconBg }}>
        <Icon size={17} color="#2B6349" />
      </div>
      <div className="flex-1 min-w-0">
        <p className="text-[14px] font-medium text-[#1A1714] truncate">{label}</p>
        {sub && <p className="text-[12px] text-[#9C9490] truncate">{sub}</p>}
      </div>
      {right ?? <ChevronRight size={16} className="text-[#C8C0B8] flex-shrink-0" />}
    </button>
  );
}

// ─── SHARED APP CHROME ────────────────────────────────────────────────────────
function StatusBar() {
  return (
    <div className="flex items-center justify-between px-5 pt-3 pb-1.5 flex-shrink-0">
      <span className="text-[12px] font-semibold text-[#1A1714]">9:41</span>
      <div className="flex items-center gap-1.5">
        <Wifi size={13} className="text-[#1A1714]" />
        <div className="flex gap-0.5 items-end h-3.5">
          {[40,60,80,100].map((h, i) => (
            <div key={i} className="w-[3px] rounded-sm bg-[#1A1714]" style={{ height: `${h}%` }} />
          ))}
        </div>
        <div className="flex items-center gap-0.5">
          <div className="w-5 h-2.5 rounded-sm border border-[#1A1714] relative">
            <div className="absolute inset-[2px] left-[2px] right-[2px] bg-[#1A1714] rounded-[1px]" style={{ right: "30%" }} />
          </div>
        </div>
      </div>
    </div>
  );
}

function ScreenHeader({ title, onBack, action }: { title: string; onBack?: () => void; action?: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between px-4 py-3 border-b border-[#EDE8DF] bg-white flex-shrink-0">
      {onBack
        ? <button onClick={onBack} className="w-8 h-8 flex items-center justify-center -ml-1 rounded-lg active:bg-[#F4EFE7]"><ChevronLeft size={20} className="text-[#1A1714]" /></button>
        : <div className="w-8" />
      }
      <p className="text-[15px] font-semibold text-[#1A1714]">{title}</p>
      {action ?? <div className="w-8" />}
    </div>
  );
}

function BottomNav({ items, active, onChange }: {
  items: { id: string; label: string; icon: React.FC<{ size?: number; strokeWidth?: number }> }[];
  active: string;
  onChange: (id: string) => void;
}) {
  return (
    <div className="flex items-center border-t border-[#EDE8DF] bg-white flex-shrink-0" style={{ paddingBottom: "env(safe-area-inset-bottom, 8px)" }}>
      {items.map((item) => {
        const isActive = item.id === active;
        return (
          <button
            key={item.id}
            onClick={() => onChange(item.id)}
            className="flex-1 flex flex-col items-center justify-center py-2.5 gap-1"
          >
            <item.icon size={22} strokeWidth={isActive ? 2.5 : 1.8} color={isActive ? "#2B6349" : "#B0A99F"} />
            <span className={`text-[10px] font-semibold ${isActive ? "text-[#2B6349]" : "text-[#B0A99F]"}`}>{item.label}</span>
          </button>
        );
      })}
    </div>
  );
}

// ─── AUTH SCREENS ─────────────────────────────────────────────────────────────
function SplashScreen({ onDone }: { onDone: () => void }) {
  return (
    <div className="flex flex-col items-center justify-center h-full bg-[#2B6349]">
      <div className="flex flex-col items-center gap-4 mb-8">
        <div className="w-20 h-20 rounded-3xl bg-white/15 flex items-center justify-center">
          <Building2 size={40} color="white" />
        </div>
        <div className="text-center">
          <p className="text-[26px] font-bold text-white tracking-tight">Apna Society</p>
          <p className="text-[13px] text-white/60 mt-0.5 font-medium">Monarch Solitaire</p>
        </div>
      </div>
      <div className="flex gap-1.5">
        {[0, 1, 2].map((i) => (
          <div key={i} className={`rounded-full bg-white transition-all ${i === 0 ? "w-5 h-1.5" : "w-1.5 h-1.5 opacity-40"}`} />
        ))}
      </div>
      <button
        onClick={onDone}
        className="absolute bottom-12 text-white/50 text-[13px] font-medium"
      >
        Tap to continue →
      </button>
    </div>
  );
}

function WelcomeScreen({ onLogin }: { onLogin: () => void }) {
  return (
    <div className="flex flex-col h-full bg-[#F4EFE7]">
      <div className="flex-1 flex flex-col items-center justify-center px-8 gap-6">
        <div className="w-24 h-24 rounded-3xl bg-[#2B6349] flex items-center justify-center shadow-lg">
          <Building2 size={46} color="white" />
        </div>
        <div className="text-center">
          <p className="text-[28px] font-bold text-[#1A1714] tracking-tight leading-tight">Apna Society</p>
          <p className="text-[15px] text-[#78706A] mt-2 leading-relaxed">Your complete society management platform for Monarch Solitaire A–E</p>
        </div>
        <div className="flex flex-col gap-3 w-full mt-4">
          <div className="flex items-center gap-3 bg-white rounded-2xl p-3.5 border border-[#E8E1D8]">
            <div className="w-8 h-8 rounded-xl bg-[#E7F4ED] flex items-center justify-center"><ShieldCheck size={16} color="#2B6349" /></div>
            <div><p className="text-[13px] font-semibold text-[#1A1714]">Secure & Trusted</p><p className="text-[11px] text-[#9C9490]">Bank-grade data security</p></div>
          </div>
          <div className="flex items-center gap-3 bg-white rounded-2xl p-3.5 border border-[#E8E1D8]">
            <div className="w-8 h-8 rounded-xl bg-[#E7F4ED] flex items-center justify-center"><Zap size={16} color="#2B6349" /></div>
            <div><p className="text-[13px] font-semibold text-[#1A1714]">Everything in One Place</p><p className="text-[11px] text-[#9C9490]">Billing, visitors, complaints &amp; more</p></div>
          </div>
        </div>
      </div>
      <div className="px-6 pb-10 flex flex-col gap-3">
        <PrimaryBtn onClick={onLogin}>Sign In to Your Account</PrimaryBtn>
        <p className="text-center text-[12px] text-[#9C9490]">v2.4.1 · Monarch Solitaire, Pune</p>
      </div>
    </div>
  );
}

function LoginScreen({ onLogin }: { onLogin: () => void }) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [showPw, setShowPw] = useState(false);
  const [remember, setRemember] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  const handleLogin = () => {
    if (!username || !password) { setError("Please enter your username and password."); return; }
    setError("");
    setLoading(true);
    setTimeout(() => { setLoading(false); onLogin(); }, 1200);
  };

  return (
    <div className="flex flex-col h-full bg-[#F4EFE7]">
      <div className="px-6 pt-10 pb-6 flex flex-col gap-1">
        <div className="w-12 h-12 rounded-2xl bg-[#2B6349] flex items-center justify-center mb-3">
          <Building2 size={24} color="white" />
        </div>
        <p className="text-[24px] font-bold text-[#1A1714]">Welcome back</p>
        <p className="text-[14px] text-[#78706A]">Sign in to Apna Society</p>
      </div>
      <div className="flex-1 px-6 flex flex-col gap-4">
        {error && (
          <div className="flex items-center gap-2 bg-[#FEE2E2] border border-[#FECACA] rounded-xl px-3.5 py-3">
            <AlertCircle size={15} color="#C53030" />
            <p className="text-[13px] text-[#C53030] font-medium">{error}</p>
          </div>
        )}
        <InputField label="Username / Employee ID" placeholder="Enter username" value={username} onChange={setUsername} />
        <InputField
          label="Password"
          placeholder="Enter password"
          type={showPw ? "text" : "password"}
          value={password}
          onChange={setPassword}
          rightEl={
            <button onClick={() => setShowPw(!showPw)} className="p-1">
              {showPw ? <EyeOff size={17} className="text-[#9C9490]" /> : <Eye size={17} className="text-[#9C9490]" />}
            </button>
          }
        />
        <div className="flex items-center justify-between">
          <button onClick={() => setRemember(!remember)} className="flex items-center gap-2">
            <div className={`w-4.5 h-4.5 w-[18px] h-[18px] rounded-[4px] border-2 flex items-center justify-center transition ${remember ? "bg-[#2B6349] border-[#2B6349]" : "border-[#C8C0B8]"}`}>
              {remember && <CheckCheck size={10} color="white" strokeWidth={3} />}
            </div>
            <span className="text-[13px] text-[#3D3830] font-medium">Remember me</span>
          </button>
          <button className="text-[13px] text-[#2B6349] font-semibold">Forgot password?</button>
        </div>
        <div className="pt-2">
          <PrimaryBtn onClick={handleLogin} disabled={loading}>
            {loading ? <RefreshCw size={17} className="animate-spin" /> : "Sign In"}
          </PrimaryBtn>
        </div>
        <p className="text-center text-[12px] text-[#9C9490] mt-2">Having trouble? Contact your society admin</p>
      </div>
    </div>
  );
}

// ─── ADMIN SCREENS ────────────────────────────────────────────────────────────
const ADMIN_TABS = [
  { id:"dashboard", label:"Dashboard", icon: LayoutGrid },
  { id:"residents",  label:"Residents", icon: Users       },
  { id:"billing",    label:"Billing",   icon: CreditCard  },
  { id:"more",       label:"More",      icon: MoreVertical },
];

function AdminDashboard({ nav }: { nav: (u: Partial<Nav>) => void }) {
  const collected = BILLS.filter(b => b.status === "paid").reduce((s, b) => s + b.amount, 0);
  const pending = BILLS.filter(b => b.status === "pending").reduce((s, b) => s + b.amount, 0);
  const overdue = BILLS.filter(b => b.status === "overdue").reduce((s, b) => s + b.amount, 0);
  const totalDue = collected + pending + overdue;
  const pct = Math.round((collected / totalDue) * 100);
  const openComplaints = COMPLAINTS.filter(c => c.status !== "resolved").length;
  const pendingVisitors = VISITORS.filter(v => v.status === "pending").length;

  const QUICK = [
    { label:"Add Resident",   icon: UserPlus,      color:"#2B6349", pale:"#E7F4ED" },
    { label:"Create Bill",    icon: Receipt,       color:"#D97706", pale:"#FEF3C7" },
    { label:"Announcement",   icon: BellRing,      color:"#3B5ADB", pale:"#EBF0FE" },
    { label:"Reports",        icon: BarChart3,     color:"#7C3AED", pale:"#EDE9FE" },
  ];

  return (
    <div className="flex-1 overflow-y-auto">
      {/* Header */}
      <div className="px-4 pt-4 pb-5 bg-white border-b border-[#EDE8DF]">
        <div className="flex items-start justify-between">
          <div>
            <p className="text-[12px] text-[#9C9490] font-medium mb-0.5">Good morning, Admin</p>
            <p className="text-[20px] font-bold text-[#1A1714]">Monarch Solitaire</p>
          </div>
          <button className="relative w-9 h-9 rounded-xl bg-[#F4EFE7] flex items-center justify-center">
            <Bell size={18} className="text-[#3D3830]" />
            <span className="absolute top-1.5 right-1.5 w-2 h-2 bg-[#C53030] rounded-full" />
          </button>
        </div>
        <p className="text-[13px] text-[#78706A] mt-1">22 October 2025 · Wings A–E</p>
      </div>

      <div className="px-4 py-5 flex flex-col gap-5">
        {/* Stats grid */}
        <div className="grid grid-cols-2 gap-3">
          <StatCard label="Total Flats" value="120" icon={Building2} color="#2B6349" sub="Wings A–E" />
          <StatCard label="Occupied" value="108" icon={Users} color="#2B6349" sub="12 vacant" />
          <StatCard label="This Month" value={`₹${(collected/1000).toFixed(0)}K`} icon={IndianRupee} color="#2B6349" sub="Collected" />
          <StatCard label="Overdue" value={`₹${(overdue/1000).toFixed(0)}K`} icon={AlertTriangle} color="#C53030" sub="4 flats" />
        </div>

        {/* Collection progress */}
        <Card className="p-4">
          <div className="flex items-center justify-between mb-3">
            <p className="text-[13px] font-semibold text-[#1A1714]">October Collection</p>
            <p className="text-[13px] font-bold text-[#2B6349]">{pct}%</p>
          </div>
          <div className="h-2 bg-[#EDE8DF] rounded-full overflow-hidden mb-3">
            <div className="h-full bg-[#2B6349] rounded-full transition-all" style={{ width: `${pct}%` }} />
          </div>
          <div className="flex justify-between text-[11px]">
            <span className="text-[#78706A]">Collected <span className="font-semibold text-[#2B6349]">₹{collected.toLocaleString("en-IN")}</span></span>
            <span className="text-[#78706A]">Pending <span className="font-semibold text-[#B45309]">₹{pending.toLocaleString("en-IN")}</span></span>
            <span className="text-[#78706A]">Overdue <span className="font-semibold text-[#C53030]">₹{overdue.toLocaleString("en-IN")}</span></span>
          </div>
        </Card>

        {/* Quick actions */}
        <div>
          <SectionHeader title="Quick Actions" />
          <div className="grid grid-cols-4 gap-2">
            {QUICK.map((q) => (
              <button key={q.label} className="flex flex-col items-center gap-1.5 p-2.5 bg-white rounded-2xl border border-[#E8E1D8] active:scale-95 transition-transform">
                <div className="w-10 h-10 rounded-xl flex items-center justify-center" style={{ backgroundColor: q.pale }}>
                  <q.icon size={18} color={q.color} />
                </div>
                <span className="text-[10px] font-semibold text-[#3D3830] text-center leading-tight">{q.label}</span>
              </button>
            ))}
          </div>
        </div>

        {/* Alerts */}
        <div>
          <SectionHeader title="Alerts" />
          <div className="flex flex-col gap-2">
            <Card className="px-4 py-3 flex items-center gap-3" onClick={() => nav({ tab:"billing" })}>
              <div className="w-8 h-8 rounded-xl bg-[#FEE2E2] flex items-center justify-center"><AlertTriangle size={15} color="#C53030" /></div>
              <div className="flex-1">
                <p className="text-[13px] font-semibold text-[#1A1714]">4 flats overdue</p>
                <p className="text-[11px] text-[#9C9490]">₹{overdue.toLocaleString("en-IN")} total overdue</p>
              </div>
              <ChevronRight size={15} className="text-[#C8C0B8]" />
            </Card>
            <Card className="px-4 py-3 flex items-center gap-3" onClick={() => nav({ tab:"more", screen:"complaints" })}>
              <div className="w-8 h-8 rounded-xl bg-[#FEF3C7] flex items-center justify-center"><MessageSquare size={15} color="#B45309" /></div>
              <div className="flex-1">
                <p className="text-[13px] font-semibold text-[#1A1714]">{openComplaints} open complaints</p>
                <p className="text-[11px] text-[#9C9490]">2 high priority unassigned</p>
              </div>
              <ChevronRight size={15} className="text-[#C8C0B8]" />
            </Card>
            <Card className="px-4 py-3 flex items-center gap-3" onClick={() => nav({ tab:"more", screen:"visitors" })}>
              <div className="w-8 h-8 rounded-xl bg-[#EBF0FE] flex items-center justify-center"><DoorOpen size={15} color="#3B5ADB" /></div>
              <div className="flex-1">
                <p className="text-[13px] font-semibold text-[#1A1714]">{pendingVisitors} visitor approvals pending</p>
                <p className="text-[11px] text-[#9C9490]">Today · 22 Oct 2025</p>
              </div>
              <ChevronRight size={15} className="text-[#C8C0B8]" />
            </Card>
          </div>
        </div>

        {/* Recent activity */}
        <div>
          <SectionHeader title="Recent Activity" />
          <Card>
            {[
              { time:"14:35", text:"Ravi Shankar entered Wing A-204", icon: DoorOpen, color:"#2B6349" },
              { time:"12:10", text:"Bill paid — B-205 Dinesh Patel ₹3,500", icon: CheckCircle, color:"#2B6349" },
              { time:"10:05", text:"Plumber entered E-701 for maintenance", icon: Wrench, color:"#B45309" },
              { time:"09:30", text:"New complaint: A-204 Water leakage", icon: AlertCircle, color:"#C53030" },
            ].map((item, i, arr) => (
              <div key={i}>
                <div className="flex items-center gap-3 px-4 py-3">
                  <div className="w-7 h-7 rounded-lg flex items-center justify-center bg-[#F4EFE7]">
                    <item.icon size={13} color={item.color} />
                  </div>
                  <p className="flex-1 text-[12px] text-[#3D3830] leading-snug">{item.text}</p>
                  <span className="text-[11px] text-[#9C9490] flex-shrink-0">{item.time}</span>
                </div>
                {i < arr.length - 1 && <Divider />}
              </div>
            ))}
          </Card>
        </div>

        {/* Staff on duty */}
        <div>
          <SectionHeader title="Staff on Duty" action="See All" onAction={() => nav({ tab:"more", screen:"staff" })} />
          <div className="flex gap-2 overflow-x-auto pb-1">
            {STAFF.filter(s => s.attendance === "present").slice(0, 4).map((s) => (
              <div key={s.id} className="flex-shrink-0 bg-white rounded-2xl border border-[#E8E1D8] p-3 w-[120px]">
                <div className="w-9 h-9 rounded-xl bg-[#E7F4ED] flex items-center justify-center mb-2">
                  <User size={17} color="#2B6349" />
                </div>
                <p className="text-[12px] font-semibold text-[#1A1714] truncate">{s.name.split(" ")[0]}</p>
                <p className="text-[10px] text-[#9C9490] truncate">{s.role}</p>
                <div className="mt-1.5"><Chip status="present" /></div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}

function AdminResidents({ nav }: { nav: (u: Partial<Nav>) => void }) {
  const [search, setSearch] = useState("");
  const [wing, setWing] = useState("All");
  const filtered = RESIDENTS.filter(r =>
    (wing === "All" || r.wing === wing) &&
    (r.owner.toLowerCase().includes(search.toLowerCase()) || r.flat.toLowerCase().includes(search.toLowerCase()))
  );
  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <div className="px-4 py-3 bg-white border-b border-[#EDE8DF] flex flex-col gap-2.5">
        <div className="flex items-center justify-between">
          <p className="text-[18px] font-bold text-[#1A1714]">Residents</p>
          <button className="w-8 h-8 rounded-xl bg-[#E7F4ED] flex items-center justify-center"><Plus size={17} color="#2B6349" /></button>
        </div>
        <SearchBar placeholder="Search flat or resident…" value={search} onChange={setSearch} />
        <div className="flex gap-2 overflow-x-auto pb-0.5">
          {["All", ...["A","B","C","D","E"].map(w => `Wing ${w}`)].map((w) => {
            const id = w === "All" ? "All" : w.replace("Wing ", "");
            const active = wing === id;
            return (
              <button
                key={w}
                onClick={() => setWing(id)}
                className={`flex-shrink-0 px-3 h-7 rounded-full text-[12px] font-semibold transition ${active ? "bg-[#2B6349] text-white" : "bg-white border border-[#E2DBD3] text-[#78706A]"}`}
              >
                {w}
              </button>
            );
          })}
        </div>
      </div>
      <div className="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-2">
        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <div className="w-14 h-14 rounded-2xl bg-[#EDE8DF] flex items-center justify-center"><Users size={24} className="text-[#9C9490]" /></div>
            <p className="text-[14px] font-medium text-[#9C9490]">No residents found</p>
          </div>
        ) : filtered.map((r) => (
          <Card key={r.id} className="p-4" onClick={() => nav({ screen:"resident-detail", detail: r as unknown as Record<string, unknown> })}>
            <div className="flex items-start gap-3">
              <div className="w-10 h-10 rounded-xl bg-[#E7F4ED] flex items-center justify-center flex-shrink-0">
                <User size={18} color="#2B6349" />
              </div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between gap-2 mb-0.5">
                  <p className="text-[14px] font-semibold text-[#1A1714] truncate">{r.owner}</p>
                  <Chip status={r.status} />
                </div>
                <p className="text-[12px] text-[#9C9490] mb-2">Flat {r.flat} · Floor {r.floor} · Wing {r.wing}</p>
                {r.tenant && <p className="text-[11px] text-[#78706A]">Tenant: {r.tenant}</p>}
                {r.balance > 0 && (
                  <div className="flex items-center gap-1.5 mt-2 bg-[#FEF3C7] rounded-lg px-2.5 py-1.5 w-fit">
                    <AlertTriangle size={11} color="#B45309" />
                    <p className="text-[11px] font-semibold text-[#B45309]">Due ₹{r.balance.toLocaleString("en-IN")} · {r.months}</p>
                  </div>
                )}
              </div>
              <ChevronRight size={15} className="text-[#C8C0B8] flex-shrink-0 mt-1" />
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}

function ResidentDetail({ resident, onBack }: { resident: Record<string, unknown>; onBack: () => void }) {
  const r = resident as typeof RESIDENTS[0];
  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <ScreenHeader title={`Flat ${r.flat}`} onBack={onBack} action={<button className="w-8 h-8 flex items-center justify-center rounded-lg active:bg-[#F4EFE7]"><Edit size={16} className="text-[#2B6349]" /></button>} />
      <div className="flex-1 overflow-y-auto px-4 py-4 flex flex-col gap-4">
        {/* Owner card */}
        <Card className="p-4">
          <p className="text-[11px] font-semibold text-[#9C9490] uppercase tracking-widest mb-3">Owner</p>
          <div className="flex items-center gap-3 mb-3">
            <div className="w-12 h-12 rounded-2xl bg-[#E7F4ED] flex items-center justify-center"><User size={22} color="#2B6349" /></div>
            <div>
              <p className="text-[15px] font-bold text-[#1A1714]">{r.owner}</p>
              <p className="text-[12px] text-[#9C9490]">Flat {r.flat} · Wing {r.wing}</p>
            </div>
          </div>
          <div className="flex gap-2">
            <div className="flex items-center gap-2 flex-1 bg-[#F4EFE7] rounded-xl px-3 py-2.5">
              <Phone size={13} color="#2B6349" /><p className="text-[12px] font-medium text-[#3D3830]">{r.ownerPhone}</p>
            </div>
            <Chip status={r.status} />
          </div>
        </Card>

        {/* Tenant card */}
        {r.tenant ? (
          <Card className="p-4">
            <p className="text-[11px] font-semibold text-[#9C9490] uppercase tracking-widest mb-3">Tenant</p>
            <div className="flex items-center gap-3 mb-3">
              <div className="w-12 h-12 rounded-2xl bg-[#EBF0FE] flex items-center justify-center"><User size={22} color="#3B5ADB" /></div>
              <div>
                <p className="text-[15px] font-bold text-[#1A1714]">{r.tenant}</p>
                <p className="text-[12px] text-[#9C9490]">Tenant · Flat {r.flat}</p>
              </div>
            </div>
            <div className="flex items-center gap-2 bg-[#F4EFE7] rounded-xl px-3 py-2.5">
              <Phone size={13} color="#2B6349" /><p className="text-[12px] font-medium text-[#3D3830]">{r.tenantPhone}</p>
            </div>
          </Card>
        ) : (
          <Card className="p-4 flex items-center gap-3 border-dashed">
            <div className="w-10 h-10 rounded-xl bg-[#EDE8DF] flex items-center justify-center"><UserPlus size={17} className="text-[#9C9490]" /></div>
            <div className="flex-1">
              <p className="text-[13px] font-semibold text-[#3D3830]">No tenant assigned</p>
              <p className="text-[11px] text-[#9C9490]">This flat is owner-occupied</p>
            </div>
            <GhostBtn>Assign</GhostBtn>
          </Card>
        )}

        {/* Billing summary */}
        <Card className="p-4">
          <p className="text-[11px] font-semibold text-[#9C9490] uppercase tracking-widest mb-3">Billing</p>
          <div className="flex justify-between items-center mb-1">
            <p className="text-[13px] text-[#78706A]">Monthly Maintenance</p>
            <p className="text-[13px] font-semibold text-[#1A1714]">₹3,500 / month</p>
          </div>
          {r.balance > 0 ? (
            <div className="mt-3 bg-[#FEE2E2] rounded-xl p-3 flex items-center justify-between">
              <div><p className="text-[12px] font-semibold text-[#C53030]">Outstanding Balance</p><p className="text-[11px] text-[#C53030]/70">{r.months}</p></div>
              <p className="text-[18px] font-bold text-[#C53030]">₹{r.balance.toLocaleString("en-IN")}</p>
            </div>
          ) : (
            <div className="mt-3 bg-[#E7F4ED] rounded-xl p-3 flex items-center gap-2">
              <CheckCircle size={15} color="#2B6349" /><p className="text-[13px] font-semibold text-[#2B6349]">All payments up to date</p>
            </div>
          )}
        </Card>

        {/* Actions */}
        <div className="flex flex-col gap-2.5">
          <PrimaryBtn><Receipt size={16} /> Generate Bill</PrimaryBtn>
          <SecondaryBtn><Key size={16} /> Reset Password</SecondaryBtn>
        </div>
      </div>
    </div>
  );
}

function AdminBilling() {
  const [filter, setFilter] = useState("all");
  const [selectedBill, setSelectedBill] = useState<typeof BILLS[0] | null>(null);

  const collected = BILLS.filter(b => b.status === "paid").reduce((s, b) => s + b.amount, 0);
  const pending = BILLS.filter(b => b.status === "pending").reduce((s, b) => s + b.amount, 0);
  const overdue = BILLS.filter(b => b.status === "overdue").reduce((s, b) => s + b.amount + b.interest, 0);

  const shown = filter === "all" ? BILLS : BILLS.filter(b => b.status === filter);

  if (selectedBill) {
    return (
      <div className="flex-1 flex flex-col overflow-hidden">
        <ScreenHeader title="Bill Details" onBack={() => setSelectedBill(null)} />
        <div className="flex-1 overflow-y-auto px-4 py-4 flex flex-col gap-4">
          <Card className="p-5">
            <div className="flex items-start justify-between mb-4">
              <div>
                <p className="text-[22px] font-bold text-[#1A1714]">₹{(selectedBill.amount + selectedBill.interest).toLocaleString("en-IN")}</p>
                <p className="text-[12px] text-[#9C9490] mt-0.5">{selectedBill.months}</p>
              </div>
              <Chip status={selectedBill.status} />
            </div>
            <div className="h-px bg-[#EDE8DF] mb-4" />
            {[
              ["Flat", selectedBill.flat],
              ["Resident", selectedBill.resident],
              ["Base Amount", `₹${selectedBill.amount.toLocaleString("en-IN")}`],
              ...(selectedBill.interest > 0 ? [["Interest (3%)", `₹${selectedBill.interest}`]] : []),
              ...(selectedBill.paidOn ? [["Paid On", selectedBill.paidOn], ["Mode", selectedBill.mode ?? "—"], ["Receipt", `#${selectedBill.receipt}`]] : []),
              ...(selectedBill.dueDate ? [["Due Date", selectedBill.dueDate]] : []),
            ].map(([k, v]) => (
              <div key={k} className="flex justify-between py-2">
                <p className="text-[13px] text-[#9C9490]">{k}</p>
                <p className="text-[13px] font-semibold text-[#1A1714]">{v}</p>
              </div>
            ))}
          </Card>
          {selectedBill.status === "paid" && (
            <PrimaryBtn><Download size={16} /> Download Receipt</PrimaryBtn>
          )}
          {selectedBill.status !== "paid" && (
            <div className="flex flex-col gap-2">
              <PrimaryBtn>Mark as Paid</PrimaryBtn>
              <SecondaryBtn>Send Reminder</SecondaryBtn>
            </div>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <div className="px-4 py-3 bg-white border-b border-[#EDE8DF]">
        <div className="flex items-center justify-between mb-3">
          <p className="text-[18px] font-bold text-[#1A1714]">Billing</p>
          <div className="flex gap-2">
            <button className="flex items-center gap-1.5 px-3 h-8 rounded-xl bg-[#E7F4ED] text-[#2B6349] text-[12px] font-semibold"><Plus size={13} />Create</button>
          </div>
        </div>
        {/* Month summary */}
        <div className="flex gap-2">
          <div className="flex-1 bg-[#E7F4ED] rounded-xl p-3 text-center">
            <p className="text-[10px] font-semibold text-[#2B6349] uppercase tracking-wide">Collected</p>
            <p className="text-[16px] font-bold text-[#2B6349]">₹{(collected/1000).toFixed(0)}K</p>
          </div>
          <div className="flex-1 bg-[#FEF3C7] rounded-xl p-3 text-center">
            <p className="text-[10px] font-semibold text-[#B45309] uppercase tracking-wide">Pending</p>
            <p className="text-[16px] font-bold text-[#B45309]">₹{(pending/1000).toFixed(0)}K</p>
          </div>
          <div className="flex-1 bg-[#FEE2E2] rounded-xl p-3 text-center">
            <p className="text-[10px] font-semibold text-[#C53030] uppercase tracking-wide">Overdue</p>
            <p className="text-[16px] font-bold text-[#C53030]">₹{(overdue/1000).toFixed(0)}K</p>
          </div>
        </div>
      </div>
      {/* Filter tabs */}
      <div className="flex bg-white border-b border-[#EDE8DF]">
        {["all","paid","pending","overdue"].map(f => (
          <button key={f} onClick={() => setFilter(f)} className={`flex-1 py-2.5 text-[12px] font-semibold capitalize border-b-2 transition ${filter === f ? "border-[#2B6349] text-[#2B6349]" : "border-transparent text-[#9C9490]"}`}>{f === "all" ? "All" : f}</button>
        ))}
      </div>
      <div className="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-2">
        {shown.map((b) => (
          <Card key={b.id} className="p-4" onClick={() => setSelectedBill(b)}>
            <div className="flex items-start justify-between gap-2 mb-2">
              <div className="flex-1 min-w-0">
                <p className="text-[14px] font-semibold text-[#1A1714] truncate">{b.resident}</p>
                <p className="text-[12px] text-[#9C9490]">Flat {b.flat} · {b.months}</p>
              </div>
              <Chip status={b.status} />
            </div>
            <div className="flex items-center justify-between">
              <p className="text-[18px] font-bold text-[#1A1714]">₹{b.amount.toLocaleString("en-IN")}</p>
              {b.interest > 0 && <p className="text-[11px] text-[#C53030] font-medium">+₹{b.interest} interest</p>}
              {b.paidOn && <p className="text-[11px] text-[#9C9490]">Paid {b.paidOn}</p>}
              {b.dueDate && b.status !== "paid" && <p className="text-[11px] text-[#B45309]">Due {b.dueDate}</p>}
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}

function AdminComplaints() {
  const [filter, setFilter] = useState("all");
  const shown = filter === "all" ? COMPLAINTS : COMPLAINTS.filter(c => c.status === filter || c.priority === filter);
  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <ScreenHeader title="Complaints" />
      <div className="flex bg-white border-b border-[#EDE8DF]">
        {["all","open","in-progress","resolved"].map(f => (
          <button key={f} onClick={() => setFilter(f)} className={`flex-1 py-2.5 text-[11px] font-semibold border-b-2 transition ${filter === f ? "border-[#2B6349] text-[#2B6349]" : "border-transparent text-[#9C9490]"}`}>
            {f === "all" ? "All" : f === "in-progress" ? "Active" : f.charAt(0).toUpperCase() + f.slice(1)}
          </button>
        ))}
      </div>
      <div className="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-2">
        {shown.map((c) => (
          <Card key={c.id} className="p-4">
            <div className="flex items-start gap-2 mb-2">
              <div className="flex-1 min-w-0">
                <p className="text-[13px] font-semibold text-[#1A1714] leading-snug">{c.title}</p>
                <p className="text-[11px] text-[#9C9490] mt-0.5">Flat {c.flat} · {c.resident}</p>
              </div>
              <Chip status={c.status} />
            </div>
            <div className="flex items-center justify-between">
              <div className="flex gap-1.5">
                <Chip status={c.priority} />
                <span className="inline-flex items-center px-2 py-0.5 rounded-full text-[10px] font-medium bg-[#F4EFE7] text-[#78706A]">{c.category}</span>
              </div>
              <p className="text-[11px] text-[#9C9490]">{c.date}</p>
            </div>
            {c.assigned && <p className="text-[11px] text-[#2B6349] mt-2 font-medium">→ {c.assigned}</p>}
          </Card>
        ))}
      </div>
    </div>
  );
}

function AdminVisitors() {
  const pending = VISITORS.filter(v => v.status === "pending");
  const active = VISITORS.filter(v => v.status === "active");
  const exited = VISITORS.filter(v => v.status === "exited");

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <ScreenHeader title="Visitors" />
      <div className="flex-1 overflow-y-auto px-4 py-4 flex flex-col gap-4">
        <div className="grid grid-cols-3 gap-2">
          <div className="bg-[#FEF3C7] rounded-2xl p-3 text-center">
            <p className="text-[20px] font-bold text-[#B45309]">{pending.length}</p>
            <p className="text-[10px] font-semibold text-[#B45309] uppercase tracking-wide">Pending</p>
          </div>
          <div className="bg-[#E7F4ED] rounded-2xl p-3 text-center">
            <p className="text-[20px] font-bold text-[#2B6349]">{active.length}</p>
            <p className="text-[10px] font-semibold text-[#2B6349] uppercase tracking-wide">Inside</p>
          </div>
          <div className="bg-[#F0EBE4] rounded-2xl p-3 text-center">
            <p className="text-[20px] font-bold text-[#78706A]">{exited.length}</p>
            <p className="text-[10px] font-semibold text-[#78706A] uppercase tracking-wide">Exited</p>
          </div>
        </div>
        <SectionHeader title="Today's Log · 22 Oct 2025" />
        <div className="flex flex-col gap-2">
          {VISITORS.map((v) => (
            <Card key={v.id} className="p-4">
              <div className="flex items-start justify-between gap-2 mb-1.5">
                <p className="text-[14px] font-semibold text-[#1A1714]">{v.name}</p>
                <Chip status={v.status} />
              </div>
              <p className="text-[12px] text-[#9C9490] mb-2">Flat {v.flat} · {v.host} · {v.purpose}</p>
              <div className="flex items-center justify-between">
                <div className="flex gap-3 text-[11px] text-[#78706A]">
                  {v.entryTime && <span>In: {v.entryTime}</span>}
                  {v.exitTime && <span>Out: {v.exitTime}</span>}
                  {!v.entryTime && <span>{v.time}</span>}
                </div>
                {v.status === "pending" && (
                  <div className="flex gap-1.5">
                    <button className="px-2.5 h-7 rounded-lg bg-[#E7F4ED] text-[#2B6349] text-[11px] font-semibold">Approve</button>
                    <button className="px-2.5 h-7 rounded-lg bg-[#FEE2E2] text-[#C53030] text-[11px] font-semibold">Decline</button>
                  </div>
                )}
              </div>
            </Card>
          ))}
        </div>
      </div>
    </div>
  );
}

function AdminStaff() {
  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <ScreenHeader title="Staff" action={<button className="w-8 h-8 flex items-center justify-center rounded-lg active:bg-[#F4EFE7]"><Plus size={17} color="#2B6349" /></button>} />
      <div className="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-2">
        <div className="flex gap-2 mb-1">
          <div className="flex-1 bg-[#E7F4ED] rounded-xl p-3 text-center">
            <p className="text-[18px] font-bold text-[#2B6349]">{STAFF.filter(s=>s.attendance==="present").length}</p>
            <p className="text-[10px] font-semibold text-[#2B6349] uppercase tracking-wide">Present</p>
          </div>
          <div className="flex-1 bg-[#FEE2E2] rounded-xl p-3 text-center">
            <p className="text-[18px] font-bold text-[#C53030]">{STAFF.filter(s=>s.attendance==="absent").length}</p>
            <p className="text-[10px] font-semibold text-[#C53030] uppercase tracking-wide">Absent</p>
          </div>
          <div className="flex-1 bg-[#F4EFE7] rounded-xl p-3 text-center">
            <p className="text-[18px] font-bold text-[#3D3830]">{STAFF.length}</p>
            <p className="text-[10px] font-semibold text-[#78706A] uppercase tracking-wide">Total</p>
          </div>
        </div>
        {STAFF.map((s) => (
          <Card key={s.id} className="p-4">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-[#EDE8DF] flex items-center justify-center flex-shrink-0"><User size={18} className="text-[#78706A]" /></div>
              <div className="flex-1 min-w-0">
                <div className="flex items-center justify-between gap-2">
                  <p className="text-[14px] font-semibold text-[#1A1714] truncate">{s.name}</p>
                  <Chip status={s.attendance} />
                </div>
                <p className="text-[12px] text-[#9C9490]">{s.role}</p>
                <p className="text-[11px] text-[#78706A] mt-0.5">{s.shift}</p>
              </div>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}

function AdminMore({ nav }: { nav: (u: Partial<Nav>) => void }) {
  const menuGroups = [
    {
      title: "Operations",
      items: [
        { icon: MessageSquare, label: "Complaints", sub: `${COMPLAINTS.filter(c=>c.status!=="resolved").length} open`, screen: "complaints", pale: "#FEF3C7", color: "#B45309" },
        { icon: DoorOpen,      label: "Visitors & Security", sub: `${VISITORS.filter(v=>v.status==="pending").length} pending approvals`, screen: "visitors", pale: "#EBF0FE", color: "#3B5ADB" },
        { icon: Users,         label: "Staff Management", sub: `${STAFF.filter(s=>s.attendance==="present").length} present today`, screen: "staff", pale: "#E7F4ED", color: "#2B6349" },
      ],
    },
    {
      title: "Society",
      items: [
        { icon: Star,      label: "Facilities & Bookings", sub: "4 facilities", screen: "facilities", pale: "#EDE9FE", color: "#7C3AED" },
        { icon: BellRing,  label: "Announcements", sub: `${ANNOUNCEMENTS.filter(a=>!a.read).length} unread`, screen: "announcements", pale: "#FEF3C7", color: "#B45309" },
        { icon: BarChart3, label: "Reports", sub: "Financial & operational", screen: "reports", pale: "#EBF0FE", color: "#3B5ADB" },
      ],
    },
    {
      title: "Account",
      items: [
        { icon: User,     label: "My Profile", sub: "Admin · Monarch Solitaire", screen: "profile", pale: "#F4EFE7", color: "#3D3830" },
        { icon: Settings, label: "Settings", sub: "App & notification settings", screen: "settings", pale: "#F4EFE7", color: "#3D3830" },
        { icon: LogOut,   label: "Sign Out", sub: "Securely sign out", screen: "logout", pale: "#FEE2E2", color: "#C53030" },
      ],
    },
  ];

  return (
    <div className="flex-1 overflow-y-auto">
      {/* Admin profile banner */}
      <div className="bg-white border-b border-[#EDE8DF] px-4 py-4 flex items-center gap-3 mb-2">
        <div className="w-12 h-12 rounded-2xl bg-[#2B6349] flex items-center justify-center">
          <User size={22} color="white" />
        </div>
        <div>
          <p className="text-[15px] font-bold text-[#1A1714]">Nilesh Joshi</p>
          <p className="text-[12px] text-[#78706A]">Society Admin · Monarch Solitaire</p>
        </div>
        <ChevronRight size={16} className="text-[#C8C0B8] ml-auto" />
      </div>

      {menuGroups.map((group) => (
        <div key={group.title} className="mb-2">
          <p className="px-4 py-2 text-[11px] font-semibold text-[#9C9490] uppercase tracking-widest">{group.title}</p>
          <Card className="mx-4 overflow-hidden">
            {group.items.map((item, i, arr) => (
              <div key={item.label}>
                <ListRow
                  icon={item.icon}
                  iconBg={item.pale}
                  label={item.label}
                  sub={item.sub}
                  onClick={() => nav({ screen: item.screen })}
                />
                {i < arr.length - 1 && <Divider />}
              </div>
            ))}
          </Card>
        </div>
      ))}
      <div className="h-4" />
    </div>
  );
}

function AnnouncementsList() {
  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <ScreenHeader title="Announcements" action={<button className="w-8 h-8 flex items-center justify-center rounded-lg active:bg-[#F4EFE7]"><Plus size={17} color="#2B6349" /></button>} />
      <div className="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-2">
        {ANNOUNCEMENTS.map((a) => (
          <Card key={a.id} className={`p-4 ${!a.read ? "border-l-4 border-l-[#2B6349]" : ""}`}>
            <div className="flex items-start justify-between gap-2 mb-1">
              <p className={`text-[13px] font-semibold leading-snug ${a.read ? "text-[#3D3830]" : "text-[#1A1714]"}`}>{a.title}</p>
              {a.important && <span className="flex-shrink-0 text-[10px] font-bold text-[#C53030] bg-[#FEE2E2] px-1.5 py-0.5 rounded-full uppercase">Important</span>}
            </div>
            <p className="text-[12px] text-[#9C9490] leading-relaxed mb-2">{a.body}</p>
            <p className="text-[11px] text-[#B0A99F]">{a.date}</p>
          </Card>
        ))}
      </div>
    </div>
  );
}

function FacilitiesList() {
  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <ScreenHeader title="Facilities" />
      <div className="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-3">
        {FACILITIES.map((f) => (
          <Card key={f.id} className="p-4">
            <div className="flex items-start justify-between gap-2 mb-2">
              <div>
                <p className="text-[14px] font-semibold text-[#1A1714]">{f.name}</p>
                <p className="text-[12px] text-[#9C9490] mt-0.5">{f.desc}</p>
              </div>
              <Chip status={f.status} />
            </div>
            <div className="flex items-center justify-between mt-2">
              <div className="flex items-center gap-1.5 text-[12px] text-[#78706A]">
                <Users size={12} /><span>Max {f.capacity}</span>
              </div>
              <p className="text-[12px] font-semibold text-[#2B6349]">{f.charge === 0 ? "Free" : `₹${f.charge}/booking`}</p>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}

// ─── OWNER SCREENS ────────────────────────────────────────────────────────────
const OWNER_TABS = [
  { id:"home",        label:"Home",        icon: Home       },
  { id:"maintenance", label:"Maintenance", icon: IndianRupee },
  { id:"visitors",    label:"Visitors",    icon: DoorOpen   },
  { id:"more",        label:"More",        icon: MoreVertical },
];

function OwnerHome({ nav }: { nav: (u: Partial<Nav>) => void }) {
  const myBill = BILLS.find(b => b.flat === "D-501");
  return (
    <div className="flex-1 overflow-y-auto">
      {/* Header */}
      <div className="bg-[#2B6349] px-4 pt-4 pb-16">
        <div className="flex items-center justify-between mb-4">
          <div>
            <p className="text-white/60 text-[12px] font-medium">Good morning</p>
            <p className="text-white text-[20px] font-bold">Ramesh Gupta</p>
          </div>
          <button className="relative w-9 h-9 rounded-xl bg-white/15 flex items-center justify-center">
            <Bell size={18} color="white" />
          </button>
        </div>
        <div className="bg-white/15 rounded-2xl px-4 py-3 flex items-center gap-3">
          <Building2 size={20} color="white" />
          <div>
            <p className="text-white text-[14px] font-semibold">Flat D-501 · Wing D</p>
            <p className="text-white/60 text-[11px]">Floor 5 · Monarch Solitaire</p>
          </div>
        </div>
      </div>

      {/* Maintenance due card */}
      <div className="-mt-10 px-4 mb-5">
        <Card className="p-4 shadow-sm">
          <div className="flex items-start justify-between mb-3">
            <div>
              <p className="text-[11px] font-semibold text-[#9C9490] uppercase tracking-widest mb-1">Maintenance Due</p>
              <p className="text-[28px] font-bold text-[#C53030]">₹3,500</p>
              <p className="text-[12px] text-[#9C9490]">October 2025 · Due 31 Oct</p>
            </div>
            <Chip status={myBill?.status ?? "pending"} />
          </div>
          <PrimaryBtn onClick={() => nav({ tab:"maintenance" })}>Pay Now</PrimaryBtn>
        </Card>
      </div>

      <div className="px-4 flex flex-col gap-5">
        {/* Quick actions */}
        <div>
          <SectionHeader title="Quick Access" />
          <div className="grid grid-cols-4 gap-2">
            {[
              { label:"Pay Bill",    icon: CreditCard,  pale:"#E7F4ED", color:"#2B6349", screen:"maintenance" },
              { label:"Visitors",    icon: DoorOpen,    pale:"#EBF0FE", color:"#3B5ADB", screen:"visitors"    },
              { label:"Complaint",   icon: MessageSquare,pale:"#FEF3C7",color:"#B45309", screen:"more"        },
              { label:"Facilities",  icon: Star,        pale:"#EDE9FE", color:"#7C3AED", screen:"more"        },
            ].map((q) => (
              <button key={q.label} onClick={() => nav({ tab:q.screen })} className="flex flex-col items-center gap-1.5 p-2.5 bg-white rounded-2xl border border-[#E8E1D8] active:scale-95 transition-transform">
                <div className="w-10 h-10 rounded-xl flex items-center justify-center" style={{ backgroundColor: q.pale }}>
                  <q.icon size={18} color={q.color} />
                </div>
                <span className="text-[10px] font-semibold text-[#3D3830] text-center leading-tight">{q.label}</span>
              </button>
            ))}
          </div>
        </div>

        {/* Announcements preview */}
        <div>
          <SectionHeader title="Announcements" action="See All" onAction={() => nav({ tab:"more", screen:"announcements" })} />
          <div className="flex flex-col gap-2">
            {ANNOUNCEMENTS.slice(0, 2).map((a) => (
              <Card key={a.id} className={`p-3.5 ${!a.read ? "border-l-4 border-l-[#2B6349]" : ""}`}>
                <div className="flex items-start justify-between gap-2 mb-1">
                  <p className="text-[13px] font-semibold text-[#1A1714] leading-snug flex-1">{a.title}</p>
                  {a.important && <span className="flex-shrink-0 text-[10px] font-bold text-[#C53030] bg-[#FEE2E2] px-1.5 py-0.5 rounded-full">!</span>}
                </div>
                <p className="text-[11px] text-[#9C9490]">{a.date}</p>
              </Card>
            ))}
          </div>
        </div>

        {/* Tenant info */}
        <div>
          <SectionHeader title="My Flat" />
          <Card className="p-4">
            <div className="flex items-center gap-3 mb-3">
              <div className="w-9 h-9 rounded-xl bg-[#EBF0FE] flex items-center justify-center"><User size={17} color="#3B5ADB" /></div>
              <div>
                <p className="text-[13px] font-semibold text-[#1A1714]">Meena Pillai</p>
                <p className="text-[11px] text-[#9C9490]">Current Tenant</p>
              </div>
              <Chip status="occupied" />
            </div>
            <div className="flex items-center gap-2 bg-[#F4EFE7] rounded-xl px-3 py-2.5">
              <Phone size={13} color="#2B6349" /><p className="text-[12px] font-medium text-[#3D3830]">98678 90123</p>
            </div>
          </Card>
        </div>
      </div>
      <div className="h-6" />
    </div>
  );
}

function OwnerMaintenance() {
  const [selected, setSelected] = useState<typeof BILLS[0] | null>(null);
  const myBills = BILLS.filter(b => b.flat === "D-501");

  if (selected) {
    return (
      <div className="flex-1 flex flex-col overflow-hidden">
        <ScreenHeader title="Bill Details" onBack={() => setSelected(null)} />
        <div className="flex-1 overflow-y-auto px-4 py-4 flex flex-col gap-4">
          <Card className="p-5">
            <div className="text-center mb-4">
              <p className="text-[11px] font-semibold text-[#9C9490] uppercase tracking-widest mb-1">{selected.months}</p>
              <p className="text-[32px] font-bold text-[#1A1714]">₹{selected.amount.toLocaleString("en-IN")}</p>
              <div className="mt-2 flex justify-center"><Chip status={selected.status} /></div>
            </div>
            <div className="h-px bg-[#EDE8DF] mb-4" />
            {[
              ["Flat", selected.flat],
              ["Period", selected.months],
              ["Amount", `₹${selected.amount.toLocaleString("en-IN")}`],
              ...(selected.dueDate ? [["Due Date", selected.dueDate]] : []),
              ...(selected.paidOn ? [["Paid On", selected.paidOn], ["Mode", selected.mode!], ["Receipt #", selected.receipt!]] : []),
            ].map(([k,v]) => (
              <div key={k} className="flex justify-between py-2.5 border-b border-[#F4EFE7] last:border-0">
                <p className="text-[13px] text-[#9C9490]">{k}</p>
                <p className="text-[13px] font-semibold text-[#1A1714]">{v}</p>
              </div>
            ))}
          </Card>
          {selected.status === "paid" && <PrimaryBtn><Download size={16} />Download Receipt</PrimaryBtn>}
          {selected.status === "pending" && <PrimaryBtn>Pay ₹{selected.amount.toLocaleString("en-IN")}</PrimaryBtn>}
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <ScreenHeader title="Maintenance" />
      <div className="flex-1 overflow-y-auto">
        {/* Prepaid status banner */}
        <div className="bg-[#E7F4ED] mx-4 mt-4 rounded-2xl p-4 flex items-center gap-3 border border-[#B7DECA]">
          <div className="w-9 h-9 rounded-xl bg-[#2B6349] flex items-center justify-center"><CheckCircle size={18} color="white" /></div>
          <div className="flex-1">
            <p className="text-[13px] font-semibold text-[#2B6349]">No prepaid balance</p>
            <p className="text-[11px] text-[#2B6349]/70">Pay 3 months in advance to avail discount</p>
          </div>
        </div>

        <div className="px-4 py-4 flex flex-col gap-3">
          <SectionHeader title="Payment History" />
          {myBills.length === 0 ? (
            <div className="flex flex-col items-center py-10 gap-3">
              <FileText size={28} className="text-[#9C9490]" />
              <p className="text-[14px] text-[#9C9490]">No bills found</p>
            </div>
          ) : myBills.map((b) => (
            <Card key={b.id} className="p-4" onClick={() => setSelected(b)}>
              <div className="flex items-start justify-between gap-2 mb-2">
                <div>
                  <p className="text-[14px] font-semibold text-[#1A1714]">{b.months}</p>
                  <p className="text-[12px] text-[#9C9490]">Flat {b.flat}</p>
                </div>
                <Chip status={b.status} />
              </div>
              <div className="flex items-center justify-between">
                <p className="text-[20px] font-bold text-[#1A1714]">₹{b.amount.toLocaleString("en-IN")}</p>
                {b.paidOn && <div className="flex items-center gap-1.5 text-[11px] text-[#9C9490]"><Download size={11} /><span>Receipt</span></div>}
                {b.dueDate && b.status!=="paid" && <p className="text-[11px] text-[#B45309] font-medium">Due {b.dueDate}</p>}
              </div>
            </Card>
          ))}
        </div>
      </div>
    </div>
  );
}

function OwnerVisitors() {
  const [tab, setTab] = useState("pending");
  const pending = VISITORS.filter(v => v.status === "pending" && v.flat === "D-501");
  const all = VISITORS.filter(v => v.flat === "D-501");
  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <ScreenHeader title="Visitors" action={<button className="w-8 h-8 flex items-center justify-center rounded-lg bg-[#E7F4ED] rounded-xl"><Plus size={17} color="#2B6349" /></button>} />
      <div className="flex bg-white border-b border-[#EDE8DF]">
        {["pending","all"].map(t => (
          <button key={t} onClick={() => setTab(t)} className={`flex-1 py-2.5 text-[13px] font-semibold border-b-2 capitalize transition ${tab===t?"border-[#2B6349] text-[#2B6349]":"border-transparent text-[#9C9490]"}`}>
            {t === "pending" ? `Approvals (${pending.length})` : "History"}
          </button>
        ))}
      </div>
      <div className="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-2">
        {(tab === "pending" ? pending : all).length === 0 ? (
          <div className="flex flex-col items-center py-16 gap-3">
            <DoorOpen size={32} className="text-[#C8C0B8]" />
            <p className="text-[14px] text-[#9C9490] font-medium">No visitors</p>
          </div>
        ) : (tab === "pending" ? pending : all).map((v) => (
          <Card key={v.id} className="p-4">
            <div className="flex items-start justify-between gap-2 mb-2">
              <p className="text-[14px] font-semibold text-[#1A1714]">{v.name}</p>
              <Chip status={v.status} />
            </div>
            <p className="text-[12px] text-[#9C9490] mb-2">{v.purpose} · {v.time ?? v.entryTime}</p>
            <div className="bg-[#F4EFE7] rounded-xl px-3 py-2 mb-3">
              <p className="text-[11px] text-[#78706A]">OTP for Guard</p>
              <p className="text-[18px] font-bold text-[#2B6349] tracking-[0.15em]">{v.otp}</p>
            </div>
            {v.status === "pending" && (
              <div className="flex gap-2">
                <PrimaryBtn sm onClick={() => {}}><CheckCircle size={14} />Approve</PrimaryBtn>
                <SecondaryBtn sm onClick={() => {}}><X size={14} />Decline</SecondaryBtn>
              </div>
            )}
          </Card>
        ))}
      </div>
    </div>
  );
}

function OwnerMore({ nav }: { nav: (u: Partial<Nav>) => void }) {
  return (
    <div className="flex-1 overflow-y-auto">
      <div className="bg-white border-b border-[#EDE8DF] px-4 py-4 flex items-center gap-3 mb-2">
        <div className="w-12 h-12 rounded-2xl bg-[#2B6349] flex items-center justify-center"><User size={22} color="white" /></div>
        <div><p className="text-[15px] font-bold text-[#1A1714]">Ramesh Gupta</p><p className="text-[12px] text-[#78706A]">Owner · Flat D-501</p></div>
      </div>
      {[
        { title:"Services", items:[
          { icon:MessageSquare, label:"My Complaints",    sub:"1 open",        pale:"#FEF3C7", color:"#B45309", screen:"" },
          { icon:Star,          label:"Facilities",       sub:"Book amenities",pale:"#EDE9FE", color:"#7C3AED", screen:"" },
          { icon:BellRing,      label:"Announcements",   sub:"2 unread",      pale:"#EBF0FE", color:"#3B5ADB", screen:"announcements" },
        ]},
        { title:"Account", items:[
          { icon:User,    label:"Profile & Settings", sub:"Update your details",       pale:"#F4EFE7", color:"#3D3830", screen:"" },
          { icon:Key,     label:"Change Password",    sub:"Update your password",      pale:"#F4EFE7", color:"#3D3830", screen:"" },
          { icon:LogOut,  label:"Sign Out",           sub:"Securely sign out",         pale:"#FEE2E2", color:"#C53030", screen:"" },
        ]},
      ].map(group => (
        <div key={group.title} className="mb-2">
          <p className="px-4 py-2 text-[11px] font-semibold text-[#9C9490] uppercase tracking-widest">{group.title}</p>
          <Card className="mx-4 overflow-hidden">
            {group.items.map((item, i, arr) => (
              <div key={item.label}>
                <ListRow icon={item.icon} iconBg={item.pale} label={item.label} sub={item.sub} onClick={() => item.screen ? nav({ screen: item.screen }) : undefined} />
                {i < arr.length - 1 && <Divider />}
              </div>
            ))}
          </Card>
        </div>
      ))}
    </div>
  );
}

// ─── TENANT SCREENS ───────────────────────────────────────────────────────────
const TENANT_TABS = [
  { id:"home",       label:"Home",       icon: Home        },
  { id:"visitors",   label:"Visitors",   icon: DoorOpen    },
  { id:"complaints", label:"Complaints", icon: MessageSquare },
  { id:"more",       label:"More",       icon: MoreVertical  },
];

function TenantHome({ nav }: { nav: (u: Partial<Nav>) => void }) {
  return (
    <div className="flex-1 overflow-y-auto">
      <div className="bg-[#2B6349] px-4 pt-4 pb-14">
        <div className="flex items-center justify-between">
          <div><p className="text-white/60 text-[12px]">Good morning</p><p className="text-white text-[20px] font-bold">Meena Pillai</p></div>
          <button className="w-9 h-9 rounded-xl bg-white/15 flex items-center justify-center"><Bell size={18} color="white" /></button>
        </div>
        <div className="mt-4 bg-white/15 rounded-2xl px-4 py-3 flex items-center gap-3">
          <Building2 size={20} color="white" />
          <div><p className="text-white text-[14px] font-semibold">Flat D-501 · Wing D</p><p className="text-white/60 text-[11px]">Tenant · Monarch Solitaire</p></div>
        </div>
      </div>
      <div className="-mt-8 px-4 mb-5">
        <div className="grid grid-cols-3 gap-2">
          {[
            { label:"Add Visitor",  icon: UserPlus,    pale:"#E7F4ED", color:"#2B6349", tab:"visitors" },
            { label:"Complaint",    icon: MessageSquare,pale:"#FEF3C7",color:"#B45309", tab:"complaints" },
            { label:"Facilities",   icon: Star,        pale:"#EDE9FE", color:"#7C3AED", tab:"more" },
          ].map((q) => (
            <button key={q.label} onClick={() => nav({ tab:q.tab })} className="bg-white rounded-2xl border border-[#E8E1D8] p-3 flex flex-col items-center gap-2 active:scale-95 transition-transform shadow-sm">
              <div className="w-10 h-10 rounded-xl flex items-center justify-center" style={{ backgroundColor: q.pale }}>
                <q.icon size={18} color={q.color} />
              </div>
              <span className="text-[11px] font-semibold text-[#3D3830]">{q.label}</span>
            </button>
          ))}
        </div>
      </div>
      <div className="px-4 flex flex-col gap-4">
        <div>
          <SectionHeader title="Announcements" action="See All" onAction={() => {}} />
          <div className="flex flex-col gap-2">
            {ANNOUNCEMENTS.map((a) => (
              <Card key={a.id} className={`p-3.5 ${!a.read ? "border-l-4 border-l-[#2B6349]" : ""}`}>
                <div className="flex justify-between items-start gap-2 mb-1">
                  <p className={`text-[13px] font-semibold leading-snug flex-1 ${!a.read ? "text-[#1A1714]" : "text-[#3D3830]"}`}>{a.title}</p>
                  {a.important && <span className="text-[10px] font-bold text-[#C53030] bg-[#FEE2E2] px-1.5 py-0.5 rounded-full">!</span>}
                </div>
                <p className="text-[11px] text-[#9C9490]">{a.date}</p>
              </Card>
            ))}
          </div>
        </div>
      </div>
      <div className="h-6" />
    </div>
  );
}

function TenantComplaints() {
  const [screen, setScreen] = useState("list");
  const myComplaints = COMPLAINTS.filter(c => c.flat === "D-501");

  if (screen === "new") {
    return (
      <div className="flex-1 flex flex-col overflow-hidden">
        <ScreenHeader title="Raise Complaint" onBack={() => setScreen("list")} />
        <div className="flex-1 overflow-y-auto px-4 py-4 flex flex-col gap-4">
          <div className="flex flex-col gap-1.5">
            <label className="text-[13px] font-medium text-[#3D3830]">Category</label>
            <div className="h-12 bg-white border border-[#E2DBD3] rounded-xl flex items-center px-4 gap-2 text-[14px] text-[#1A1714]">
              <span className="flex-1">Plumbing</span>
              <ChevronDown size={16} className="text-[#9C9490]" />
            </div>
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-[13px] font-medium text-[#3D3830]">Subject</label>
            <input className="h-12 bg-white border border-[#E2DBD3] rounded-xl px-4 text-[14px] text-[#1A1714] placeholder-[#B0A99F] focus:outline-none focus:border-[#2B6349]" placeholder="e.g. Water leakage in bathroom" />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-[13px] font-medium text-[#3D3830]">Description</label>
            <textarea className="bg-white border border-[#E2DBD3] rounded-xl px-4 py-3 text-[14px] text-[#1A1714] placeholder-[#B0A99F] focus:outline-none focus:border-[#2B6349] resize-none" rows={4} placeholder="Describe your issue in detail…" />
          </div>
          <div className="flex flex-col gap-1.5">
            <label className="text-[13px] font-medium text-[#3D3830]">Priority</label>
            <div className="flex gap-2">
              {["Low","Medium","High"].map((p) => (
                <button key={p} className={`flex-1 h-10 rounded-xl border text-[13px] font-semibold transition ${p==="Medium" ? "bg-[#2B6349] border-[#2B6349] text-white" : "border-[#E2DBD3] text-[#78706A]"}`}>{p}</button>
              ))}
            </div>
          </div>
          <button className="h-12 border-2 border-dashed border-[#E2DBD3] rounded-xl flex items-center justify-center gap-2 text-[13px] text-[#9C9490]">
            <Plus size={15} />Attach Photo (optional)
          </button>
          <PrimaryBtn onClick={() => setScreen("success")}><Send size={16} />Submit Complaint</PrimaryBtn>
        </div>
      </div>
    );
  }

  if (screen === "success") {
    return (
      <div className="flex-1 flex flex-col items-center justify-center px-8 gap-5">
        <div className="w-20 h-20 rounded-full bg-[#E7F4ED] flex items-center justify-center"><CheckCircle size={40} color="#2B6349" /></div>
        <div className="text-center">
          <p className="text-[20px] font-bold text-[#1A1714] mb-1">Complaint Raised</p>
          <p className="text-[14px] text-[#78706A] leading-relaxed">Your complaint has been submitted. You will receive updates as it progresses.</p>
        </div>
        <PrimaryBtn onClick={() => setScreen("list")}>Back to Complaints</PrimaryBtn>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <ScreenHeader title="My Complaints" action={<button onClick={() => setScreen("new")} className="w-8 h-8 rounded-xl bg-[#E7F4ED] flex items-center justify-center"><Plus size={17} color="#2B6349" /></button>} />
      <div className="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-2">
        {myComplaints.length === 0 ? (
          <div className="flex flex-col items-center py-16 gap-3">
            <div className="w-16 h-16 rounded-2xl bg-[#EDE8DF] flex items-center justify-center"><MessageSquare size={26} className="text-[#9C9490]" /></div>
            <p className="text-[15px] font-semibold text-[#3D3830]">No complaints yet</p>
            <p className="text-[13px] text-[#9C9490] text-center">Raise a complaint if you face any issue</p>
            <PrimaryBtn sm onClick={() => setScreen("new")}><Plus size={14} />Raise Complaint</PrimaryBtn>
          </div>
        ) : myComplaints.map((c) => (
          <Card key={c.id} className="p-4">
            <div className="flex items-start gap-2 mb-2">
              <p className="flex-1 text-[13px] font-semibold text-[#1A1714] leading-snug">{c.title}</p>
              <Chip status={c.status} />
            </div>
            <p className="text-[12px] text-[#9C9490] mb-2">{c.category} · {c.date}</p>
            <div className="flex items-center justify-between">
              <Chip status={c.priority} />
              {c.assigned && <p className="text-[11px] text-[#2B6349] font-medium">→ {c.assigned}</p>}
              {c.resolvedOn && <p className="text-[11px] text-[#9C9490]">Resolved {c.resolvedOn}</p>}
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}

function TenantMore() {
  return (
    <div className="flex-1 overflow-y-auto">
      <div className="bg-white border-b border-[#EDE8DF] px-4 py-4 flex items-center gap-3 mb-2">
        <div className="w-12 h-12 rounded-2xl bg-[#3B5ADB] flex items-center justify-center"><User size={22} color="white" /></div>
        <div><p className="text-[15px] font-bold text-[#1A1714]">Meena Pillai</p><p className="text-[12px] text-[#78706A]">Tenant · Flat D-501</p></div>
      </div>
      <Card className="mx-4 overflow-hidden mb-2">
        {[
          { icon:Star,      label:"Book Facilities",    sub:"Gym, court & more",    pale:"#EDE9FE", color:"#7C3AED" },
          { icon:BellRing,  label:"Announcements",      sub:"2 unread",             pale:"#EBF0FE", color:"#3B5ADB" },
          { icon:Info,      label:"Society Info",       sub:"Contact & guidelines", pale:"#F4EFE7", color:"#78706A" },
        ].map((item, i, arr) => (
          <div key={item.label}>
            <ListRow icon={item.icon} iconBg={item.pale} label={item.label} sub={item.sub} />
            {i < arr.length - 1 && <Divider />}
          </div>
        ))}
      </Card>
      <Card className="mx-4 overflow-hidden">
        {[
          { icon:User,   label:"Profile",          sub:"Update your details",  pale:"#F4EFE7", color:"#3D3830" },
          { icon:Key,    label:"Change Password",  sub:"Update your password", pale:"#F4EFE7", color:"#3D3830" },
          { icon:LogOut, label:"Sign Out",         sub:"Securely sign out",    pale:"#FEE2E2", color:"#C53030" },
        ].map((item, i, arr) => (
          <div key={item.label}>
            <ListRow icon={item.icon} iconBg={item.pale} label={item.label} sub={item.sub} />
            {i < arr.length - 1 && <Divider />}
          </div>
        ))}
      </Card>
    </div>
  );
}

// ─── GUARD SCREENS ────────────────────────────────────────────────────────────
const GUARD_TABS = [
  { id:"home",     label:"Home",     icon: Home        },
  { id:"visitors", label:"Visitors", icon: DoorOpen    },
  { id:"history",  label:"History",  icon: ClipboardList },
  { id:"more",     label:"More",     icon: MoreVertical  },
];

function GuardHome({ nav }: { nav: () => void }) {
  const pending = VISITORS.filter(v => v.status === "pending");
  const inside = VISITORS.filter(v => v.status === "active");

  return (
    <div className="flex-1 overflow-y-auto">
      {/* Header */}
      <div className="bg-[#1E3D2B] px-4 py-4">
        <div className="flex items-center justify-between mb-1">
          <p className="text-white/60 text-[12px]">On Duty</p>
          <div className="flex items-center gap-1.5 bg-[#2B6349] px-2.5 py-1 rounded-full">
            <div className="w-1.5 h-1.5 rounded-full bg-[#4ADE80] animate-pulse" />
            <p className="text-[11px] font-semibold text-white">Active</p>
          </div>
        </div>
        <p className="text-white text-[20px] font-bold mb-4">Mahesh Kumar</p>
        <div className="grid grid-cols-3 gap-2">
          {[
            { label:"Pending", value: pending.length, color:"#FEF3C7", text:"#B45309" },
            { label:"Inside",  value: inside.length,  color:"#E7F4ED", text:"#2B6349" },
            { label:"Exited",  value: VISITORS.filter(v=>v.status==="exited").length, color:"#F0EBE4", text:"#78706A" },
          ].map(s => (
            <div key={s.label} className="rounded-xl p-3 text-center" style={{ backgroundColor: s.color }}>
              <p className="text-[24px] font-bold" style={{ color: s.text }}>{s.value}</p>
              <p className="text-[10px] font-semibold uppercase tracking-wide" style={{ color: s.text }}>{s.label}</p>
            </div>
          ))}
        </div>
      </div>

      {/* OTP verify */}
      <div className="px-4 py-4">
        <button
          onClick={() => nav()}
          className="w-full h-14 bg-[#2B6349] rounded-2xl flex items-center justify-center gap-3 shadow active:scale-[0.99] transition-transform"
        >
          <div className="w-8 h-8 rounded-xl bg-white/20 flex items-center justify-center"><Key size={18} color="white" /></div>
          <span className="text-white font-bold text-[16px]">Verify Visitor OTP</span>
        </button>
      </div>

      {/* Pending approvals */}
      <div className="px-4 pb-4 flex flex-col gap-3">
        <SectionHeader title={`Pending Approvals (${pending.length})`} />
        {pending.length === 0 ? (
          <div className="flex flex-col items-center py-8 gap-2">
            <CheckCircle size={28} className="text-[#2B6349]" />
            <p className="text-[14px] text-[#9C9490]">No pending approvals</p>
          </div>
        ) : pending.map((v) => (
          <Card key={v.id} className="p-4">
            <div className="flex items-start justify-between gap-2 mb-2">
              <div>
                <p className="text-[15px] font-semibold text-[#1A1714]">{v.name}</p>
                <p className="text-[12px] text-[#9C9490]">Flat {v.flat} · {v.host}</p>
              </div>
              <span className="text-[11px] font-medium text-[#9C9490]">{v.time}</span>
            </div>
            <p className="text-[12px] text-[#78706A] mb-3">{v.purpose}</p>
            <div className="flex gap-2">
              <button className="flex-1 h-11 bg-[#2B6349] rounded-xl text-white font-semibold text-[13px] flex items-center justify-center gap-1.5 active:opacity-90">
                <DoorOpen size={15} />Allow Entry
              </button>
              <button className="flex-1 h-11 border border-[#C53030] rounded-xl text-[#C53030] font-semibold text-[13px] flex items-center justify-center gap-1.5 active:opacity-90">
                <X size={15} />Deny
              </button>
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}

function GuardVisitors({ initScreen }: { initScreen?: string }) {
  const [screen, setScreen] = useState(initScreen ?? "list");
  const [otp, setOtp] = useState("");
  const [verifying, setVerifying] = useState(false);
  const [verified, setVerified] = useState(false);

  if (screen === "otp") {
    const verifyOtp = () => {
      setVerifying(true);
      setTimeout(() => {
        setVerifying(false);
        if (otp === VISITORS[0].otp) setVerified(true);
      }, 1200);
    };

    if (verified) {
      return (
        <div className="flex-1 flex flex-col overflow-hidden">
          <ScreenHeader title="OTP Verified" onBack={() => { setVerified(false); setOtp(""); setScreen("list"); }} />
          <div className="flex-1 flex flex-col items-center justify-center px-6 gap-5">
            <div className="w-20 h-20 rounded-full bg-[#E7F4ED] flex items-center justify-center"><CheckCircle size={40} color="#2B6349" /></div>
            <div className="text-center">
              <p className="text-[20px] font-bold text-[#1A1714] mb-1">OTP Verified!</p>
              <p className="text-[14px] text-[#78706A]">{VISITORS[0].name} can enter Flat A-204</p>
            </div>
            <Card className="w-full p-4">
              {[["Visitor",VISITORS[0].name],["Flat","A-204"],["Host","Priya Sharma"],["Purpose","Family Visit"]].map(([k,v])=>(
                <div key={k} className="flex justify-between py-2 border-b border-[#F4EFE7] last:border-0"><p className="text-[13px] text-[#9C9490]">{k}</p><p className="text-[13px] font-semibold text-[#1A1714]">{v}</p></div>
              ))}
            </Card>
            <PrimaryBtn onClick={() => { setVerified(false); setOtp(""); setScreen("list"); }}>Record Entry &amp; Done</PrimaryBtn>
          </div>
        </div>
      );
    }

    return (
      <div className="flex-1 flex flex-col overflow-hidden">
        <ScreenHeader title="Verify OTP" onBack={() => setScreen("list")} />
        <div className="flex-1 flex flex-col items-center justify-center px-6 gap-6">
          <div className="text-center">
            <div className="w-16 h-16 rounded-2xl bg-[#E7F4ED] flex items-center justify-center mx-auto mb-4"><Key size={28} color="#2B6349" /></div>
            <p className="text-[18px] font-bold text-[#1A1714] mb-1">Enter Visitor OTP</p>
            <p className="text-[13px] text-[#78706A]">Ask the visitor for the OTP shared by the resident</p>
          </div>
          <div className="w-full flex flex-col gap-4">
            <div className="flex justify-center gap-3">
              {[0,1,2,3,4,5].map(i => (
                <div key={i} className={`w-11 h-14 rounded-xl border-2 flex items-center justify-center text-[22px] font-bold transition ${otp[i] ? "border-[#2B6349] bg-white text-[#2B6349]" : "border-[#E2DBD3] bg-white text-transparent"}`}>
                  {otp[i] || "·"}
                </div>
              ))}
            </div>
            <InputField placeholder="Type OTP here" value={otp} onChange={(v: string) => setOtp(v.replace(/\D/g,"").slice(0,6))} />
            <PrimaryBtn onClick={verifyOtp} disabled={otp.length < 6 || verifying}>
              {verifying ? <RefreshCw size={17} className="animate-spin" /> : <><ShieldCheck size={17} />Verify OTP</>}
            </PrimaryBtn>
            {otp.length === 6 && !verifying && otp !== VISITORS[0].otp && (
              <div className="flex items-center gap-2 bg-[#FEE2E2] rounded-xl px-3.5 py-3">
                <AlertCircle size={15} color="#C53030" />
                <p className="text-[13px] text-[#C53030] font-medium">Invalid OTP. Please check and try again.</p>
              </div>
            )}
            <p className="text-center text-[11px] text-[#9C9490]">Hint: try {VISITORS[0].otp}</p>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <div className="px-4 py-3 bg-white border-b border-[#EDE8DF]">
        <div className="flex items-center justify-between mb-2">
          <p className="text-[18px] font-bold text-[#1A1714]">Visitors</p>
          <button onClick={() => setScreen("otp")} className="flex items-center gap-1.5 px-3 h-8 rounded-xl bg-[#E7F4ED] text-[#2B6349] text-[12px] font-semibold"><Key size={13} />Verify OTP</button>
        </div>
      </div>
      <div className="flex-1 overflow-y-auto px-4 py-3 flex flex-col gap-2">
        {VISITORS.map((v) => (
          <Card key={v.id} className="p-4">
            <div className="flex items-start justify-between gap-2 mb-1.5">
              <p className="text-[14px] font-semibold text-[#1A1714]">{v.name}</p>
              <Chip status={v.status} />
            </div>
            <p className="text-[12px] text-[#9C9490] mb-2">Flat {v.flat} · {v.host} · {v.purpose}</p>
            <div className="flex justify-between text-[11px] text-[#78706A]">
              {v.entryTime && <span>In: {v.entryTime}</span>}
              {v.exitTime ? <span>Out: {v.exitTime}</span> : v.status==="active" ? (
                <button className="text-[#C53030] font-semibold">Record Exit</button>
              ) : null}
              {!v.entryTime && <span>Expected: {v.time}</span>}
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}

function GuardHistory() {
  return (
    <div className="flex-1 flex flex-col overflow-hidden">
      <div className="px-4 py-3 bg-white border-b border-[#EDE8DF]">
        <div className="flex items-center justify-between mb-2">
          <p className="text-[18px] font-bold text-[#1A1714]">Visitor Log</p>
        </div>
        <SearchBar placeholder="Search visitor or flat…" value="" onChange={() => {}} />
      </div>
      <div className="flex-1 overflow-y-auto px-4 py-3">
        <p className="text-[11px] font-semibold text-[#9C9490] uppercase tracking-widest mb-2 px-0.5">Today · 22 Oct 2025</p>
        <div className="flex flex-col gap-2">
          {VISITORS.map((v) => (
            <Card key={v.id} className="px-4 py-3 flex items-center gap-3">
              <div className={`w-9 h-9 rounded-xl flex items-center justify-center flex-shrink-0 ${v.status==="active" ? "bg-[#E7F4ED]" : v.status==="exited" ? "bg-[#F0EBE4]" : "bg-[#FEF3C7]"}`}>
                <DoorOpen size={16} color={v.status==="active" ? "#2B6349" : v.status==="exited" ? "#78706A" : "#B45309"} />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-[13px] font-semibold text-[#1A1714] truncate">{v.name}</p>
                <p className="text-[11px] text-[#9C9490]">Flat {v.flat} · {v.purpose}</p>
              </div>
              <div className="text-right flex-shrink-0">
                <Chip status={v.status} />
                <p className="text-[10px] text-[#B0A99F] mt-1">{v.entryTime ?? v.time}</p>
              </div>
            </Card>
          ))}
        </div>
      </div>
    </div>
  );
}

function GuardMore() {
  return (
    <div className="flex-1 overflow-y-auto">
      <div className="bg-white border-b border-[#EDE8DF] px-4 py-4 flex items-center gap-3 mb-2">
        <div className="w-12 h-12 rounded-2xl bg-[#1E3D2B] flex items-center justify-center"><Shield size={22} color="white" /></div>
        <div><p className="text-[15px] font-bold text-[#1A1714]">Mahesh Kumar</p><p className="text-[12px] text-[#78706A]">Security Guard · Morning Shift</p></div>
      </div>
      <p className="px-4 py-2 text-[11px] font-semibold text-[#9C9490] uppercase tracking-widest">Emergency Contacts</p>
      <Card className="mx-4 overflow-hidden mb-3">
        {[
          { name:"Society Admin", phone:"98765 00000", role:"Admin — Nilesh Joshi" },
          { name:"Police Control", phone:"100", role:"Emergency" },
          { name:"Fire Station", phone:"101", role:"Emergency" },
          { name:"Ambulance", phone:"108", role:"Emergency" },
        ].map((c, i, arr) => (
          <div key={c.name}>
            <div className="flex items-center gap-3 px-4 py-3.5">
              <div className="w-9 h-9 rounded-xl bg-[#FEE2E2] flex items-center justify-center flex-shrink-0"><Phone size={15} color="#C53030" /></div>
              <div className="flex-1"><p className="text-[14px] font-medium text-[#1A1714]">{c.name}</p><p className="text-[11px] text-[#9C9490]">{c.role}</p></div>
              <p className="text-[13px] font-bold text-[#2B6349]">{c.phone}</p>
            </div>
            {i < arr.length - 1 && <Divider />}
          </div>
        ))}
      </Card>
      <Card className="mx-4 overflow-hidden">
        {[
          { icon:User,   label:"My Profile",       sub:"View & edit details",  pale:"#F4EFE7", color:"#3D3830" },
          { icon:LogOut, label:"End Shift & Exit",  sub:"Sign out of duty",    pale:"#FEE2E2", color:"#C53030" },
        ].map((item, i, arr) => (
          <div key={item.label}>
            <ListRow icon={item.icon} iconBg={item.pale} label={item.label} sub={item.sub} />
            {i < arr.length - 1 && <Divider />}
          </div>
        ))}
      </Card>
    </div>
  );
}

// ─── PHONE FRAME ─────────────────────────────────────────────────────────────
function PhoneFrame({ children }: { children: React.ReactNode }) {
  return (
    <div className="relative flex-shrink-0" style={{ width: 390, height: 790 }}>
      {/* Outer bezel */}
      <div className="absolute inset-0 rounded-[48px] bg-[#1C1C1E] shadow-2xl" />
      {/* Screen */}
      <div className="absolute rounded-[40px] overflow-hidden flex flex-col" style={{ inset: 9, backgroundColor: "#F4EFE7" }}>
        {children}
      </div>
    </div>
  );
}

// ─── APP ROOT ─────────────────────────────────────────────────────────────────
export default function App() {
  const [nav, setNav] = useState<Nav>({ view:"demo", tab:"dashboard", screen:"main", detail: null });
  const go = (updates: Partial<Nav>) => setNav(prev => ({ ...prev, screen:"main", detail:null, ...updates }));

  // ── Demo picker ──────────────────────────────────────────────────────────
  if (nav.view === "demo") {
    return (
      <div className="min-h-screen bg-[#EDE8DF] flex flex-col items-center justify-center py-8 px-4 gap-8">
        <div className="text-center">
          <div className="flex items-center justify-center gap-3 mb-2">
            <div className="w-10 h-10 rounded-2xl bg-[#2B6349] flex items-center justify-center"><Building2 size={20} color="white" /></div>
            <p className="text-[26px] font-bold text-[#1A1714] tracking-tight">Apna Society</p>
          </div>
          <p className="text-[14px] text-[#78706A]">UI Design Preview · Monarch Solitaire A–E</p>
        </div>

        <div className="grid grid-cols-2 gap-3 w-full max-w-sm">
          {([
            { view:"auth",   label:"Authentication",  sub:"Login & welcome screens",   icon: Lock,      pale:"#E7F4ED", color:"#2B6349" },
            { view:"admin",  label:"Admin App",        sub:"Full management console",   icon: LayoutGrid, pale:"#EBF0FE", color:"#3B5ADB" },
            { view:"owner",  label:"Owner App",        sub:"Billing & residents",       icon: Building2,  pale:"#FEF3C7", color:"#B45309" },
            { view:"tenant", label:"Tenant App",       sub:"Complaints & visitors",     icon: Users,      pale:"#EDE9FE", color:"#7C3AED" },
            { view:"guard",  label:"Guard App",        sub:"Entry & OTP verification",  icon: Shield,     pale:"#FEE2E2", color:"#C53030" },
          ] as const).map((role) => (
            <button
              key={role.view}
              onClick={() => go({ view: role.view as View, tab: role.view === "admin" ? "dashboard" : role.view === "guard" ? "home" : "home", screen: role.view === "auth" ? "welcome" : "main" })}
              className={`bg-white rounded-3xl border border-[#E8E1D8] p-4 flex flex-col gap-3 text-left active:scale-[0.97] transition-transform shadow-sm ${role.view === "auth" ? "col-span-2" : ""}`}
            >
              <div className="w-11 h-11 rounded-2xl flex items-center justify-center" style={{ backgroundColor: role.pale }}>
                <role.icon size={21} color={role.color} />
              </div>
              <div>
                <p className="text-[14px] font-bold text-[#1A1714]">{role.label}</p>
                <p className="text-[12px] text-[#9C9490] mt-0.5">{role.sub}</p>
              </div>
            </button>
          ))}
        </div>
        <p className="text-[12px] text-[#B0A99F] text-center">Select a role above to preview the app experience</p>
      </div>
    );
  }

  // ── Auth ─────────────────────────────────────────────────────────────────
  if (nav.view === "auth") {
    return (
      <div className="min-h-screen bg-[#EDE8DF] flex flex-col items-center justify-center py-8 gap-4">
        <button onClick={() => go({ view:"demo" })} className="flex items-center gap-1.5 text-[13px] text-[#78706A] font-medium self-start ml-6 mb-2">
          ← Back to Demo
        </button>
        <PhoneFrame>
          <StatusBar />
          {nav.screen === "welcome" ? (
            <WelcomeScreen onLogin={() => go({ screen:"login" })} />
          ) : nav.screen === "login" ? (
            <LoginScreen onLogin={() => go({ view:"admin", tab:"dashboard" })} />
          ) : (
            <SplashScreen onDone={() => go({ screen:"welcome" })} />
          )}
        </PhoneFrame>
        <div className="flex gap-2 flex-wrap justify-center max-w-xs">
          {[["Splash","splash"],["Welcome","welcome"],["Login","login"]].map(([label, s]) => (
            <button key={s} onClick={() => go({ screen:s })} className={`px-3 h-7 rounded-full text-[12px] font-semibold transition ${nav.screen===s?"bg-[#2B6349] text-white":"bg-white border border-[#E2DBD3] text-[#78706A]"}`}>{label}</button>
          ))}
        </div>
      </div>
    );
  }

  // ── Shared app shell renderer ─────────────────────────────────────────────
  const renderAdmin = () => {
    const subScreens: Record<string, React.ReactNode> = {
      complaints:    <AdminComplaints />,
      visitors:      <AdminVisitors />,
      staff:         <AdminStaff />,
      announcements: <AnnouncementsList />,
      facilities:    <FacilitiesList />,
      "resident-detail": nav.detail ? <ResidentDetail resident={nav.detail} onBack={() => go({ tab:nav.tab, screen:"main" })} /> : null,
    };
    const tabContent: Record<string, React.ReactNode> = {
      dashboard: <AdminDashboard nav={go} />,
      residents:  <AdminResidents nav={go} />,
      billing:    <AdminBilling />,
      more:       nav.screen !== "main" && subScreens[nav.screen]
                    ? subScreens[nav.screen]
                    : <AdminMore nav={(u) => go({ tab:"more", ...u })} />,
    };

    if (nav.tab === "residents" && nav.screen === "resident-detail" && nav.detail) {
      return <ResidentDetail resident={nav.detail} onBack={() => go({ tab:"residents", screen:"main" })} />;
    }
    return tabContent[nav.tab] ?? <AdminDashboard nav={go} />;
  };

  const renderOwner = () => {
    const more = <OwnerMore nav={(u) => go({ tab:"more", ...u })} />;
    const tabContent: Record<string, React.ReactNode> = {
      home:        <OwnerHome nav={go} />,
      maintenance: <OwnerMaintenance />,
      visitors:    <OwnerVisitors />,
      more:        nav.screen === "announcements" ? <AnnouncementsList /> : more,
    };
    return tabContent[nav.tab] ?? <OwnerHome nav={go} />;
  };

  const renderTenant = () => ({
    home:       <TenantHome nav={go} />,
    visitors:   <OwnerVisitors />,
    complaints: <TenantComplaints />,
    more:       <TenantMore />,
  }[nav.tab] ?? <TenantHome nav={go} />);

  const renderGuard = () => {
    if (nav.tab === "visitors" && nav.screen === "otp") {
      return <GuardVisitors initScreen="otp" />;
    }
    const onOTP = () => go({ tab:"visitors", screen:"otp" });
    return ({
      home:     <GuardHome nav={onOTP} />,
      visitors: <GuardVisitors />,
      history:  <GuardHistory />,
      more:     <GuardMore />,
    }[nav.tab] ?? <GuardHome nav={onOTP} />);
  };

  const tabs = {
    admin:  ADMIN_TABS,
    owner:  OWNER_TABS,
    tenant: TENANT_TABS,
    guard:  GUARD_TABS,
  }[nav.view as Role] ?? ADMIN_TABS;

  const content = {
    admin:  renderAdmin(),
    owner:  renderOwner(),
    tenant: renderTenant(),
    guard:  renderGuard(),
  }[nav.view as Role];

  const roleLabels = { admin:"Admin", owner:"Owner", tenant:"Tenant", guard:"Guard" };

  return (
    <div className="min-h-screen bg-[#EDE8DF] flex flex-col items-center justify-center py-6 gap-4">
      <div className="flex items-center gap-3">
        <button onClick={() => go({ view:"demo" })} className="flex items-center gap-1.5 text-[12px] text-[#78706A] font-medium bg-white border border-[#E2DBD3] px-3 h-7 rounded-full">← Demo</button>
        <div className="flex items-center gap-2 bg-white border border-[#E2DBD3] px-3 h-7 rounded-full">
          <div className="w-2 h-2 rounded-full bg-[#2B6349]" />
          <p className="text-[12px] font-semibold text-[#1A1714]">{roleLabels[nav.view as Role]} App</p>
        </div>
        <div className="flex gap-1.5">
          {tabs.map(t => (
            <button
              key={t.id}
              onClick={() => go({ tab:t.id })}
              className={`px-3 h-7 rounded-full text-[11px] font-semibold transition ${nav.tab===t.id ? "bg-[#2B6349] text-white" : "bg-white border border-[#E2DBD3] text-[#78706A]"}`}
            >{t.label}</button>
          ))}
        </div>
      </div>

      <PhoneFrame>
        <StatusBar />
        <div className="flex-1 flex flex-col overflow-hidden">
          {content}
        </div>
        {!["resident-detail","otp"].includes(nav.screen) && (
          <BottomNav
            items={tabs}
            active={nav.tab}
            onChange={(id) => go({ tab:id })}
          />
        )}
      </PhoneFrame>

      <p className="text-[11px] text-[#B0A99F]">Monarch Solitaire A–E · Apna Society v2.4.1</p>
    </div>
  );
}
