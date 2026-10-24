import { renderToString } from 'react-dom/server'
import { StaticRouter } from 'react-router-dom/server'
import App from './App'
import { home, pages } from './content'
export function render(url: string) { return renderToString(<StaticRouter location={url}><App /></StaticRouter>) }
export function meta(url: string) { const p = pages.find(x => x.path === url); return p ? { title: p.title, description: p.description } : home }
export { routes } from './content'
