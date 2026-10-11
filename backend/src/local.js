import {app} from './server.js';
const port = Number(process.env.PORT || 8080);
app.listen(port, '127.0.0.1', () => console.log(`Local Firebase API listening on ${port}`));
