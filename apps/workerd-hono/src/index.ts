import { Hono } from 'hono'

const app = new Hono()

app.get('/', (c) => c.text('Hello'))
app.get('/json', (c) => c.json({ hello: 'world' }))
app.get('/params/:id', (c) => c.text(c.req.param('id')))
app.post('/echo', async (c) => {
  const body = await c.req.raw.arrayBuffer()
  return new Response(body, {
    headers: { 'content-type': c.req.header('content-type') ?? 'application/octet-stream' },
  })
})

export default app
