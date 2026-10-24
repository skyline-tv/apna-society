import { useEffect } from 'react'
import { Link, NavLink, Route, Routes, useLocation } from 'react-router-dom'
import {
  APP, DEVELOPER, DEVELOPER_SITE, home, landing, mainNav, pages,
  type Block, type PageDef,
} from './content'

function Text({ t }: { t: string }) {
  return <>{t.split(/(\[TO CONFIRM[^\]]*\])/).map((s, i) => s.startsWith('[TO CONFIRM') ? <mark key={i}>{s}</mark> : s)}</>
}
function Blocks({ body }: { body: Block[] }) {
  return <>{body.map((b, i) => Array.isArray(b)
    ? <ul key={i}>{b.map((li, j) => <li key={j}><Text t={li} /></li>)}</ul>
    : <p key={i}><Text t={b} /></p>)}</>
}
function useTitle(t: string) { useEffect(() => { document.title = t }, [t]) }

function ScrollToTop() {
  const { pathname, hash } = useLocation()
  useEffect(() => {
    if (!hash) {
      window.scrollTo(0, 0)
      return
    }
    const id = decodeURIComponent(hash.slice(1))
    let tries = 0
    let timer = 0
    const go = () => {
      const el = document.getElementById(id)
      if (el) { el.scrollIntoView(); return }
      if (tries++ < 10) timer = window.setTimeout(go, 16)
    }
    go()
    return () => window.clearTimeout(timer)
  }, [pathname, hash])
  return null
}

function Doc({ page }: { page: PageDef }) {
  useTitle(page.title)
  const toc = page.sections.map(s => <li key={s.id}><a href={`#${s.id}`}>{s.title}</a></li>)
  return (
    <div className="wrap doc">
      <header className="doc-head">
        <h1>{page.nav === 'Account Deletion' ? 'Delete your account' : page.nav}</h1>
        <p className="lede">{page.intro}</p>
        {page.updated && <p className="updated">Last updated {page.updated}</p>}
      </header>
      <details className="toc-m"><summary>On this page</summary><ol>{toc}</ol></details>
      <nav className="toc-d" aria-label="On this page"><p>On this page</p><ol>{toc}</ol></nav>
      <article>
        {page.sections.map(s => <section key={s.id} id={s.id} aria-labelledby={`${s.id}-h`}><h2 id={`${s.id}-h`}>{s.title}</h2><Blocks body={s.body} /></section>)}
      </article>
    </div>
  )
}

const featureMarks: Record<string, string> = {
  billing: 'M6 4h12a1 1 0 0 1 1 1v16l-3.2-1.6L12 21l-3.8-1.6L5 21V5a1 1 0 0 1 1-1zm3 5h6M9 13h6M9 17h3',
  visitors: 'M16 11a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM8 12a3.5 3.5 0 1 0 0-7 3.5 3.5 0 0 0 0 7zM2.5 20a5.5 5.5 0 0 1 11 0M13 20a5 5 0 0 1 9 0',
  vehicles: 'M4 16v2a1 1 0 0 0 1 1h1.5a1.5 1.5 0 0 0 3 0h5a1.5 1.5 0 0 0 3 0H19a1 1 0 0 0 1-1v-2M4 16l1.2-6.2A2 2 0 0 1 7.16 8h9.68a2 2 0 0 1 1.96 1.8L20 16M4 16h16M8 11h8',
  roles: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21a8 8 0 0 1 16 0',
  collections: 'M4 7h16v12H4zM4 11h16M8 7V5h8v2',
  announce: 'M5 10v4a2 2 0 0 0 2 2h2l5 4V6l-5 4H7a2 2 0 0 0-2 2zm14-1.5a6 6 0 0 1 0 9',
}

function Mark({ d }: { d: string }) {
  return (
    <svg className="mark" viewBox="0 0 24 24" aria-hidden="true">
      <path fill="none" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" d={d} />
    </svg>
  )
}

function PhoneMock() {
  const m = landing.mock
  return (
    <div className="phone" aria-hidden="true">
      <div className="phone-bezel">
        <div className="phone-bar"><span /><span /></div>
        <p className="phone-eye">{m.society}</p>
        <p className="phone-role">{m.role}</p>
        <div className="phone-card">
          <p>{m.dueLabel}</p>
          <strong>{m.dueValue}</strong>
        </div>
        <div className="phone-card">
          <p>{m.visitLabel}</p>
          <strong>{m.visitValue}</strong>
        </div>
        <div className="phone-tabs">{m.tabs.map(t => <span key={t}>{t}</span>)}</div>
      </div>
    </div>
  )
}

function Home() {
  useTitle(home.title)
  const store = landing.storeCta.to
  return (
    <div className="land">
      <section className="hero">
        <div className="wrap hero-grid">
          <div className="hero-copy">
            <p className="eyebrow">{landing.eyebrow}</p>
            <h1>{landing.headline}</h1>
            <p className="lede">{landing.lede}</p>
            <div className="hero-actions">
              {store
                ? <a className="btn" href={store} rel="noopener noreferrer">{landing.storeCta.label}</a>
                : <Link className="btn" to={landing.primaryCta.to}>{landing.primaryCta.label}</Link>}
              <Link className="btn btn-ghost" to={landing.secondaryCta.to}>{landing.secondaryCta.label}</Link>
            </div>
          </div>
          <PhoneMock />
        </div>
      </section>

      <section className="band" id="features" aria-labelledby="features-h">
        <div className="wrap">
          <header className="band-head">
            <h2 id="features-h">{landing.featuresTitle}</h2>
            <p className="lede">{landing.featuresLede}</p>
          </header>
          <ul className="feat">
            {landing.features.map(f => (
              <li key={f.id}>
                <Mark d={featureMarks[f.id] ?? featureMarks.roles} />
                <h3>{f.title}</h3>
                <p>{f.body}</p>
              </li>
            ))}
          </ul>
        </div>
      </section>

      <section className="band band-alt" id="roles" aria-labelledby="roles-h">
        <div className="wrap">
          <header className="band-head">
            <h2 id="roles-h">{landing.rolesTitle}</h2>
            <p className="lede">{landing.rolesLede}</p>
          </header>
          <ul className="roles">
            {landing.roles.map(r => (
              <li key={r.id}>
                <h3>{r.title}</h3>
                <p>{r.body}</p>
              </li>
            ))}
          </ul>
        </div>
      </section>

      <section className="band" id="how" aria-labelledby="how-h">
        <div className="wrap">
          <header className="band-head">
            <h2 id="how-h">{landing.howTitle}</h2>
          </header>
          <ol className="steps">
            {landing.steps.map(s => (
              <li key={s.n}>
                <span className="step-n">{s.n}</span>
                <h3>{s.title}</h3>
                <p>{s.body}</p>
              </li>
            ))}
          </ol>
        </div>
      </section>

      <section className="cta" aria-labelledby="cta-h">
        <div className="wrap">
          <h2 id="cta-h">{landing.ctaTitle}</h2>
          <p className="lede">{landing.ctaBody}</p>
          <Link className="btn btn-light" to={landing.ctaButton.to}>{landing.ctaButton.label}</Link>
        </div>
      </section>
    </div>
  )
}

export default function App() {
  return (
    <>
      <ScrollToTop />
      <a className="skip" href="#main">Skip to content</a>
      <header className="site-head"><div className="wrap">
        <Link to="/" className="brand">
          <img src="/app-icon.png" alt="" width="32" height="32" />
          {APP}
        </Link>
        <nav aria-label="Main">
          {mainNav.map(item => item.to.includes('#')
            ? <Link key={item.to} to={item.to}>{item.label}</Link>
            : <NavLink key={item.to} to={item.to}>{item.label}</NavLink>)}
        </nav>
      </div></header>
      <main id="main">
        <Routes>
          <Route path="/" element={<Home />} />
          {pages.map(p => <Route key={p.path} path={p.path} element={<Doc page={p} />} />)}
          <Route path="*" element={<Home />} />
        </Routes>
      </main>
      <footer className="site-foot"><div className="wrap">
        <p>{APP} by <a href={DEVELOPER_SITE}>{DEVELOPER}</a></p>
        <nav aria-label="Footer">{pages.map(p => <Link key={p.path} to={p.path}>{p.nav}</Link>)}</nav>
      </div></footer>
    </>
  )
}
