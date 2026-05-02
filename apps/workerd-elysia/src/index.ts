import { Elysia } from 'elysia'
import { CloudflareAdapter } from 'elysia/adapter/cloudflare-worker'

export default new Elysia({ adapter: CloudflareAdapter })
  .get('/', () => 'Hello')
  .get('/json', () => ({ hello: 'world' }))
  .get('/params/:id', ({ params: { id } }) => id)
  .post('/echo', ({ body }) => body)
  .compile()
