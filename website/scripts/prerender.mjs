import fs from 'node:fs'
import path from 'node:path'
import { pathToFileURL } from 'node:url'
const { render, meta, routes } = await import(pathToFileURL(path.resolve('dist-ssr/entry-server.js')).href)
const tpl = fs.readFileSync('dist/index.html', 'utf8')
const site = (process.env.SITE_URL || '').replace(/\/$/, '')
const esc = s => s.replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;')
const todos = []
for (const url of routes) {
  const m = meta(url)
  const head = `<title>${esc(m.title)}</title>\n<meta name="description" content="${esc(m.description)}" />\n<meta name="robots" content="index,follow" />` +
    (site ? `\n<link rel="canonical" href="${site}${url}" />` : '')
  const app = render(url)
  for (const t of app.match(/\[TO CONFIRM[^\]]*\]/g) ?? []) todos.push(`${url}: ${t.replace(/&#x27;/g, "'")}`)
  const html = tpl.replace('<!--head-->', head).replace('<!--app-->', app)
  const out = url === '/' ? 'dist/index.html' : `dist${url}/index.html`
  fs.mkdirSync(path.dirname(out), { recursive: true }); fs.writeFileSync(out, html)
}
fs.rmSync('dist-ssr', { recursive: true, force: true })
console.log(`Prerendered ${routes.length} routes.`)
if (!site) console.warn('WARN: SITE_URL not set, so no canonical links were written. Build with SITE_URL=https://your-domain')
if (todos.length) console.warn(`\nWARN: ${todos.length} unconfirmed item(s) still on the pages:\n - ` + todos.join('\n - '))
