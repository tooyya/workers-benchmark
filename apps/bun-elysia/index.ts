import { Elysia } from 'elysia'

new Elysia()
  .get('/', () => 'Hello')
  .get('/json', () => ({ hello: 'world' }))
  .get('/params/:id', ({ params: { id } }) => id)
  .post('/echo', ({ body }) => body)
  .listen(Number(process.env.PORT ?? 3001))
